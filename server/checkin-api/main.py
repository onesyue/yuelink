from telemetry import router_dashboard as telemetry_dashboard_router
"""
YueLink App Checkin API
Standalone FastAPI service for daily check-in rewards.
Auth: delegates to XBoard /api/v1/user/info to validate token, then resolves
v2_user.id by email from DB (XBoard user/info does NOT return id).
"""

import os
import ipaddress
import random
import time
import socket
import logging
import datetime
import hashlib
import subprocess
from datetime import datetime as _dt, timedelta as _td
try:
    from zoneinfo import ZoneInfo
    _TZ_SH = ZoneInfo('Asia/Shanghai')
except ImportError:
    import pytz
    _TZ_SH = pytz.timezone('Asia/Shanghai')
from contextlib import asynccontextmanager, contextmanager
import urllib.request
import urllib.error
import json as _json

import psycopg2
import psycopg2.pool
import psycopg2.extras
from fastapi import FastAPI, Depends, HTTPException, Header, Request as _Request, Response as _Response
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from apscheduler.schedulers.background import BackgroundScheduler
from collections import defaultdict as _defaultdict
from dotenv import load_dotenv

load_dotenv()

# ─── Config ──────────────────────────────────────────────────────────────────

DB_HOST = os.getenv('DB_HOST', '127.0.0.1')
DB_PORT = int(os.getenv('DB_PORT', '5432'))
DB_NAME = os.getenv('DB_NAME', 'yue-to')
DB_USER = os.getenv('DB_USER', 'root')
DB_PASSWORD = os.getenv('DB_PASSWORD', '')

TELEMETRY_DATABASE_DSN = os.getenv('TELEMETRY_DATABASE_DSN', '').strip()
TELEMETRY_SCHEMA = os.getenv('TELEMETRY_SCHEMA', 'telemetry').strip() or 'telemetry'
TELEMETRY_ID_SALT = os.getenv('TELEMETRY_ID_SALT', 'yuelink-anonymous-telemetry-v1')
TELEMETRY_NODE_INVENTORY_PATH = os.getenv(
    'TELEMETRY_NODE_INVENTORY_PATH',
    '/opt/checkin-api/nodes-inventory-path-map.json',
)
TELEMETRY_CYMRU_TIMEOUT = float(os.getenv('TELEMETRY_CYMRU_TIMEOUT', '1.0'))

# Direct to XBoard origin — NOT through CloudFront.
# CloudFront→origin is unreliable, and XBoard nginx blocks non-CF traffic
# + python-urllib UA.  The direct URL bypasses both issues.
XBOARD_BASE = os.getenv('XBOARD_BASE', 'http://66.55.76.208:8001')

# Account center config — fall back to empty string (not null) so client
# always gets a string field even when env vars are unset.
RENEWAL_URL        = os.getenv('RENEWAL_URL',        'https://yue.to/#/plan')
FEEDBACK_URL       = os.getenv('FEEDBACK_URL',       'https://t.me/yuetong_support')
TELEGRAM_GROUP_URL = os.getenv('TELEGRAM_GROUP_URL', 'https://t.me/yuetong_group')
STATUS_PAGE_URL    = os.getenv('STATUS_PAGE_URL',    'https://status.yue.to')

PERIODIC_TRAFFIC = 10737418240   # 10GB
ONE_TIME_TRAFFIC  = 3221225472   # 3GB
BALANCE_CHOICES  = [0.2, 0.3, 0.5, 0.6, 0.8, 1.0]

# ─── 签到随机奖池（与 Bot 签到同步 v7.2）───────────────────────────────────────
# (权重, 类型)
SIGN_REWARD_POOL = [
    (40, 'traffic'),     # 流量（连签加成生效）
    (30, 'balance'),     # 余额随机
    (15, 'both'),        # 双奖：流量50% + 余额0.3
    (10, 'points'),      # 积分 3-8
    (5,  'lucky'),       # 幸运大奖：流量 ×2.5
]

STREAK_MULTIPLIER = {30: 1.5, 15: 1.3, 8: 1.2}  # 连签流量加成
STREAK_BONUS = {7: 1.0, 14: 2.0, 30: 5.0, 60: 10.0, 90: 20.0}  # 里程碑余额奖励

def _get_streak_multiplier(streak):
    for days, mult in sorted(STREAK_MULTIPLIER.items(), reverse=True):
        if streak >= days:
            return mult
    return 1.0

def _pick_reward():
    total = sum(w for w, _ in SIGN_REWARD_POOL)
    r = random.randint(1, total)
    cum = 0
    for w, t in SIGN_REWARD_POOL:
        cum += w
        if r <= cum:
            return t
    return 'traffic'

logger = logging.getLogger('checkin')
logging.basicConfig(level=logging.INFO)

# ─── Database ────────────────────────────────────────────────────────────────

pool = psycopg2.pool.ThreadedConnectionPool(
    minconn=2, maxconn=12,
    host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
    user=DB_USER, password=DB_PASSWORD, connect_timeout=10,
)

_telemetry_pool = None
_telemetry_schema_ready = False

if TELEMETRY_DATABASE_DSN:
    try:
        _telemetry_pool = psycopg2.pool.ThreadedConnectionPool(
            minconn=1,
            maxconn=4,
            dsn=TELEMETRY_DATABASE_DSN,
            connect_timeout=5,
        )
    except Exception as e:
        logger.warning('Telemetry DB disabled: %s', e)
        _telemetry_pool = None


def _telemetry_schema_name() -> str:
    # Environment-controlled identifier; keep it conservative because it is interpolated.
    if TELEMETRY_SCHEMA.replace('_', '').isalnum():
        return TELEMETRY_SCHEMA
    return 'telemetry'


_TEL_SCHEMA = _telemetry_schema_name()
_telemetry_path_cache = {'mtime': None, 'by_id': {}}
_telemetry_client_net_cache = {}


def _telemetry_sql(name: str) -> str:
    return f'"{_TEL_SCHEMA}"."{name}"'


@contextmanager
def get_telemetry_cursor():
    if _telemetry_pool is None:
        yield None
        return
    conn = cursor = None
    try:
        conn = _telemetry_pool.getconn()
        cursor = conn.cursor()
        yield cursor
        conn.commit()
    except Exception:
        if conn:
            try:
                conn.rollback()
            except Exception:
                pass
        raise
    finally:
        if cursor:
            try:
                cursor.close()
            except Exception:
                pass
        if conn:
            try:
                _telemetry_pool.putconn(conn)
            except Exception:
                pass


def _ensure_telemetry_schema(cur) -> None:
    global _telemetry_schema_ready
    if _telemetry_schema_ready or cur is None:
        return

    schema = f'"{_TEL_SCHEMA}"'
    cur.execute(f"CREATE SCHEMA IF NOT EXISTS {schema}")
    cur.execute(f"""
        CREATE TABLE IF NOT EXISTS {_telemetry_sql('events')} (
            id BIGSERIAL PRIMARY KEY,
            ts BIGINT NOT NULL,
            server_ts BIGINT NOT NULL,
            day DATE NOT NULL,
            event TEXT NOT NULL,
            client_id TEXT,
            session_id TEXT,
            platform TEXT,
            version TEXT,
            props JSONB
        )
    """)
    cur.execute(f"""
        CREATE TABLE IF NOT EXISTS {_telemetry_sql('node_events')} (
            id BIGSERIAL PRIMARY KEY,
            ts BIGINT NOT NULL,
            day DATE NOT NULL,
            client_id TEXT,
            platform TEXT,
            version TEXT,
            event TEXT NOT NULL,
            fp TEXT,
            type TEXT,
            region TEXT,
            delay_ms INTEGER,
            ok SMALLINT,
            reason TEXT,
            group_name TEXT
        )
    """)
    cur.execute(f"""
        CREATE TABLE IF NOT EXISTS {_telemetry_sql('node_identity')} (
            identity_id BIGSERIAL PRIMARY KEY,
            current_fp TEXT UNIQUE,
            label TEXT,
            protocol TEXT,
            region TEXT,
            sid TEXT,
            xb_server_id INTEGER,
            first_seen BIGINT NOT NULL,
            last_seen BIGINT NOT NULL,
            retired_at BIGINT
        )
    """)
    cur.execute(f"""
        CREATE TABLE IF NOT EXISTS {_telemetry_sql('node_fp_history')} (
            fp TEXT PRIMARY KEY,
            identity_id BIGINT NOT NULL REFERENCES {_telemetry_sql('node_identity')}(identity_id),
            bound_at BIGINT NOT NULL,
            retired_at BIGINT
        )
    """)
    cur.execute(f"""
        CREATE TABLE IF NOT EXISTS {_telemetry_sql('nps_responses')} (
            id BIGSERIAL PRIMARY KEY,
            ts BIGINT NOT NULL,
            day DATE NOT NULL,
            client_id TEXT,
            platform TEXT,
            version TEXT,
            score SMALLINT NOT NULL,
            comment TEXT
        )
    """)
    cur.execute(f"""
        CREATE TABLE IF NOT EXISTS {_telemetry_sql('feature_flags')} (
            key TEXT PRIMARY KEY,
            value_json TEXT NOT NULL,
            rollout_pct INTEGER DEFAULT 100,
            updated_at BIGINT NOT NULL
        )
    """)
    cur.execute(f"CREATE INDEX IF NOT EXISTS idx_events_day_event ON {_telemetry_sql('events')} (day, event)")
    cur.execute(f"CREATE INDEX IF NOT EXISTS idx_events_client ON {_telemetry_sql('events')} (client_id)")
    cur.execute(f"CREATE INDEX IF NOT EXISTS idx_events_session ON {_telemetry_sql('events')} (session_id)")
    cur.execute(f"CREATE INDEX IF NOT EXISTS idx_events_props ON {_telemetry_sql('events')} USING GIN (props)")
    cur.execute(f"CREATE INDEX IF NOT EXISTS idx_node_events_day ON {_telemetry_sql('node_events')} (day)")
    cur.execute(f"CREATE INDEX IF NOT EXISTS idx_node_events_event ON {_telemetry_sql('node_events')} (event)")
    cur.execute(f"CREATE INDEX IF NOT EXISTS idx_node_events_fp_day ON {_telemetry_sql('node_events')} (fp, day)")
    cur.execute(f"CREATE INDEX IF NOT EXISTS idx_nps_day ON {_telemetry_sql('nps_responses')} (day)")
    _telemetry_schema_ready = True

@contextmanager
def get_cursor(dictionary=True):
    conn = cursor = None
    try:
        conn = pool.getconn()
        cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor if dictionary else None)
        yield cursor
        conn.commit()
    except psycopg2.Error:
        if conn:
            try: conn.rollback()
            except Exception: pass
        raise
    finally:
        if cursor:
            try: cursor.close()
            except Exception: pass
        if conn:
            try: pool.putconn(conn)
            except Exception: pass

# ─── Auth via XBoard ─────────────────────────────────────────────────────────

def validate_token(authorization: str = Header(...)) -> int:
    """
    Validate by calling XBoard /api/v1/user/info with the token.
    XBoard user/info does NOT return ``id`` — resolve v2_user.id by email from DB.

    Error mapping:
      XBoard 401/403          → HTTP 401  {"status":"error","message":"invalid_token"}
      XBoard timeout (>5s)    → HTTP 503  {"status":"error","message":"upstream_timeout"}
      other network / non-200 → HTTP 502  (upstream error, details not exposed)
    """
    req = urllib.request.Request(
        f'{XBOARD_BASE}/api/v1/user/info',
        headers={'Authorization': authorization, 'Accept': 'application/json'},
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            body = _json.loads(resp.read())
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            raise HTTPException(status_code=401, detail='invalid_token')
        raise HTTPException(status_code=502, detail='upstream_error')
    except (socket.timeout, urllib.error.URLError) as e:
        # URLError wraps socket.timeout on Python 3.x
        is_timeout = isinstance(e, socket.timeout) or (
            isinstance(e, urllib.error.URLError) and isinstance(e.reason, socket.timeout)
        )
        if is_timeout:
            logger.warning('XBoard auth timeout')
            raise HTTPException(status_code=503, detail='upstream_timeout')
        logger.warning('XBoard auth network error: %s', e)
        raise HTTPException(status_code=502, detail='upstream_error')
    except Exception as e:
        logger.warning('XBoard auth error: %s', e)
        raise HTTPException(status_code=502, detail='upstream_error')

    if body.get('status', '') != 'success':
        raise HTTPException(status_code=401, detail='invalid_token')

    user_data = body.get('data', {}) or {}
    email = user_data.get('email')
    if not email:
        raise HTTPException(status_code=401, detail='invalid_token')

    # Resolve v2_user.id by email — XBoard user/info omits id from response.
    with get_cursor() as cur:
        cur.execute('SELECT id FROM v2_user WHERE email = %s', (email,))
        row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=401, detail='invalid_token')
    return int(row['id'])

# ─── Checkin logic ────────────────────────────────────────────────────────────

def _get_user(user_id: int):
    with get_cursor() as cur:
        cur.execute('SELECT * FROM v2_user WHERE id = %s', (user_id,))
        return cur.fetchone()

def _check_can_checkin(user):
    if not user:
        return False, 'User not found'
    if user.get('app_sign') == '1':
        return False, 'already_checked'
    # Treat NULL as 0
    transfer_enable = int(user['transfer_enable'] or 0)
    u = int(user['u'] or 0)
    d = int(user['d'] or 0)
    expired_at = user['expired_at']
    if transfer_enable == 0 and (expired_at is None or expired_at == 0):
        return False, 'No active subscription'
    now = int(time.time())
    if expired_at is not None and expired_at > 0:
        if now > expired_at:
            return False, 'Subscription expired'
        # 流量耗尽 + 无下次重置（next_reset_at 为 None 或 == expired_at）才拦截
        # 若 next_reset_at < expired_at，说明还有流量重置日，放行（等重置即可）
        if (transfer_enable > 0
                and u + d >= transfer_enable
                and (user.get('next_reset_at') is None
                     or user['next_reset_at'] == expired_at)):
            return False, 'Traffic exhausted'
        if transfer_enable > 0:
            return True, ''
    if expired_at is None or expired_at == 0:
        if transfer_enable > 0 and u + d >= transfer_enable:
            return False, 'Traffic exhausted'
        if transfer_enable > 0:
            return True, ''
    return False, 'Cannot check in'

def _is_periodic(user):
    expired_at = user['expired_at']
    return expired_at is not None and expired_at > 0

def _apply_traffic(user, traffic):
    """扣减已用流量（通用）"""
    uid = user['id']
    u = int(user['u'] or 0)
    d = int(user['d'] or 0)
    with get_cursor() as cur:
        if u + d <= traffic:
            cur.execute("UPDATE v2_user SET u=0, d=0 WHERE id=%s", (uid,))
        elif d >= traffic:
            cur.execute("UPDATE v2_user SET d=d-%s WHERE id=%s", (traffic, uid))
        else:
            cur.execute("UPDATE v2_user SET u=u-%s, d=0 WHERE id=%s", (traffic - d, uid))


def _mark_signed(user, streak):
    """标记已签到 + 更新连签"""
    with get_cursor() as cur:
        cur.execute("UPDATE v2_user SET app_sign='1', app_sign_streak=%s WHERE id=%s",
                    (streak, user['id']))


def _record_sign_history(user_id: int, sign_date, streak: int,
                         reward_type: str = None, reward_value: int = 0,
                         source: str = 'normal'):
    """落 app_sign_history 一行。失败仅日志，不影响主流程。"""
    try:
        with get_cursor() as cur:
            cur.execute(
                """INSERT INTO app_sign_history
                     (user_id, sign_date, streak, reward_type, reward_value, source)
                   VALUES (%s, %s, %s, %s, %s, %s)
                   ON CONFLICT (user_id, sign_date) DO UPDATE
                     SET streak       = EXCLUDED.streak,
                         reward_type  = EXCLUDED.reward_type,
                         reward_value = EXCLUDED.reward_value,
                         source       = EXCLUDED.source""",
                (user_id, sign_date, streak, reward_type, reward_value, source),
            )
    except Exception:
        logger.exception('record_app_sign_history failed user=%s date=%s', user_id, sign_date)


def _unified_reward(user):
    """统一签到奖励（与 Bot v7.2 同步的随机奖池）"""
    streak = int(user.get('app_sign_streak') or 0) + 1
    multiplier = _get_streak_multiplier(streak)
    base_traffic = PERIODIC_TRAFFIC if _is_periodic(user) else ONE_TIME_TRAFFIC

    reward_type = _pick_reward()
    rewards = []  # [{type, amount, text}]

    if reward_type == 'traffic':
        t = int(base_traffic * multiplier)
        _apply_traffic(user, t)
        gb = t / (1024**3)
        rewards.append({'type': 'traffic', 'amount': t, 'text': f'+{gb:.0f}GB 流量'})

    elif reward_type == 'balance':
        bal = random.choice(BALANCE_CHOICES)
        cents = int(bal * 100)
        with get_cursor() as cur:
            cur.execute("UPDATE v2_user SET balance=balance+%s WHERE id=%s", (cents, user['id']))
        rewards.append({'type': 'balance', 'amount': cents, 'text': f'+{bal}元余额'})

    elif reward_type == 'both':
        t = int(base_traffic * multiplier * 0.5)
        _apply_traffic(user, t)
        gb = t / (1024**3)
        bal = 0.3
        cents = int(bal * 100)
        with get_cursor() as cur:
            cur.execute("UPDATE v2_user SET balance=balance+%s WHERE id=%s", (cents, user['id']))
        rewards.append({'type': 'traffic', 'amount': t, 'text': f'+{gb:.0f}GB 流量'})
        rewards.append({'type': 'balance', 'amount': cents, 'text': f'+{bal}元余额'})

    elif reward_type == 'points':
        pts = random.choice([3, 4, 5, 6, 8])
        try:
            with get_cursor() as cur:
                cur.execute("UPDATE user_account SET gambling_points = COALESCE(gambling_points,0) + %s WHERE account_id = %s",
                            (pts, user['id']))
        except Exception:
            pass
        rewards.append({'type': 'points', 'amount': pts, 'text': f'+{pts} 竞猜积分'})

    elif reward_type == 'lucky':
        t = int(base_traffic * multiplier * 2.5)
        _apply_traffic(user, t)
        gb = t / (1024**3)
        rewards.append({'type': 'lucky', 'amount': t, 'text': f'+{gb:.0f}GB 流量（幸运大奖 ×2.5）'})

    # 连签里程碑奖励
    milestone_bonus = STREAK_BONUS.get(streak)
    if milestone_bonus:
        cents = int(milestone_bonus * 100)
        with get_cursor() as cur:
            cur.execute("UPDATE v2_user SET balance=balance+%s WHERE id=%s", (cents, user['id']))
        rewards.append({'type': 'milestone', 'amount': cents, 'text': f'连签{streak}天奖励 +{milestone_bonus}元'})

    _mark_signed(user, streak)

    # 落历史（amount 单位：traffic→GB, balance/milestone→分, points→pts, lucky→GB）
    today = _dt.now(_TZ_SH).date()
    primary_for_hist = rewards[0] if rewards else None
    _hist_value = 0
    if primary_for_hist:
        if primary_for_hist['type'] in ('traffic', 'lucky'):
            _hist_value = int(primary_for_hist['amount'] / (1024**3))
        else:
            _hist_value = int(primary_for_hist['amount'])
    _record_sign_history(
        user_id=user['id'],
        sign_date=today,
        streak=streak,
        reward_type=reward_type,
        reward_value=_hist_value,
        source='normal',
    )

    amount_text = ' / '.join(r['text'] for r in rewards)
    primary = rewards[0] if rewards else {'type': 'traffic', 'amount': 0}
    return {
        'type': primary['type'],
        'amount': primary['amount'],
        'amount_text': amount_text,
        'reward_type': reward_type,
        'rewards': rewards,
        'streak': streak,
        'multiplier': multiplier,
    }

# ─── Midnight reset ────────────────────────────────────────────────────────────

def clear_app_sign():
    """每日凌晨重置签到标志。未签到用户 streak 减半（断签不归零），已签到用户清标志保留 streak。"""
    with get_cursor(dictionary=False) as cur:
        # 1. 未签到的用户：streak 减半（断签惩罚，但不归零保留一些动力）
        cur.execute("UPDATE v2_user SET app_sign_streak = app_sign_streak / 2 WHERE app_sign = '0' AND app_sign_streak > 0")
        missed = cur.rowcount
        # 2. 已签到的用户：清标志（streak 保留，下次签到 +1）
        cur.execute("UPDATE v2_user SET app_sign = '0' WHERE app_sign = '1'")
        cleared = cur.rowcount
    logger.info('Daily reset: cleared %d signed users, halved streak for %d missed users', cleared, missed)

# ─── App ─────────────────────────────────────────────────────────────────────

scheduler = BackgroundScheduler()

@asynccontextmanager
async def lifespan(app):
    scheduler.add_job(clear_app_sign, 'cron', hour=0, minute=0, timezone='Asia/Shanghai')
    scheduler.add_job(_cleanup_ai_rate, 'interval', minutes=5)
    scheduler.add_job(_ticket_worker, 'interval', seconds=30)       # 每 30 秒扫描新工单
    scheduler.add_job(_auto_resolve_worker, 'interval', minutes=5)  # 每 5 分钟节点恢复回填
    scheduler.start()
    logger.info('Checkin API started')
    yield
    scheduler.shutdown()

app = FastAPI(title='YueLink Checkin API', lifespan=lifespan)
app.include_router(telemetry_dashboard_router)

# CORS — allow yue.to widget to call /api/faq/
from fastapi.middleware.cors import CORSMiddleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=['https://yue.to', 'https://www.yue.to'],
    allow_origin_regex=r'https://[a-z0-9\-]+\.yue\.to',
    allow_methods=['GET', 'POST', 'OPTIONS'],
    allow_headers=['*'],
    expose_headers=['Content-Type'],
    allow_credentials=True,
)

# ─── Static files (Crisp-like widget hosting) ───────────────────────────────
# 官网 + XBoard 面板共用同一份 chat-widget.js，只需一行 <script> 即可接入。
# 更新 widget 时只改这个文件，不需要改主题配置。

_STATIC_DIR = os.path.join(os.path.dirname(__file__), 'static')

@app.get('/static/{filename:path}')
def serve_static(filename: str):
    filepath = os.path.join(_STATIC_DIR, filename)
    if not os.path.isfile(filepath) or '..' in filename:
        raise HTTPException(status_code=404, detail='not_found')
    content_type = 'application/javascript' if filename.endswith('.js') else 'text/plain'
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    return _Response(
        content=content, media_type=content_type,
        headers={
            'Cache-Control': 'public, max-age=3600',
            'Access-Control-Allow-Origin': '*',
        },
    )

# ─── Unified error responses ─────────────────────────────────────────────────
# Map FastAPI/Starlette HTTPException → {"status":"error","message":"..."}
# so all error responses share the same envelope as success responses.

@app.exception_handler(HTTPException)
async def http_exception_handler(request: _Request, exc: HTTPException):
    return JSONResponse(
        status_code=exc.status_code,
        content={'status': 'error', 'message': exc.detail},
    )

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: _Request, exc: RequestValidationError):
    # Missing authorization header → 401
    errors = exc.errors()
    for e in errors:
        if e.get('loc') and 'authorization' in [str(x).lower() for x in e['loc']]:
            return JSONResponse(status_code=401, content={'status': 'error', 'message': 'invalid_token'})
    return JSONResponse(
        status_code=422,
        content={'status': 'error', 'message': 'invalid_request'},
    )

# ─── Simple rate limiter ──────────────────────────────────────────────────────
_rate_store: dict[str, list[float]] = _defaultdict(list)
_RATE_LIMIT = 10  # max requests per window
_RATE_WINDOW = 60  # seconds

@app.middleware("http")
async def rate_limit_middleware(request: _Request, call_next):
    if request.url.path.startswith('/api/client/'):
        client_ip = request.client.host or ""
        # Only trust X-Forwarded-For when behind nginx (loopback)
        if client_ip in ("127.0.0.1", "::1"):
            ip = request.headers.get("x-forwarded-for", client_ip).split(",")[0].strip()
        else:
            ip = client_ip
        now = time.time()
        recent = [t for t in _rate_store[ip] if now - t < _RATE_WINDOW]
        if len(recent) >= _RATE_LIMIT:
            # 更新过滤后的列表，顺便清理过期时间戳
            _rate_store[ip] = recent
            return _Response(
                content='{"status":"error","message":"rate_limited"}',
                status_code=429, media_type='application/json',
            )
        # 列表为空说明该 IP 长期无请求，直接替换而非追加，防止 defaultdict key 无限积累
        _rate_store[ip] = recent + [now]
    return await call_next(request)


@app.post('/api/client/checkin')
def checkin(user_id: int = Depends(validate_token)):
    user = _get_user(user_id)
    if not user:
        return {'status': 'error', 'message': 'User not found'}
    can, reason = _check_can_checkin(user)
    if reason == 'already_checked':
        return {'status': 'success', 'data': {'type': '', 'amount': 0, 'amount_text': '', 'already_checked': True}}
    if not can:
        return {'status': 'error', 'message': reason}
    result = _unified_reward(user)
    return {'status': 'success', 'data': {
        'type': result['type'],
        'amount': result['amount'],
        'amount_text': result['amount_text'],
        'already_checked': False,
        'reward_type': result['reward_type'],
        'rewards': result['rewards'],
        'streak': result['streak'],
        'multiplier': result['multiplier'],
    }}

@app.get('/api/client/checkin/status')
def checkin_status(user_id: int = Depends(validate_token)):
    user = _get_user(user_id)
    if not user:
        return {'status': 'error', 'message': 'User not found'}
    checked = user.get('app_sign') == '1'
    streak = int(user.get('app_sign_streak') or 0)
    return {'status': 'success', 'data': {
        'type': '', 'amount': 0, 'amount_text': '', 'already_checked': checked,
        'streak': streak, 'multiplier': _get_streak_multiplier(streak),
    }}


SIGN_CARD_COST = 25  # 与 telegram bot gambling/config.py POINTS_EXCHANGE['sign_card'] 对齐


@app.get('/api/client/checkin/history')
def checkin_history(month: str = '', user_id: int = Depends(validate_token)):
    """月历数据：返回 user_id 在指定月份的全部签到记录（含补签卡条目）。

    `month` 格式 YYYY-MM；省略则取当前月。返回每天一行 + 月度汇总。
    """
    today = _dt.now(_TZ_SH).date()
    if month:
        try:
            year_i, month_i = int(month[:4]), int(month[5:7])
            first = datetime.date(year_i, month_i, 1)
        except (ValueError, IndexError):
            return {'status': 'error', 'message': 'invalid month format, expect YYYY-MM'}
    else:
        first = today.replace(day=1)
        year_i, month_i = first.year, first.month

    if month_i == 12:
        last = datetime.date(year_i + 1, 1, 1) - _td(days=1)
    else:
        last = datetime.date(year_i, month_i + 1, 1) - _td(days=1)

    with get_cursor() as cur:
        cur.execute(
            """SELECT sign_date, streak, reward_type, reward_value, source
               FROM app_sign_history
               WHERE user_id = %s AND sign_date >= %s AND sign_date <= %s
               ORDER BY sign_date""",
            (user_id, first, last),
        )
        rows = cur.fetchall() or []

    user = _get_user(user_id)
    today_signed = user.get('app_sign') == '1' if user else False
    streak = int((user or {}).get('app_sign_streak') or 0)

    # 取 gambling_points 同表查询，避免前端补签弹窗再单独发一次请求
    gambling_points = 0
    try:
        with get_cursor() as cur:
            cur.execute(
                'SELECT COALESCE(gambling_points, 0) AS pts FROM user_account WHERE account_id=%s',
                (user_id,),
            )
            row = cur.fetchone()
            if row:
                gambling_points = int(row.get('pts') or 0)
    except Exception:
        logger.exception('history: query gambling_points failed user=%s', user_id)

    days = []
    for r in rows:
        days.append({
            'date': r['sign_date'].isoformat(),
            'streak': r['streak'],
            'reward_type': r['reward_type'],
            'reward_value': r['reward_value'],
            'source': r['source'],
        })

    return {'status': 'success', 'data': {
        'month': f'{year_i:04d}-{month_i:02d}',
        'days_in_month': (last - first).days + 1,
        'today': today.isoformat(),
        'today_signed': today_signed,
        'streak': streak,
        'multiplier': _get_streak_multiplier(streak),
        'gambling_points': gambling_points,
        'sign_card_cost': SIGN_CARD_COST,
        'days': days,
    }}


@app.post('/api/client/checkin/resign')
def checkin_resign(user_id: int = Depends(validate_token)):
    """补签卡：扣 25 积分，给昨天补 1 行 history，streak += 1。

    与 telegram bot 的 supplement_sign 行为对齐：仅能补昨天，不能补更早。
    前置检查：今天未签 + 昨天未签 + 积分≥25。
    """
    user = _get_user(user_id)
    if not user:
        return {'status': 'error', 'message': 'User not found'}

    if user.get('app_sign') == '1':
        return {'status': 'error', 'message': 'today_already_checked'}

    today = _dt.now(_TZ_SH).date()
    yesterday = today - _td(days=1)

    # 检查 yesterday 是否已经在历史里（之前签过 / 用过补签卡）
    with get_cursor() as cur:
        cur.execute(
            "SELECT 1 FROM app_sign_history WHERE user_id=%s AND sign_date=%s",
            (user_id, yesterday),
        )
        if cur.fetchone():
            return {'status': 'error', 'message': 'yesterday_already_signed'}

    # 检查积分
    with get_cursor() as cur:
        cur.execute(
            "SELECT COALESCE(gambling_points, 0) AS pts FROM user_account WHERE account_id=%s",
            (user_id,),
        )
        row = cur.fetchone()
        points = int((row or {}).get('pts') or 0)

    if points < SIGN_CARD_COST:
        return {'status': 'error', 'message': 'points_insufficient',
                'required': SIGN_CARD_COST, 'current': points}

    # 扣积分 + 写历史 + streak +1（弥补 cron 减半）
    with get_cursor() as cur:
        cur.execute(
            "UPDATE user_account SET gambling_points = gambling_points - %s WHERE account_id=%s",
            (SIGN_CARD_COST, user_id),
        )

    cur_streak = int(user.get('app_sign_streak') or 0)
    new_streak = cur_streak + 1

    _record_sign_history(
        user_id=user_id,
        sign_date=yesterday,
        streak=new_streak,
        reward_type='card',
        reward_value=0,
        source='card',
    )

    # 把 streak 同步回 v2_user，确保下次签到 +1 续上
    with get_cursor() as cur:
        cur.execute(
            "UPDATE v2_user SET app_sign_streak=%s WHERE id=%s",
            (new_streak, user_id),
        )

    return {'status': 'success', 'data': {
        'cost': SIGN_CARD_COST,
        'remaining_points': points - SIGN_CARD_COST,
        'new_streak': new_streak,
        'message': '补签成功，连签已恢复',
    }}

@app.get('/api/client/account/overview')
def account_overview(user_id: int = Depends(validate_token)):
    """返回账户概览信息：套餐、流量、到期时间等。"""
    with get_cursor() as cur:
        cur.execute(
            '''
            SELECT u.id, u.email, u.u, u.d, u.transfer_enable, u.expired_at, u.plan_id,
                   u.online_count, u.device_limit, u.last_online_at,
                   p.name AS plan_name, p.transfer_enable AS plan_transfer_gb,
                   p.device_limit AS plan_device_limit
            FROM v2_user u
            LEFT JOIN v2_plan p ON u.plan_id = p.id
            WHERE u.id = %s
            ''',
            (user_id,),
        )
        user = cur.fetchone()

    if not user:
        raise HTTPException(status_code=404, detail='user_not_found')

    # Email 脱敏：首字符 + *** + @domain
    email_raw = user['email'] or ''
    if '@' in email_raw:
        local, domain = email_raw.split('@', 1)
        email_masked = (local[0] if local else '') + '***@' + domain
    else:
        email_masked = email_raw[:1] + '***' if email_raw else ''

    # 流量计算（单位字节）
    # v2_plan.transfer_enable 单位 GB，v2_user 字段单位字节
    plan_transfer_gb = user['plan_transfer_gb']  # None when no plan
    if plan_transfer_gb is None:
        transfer_total = 0
    else:
        transfer_total = int(plan_transfer_gb) * 1024 ** 3

    u = int(user['u'] or 0)
    d = int(user['d'] or 0)
    used = u + d
    remaining = max(transfer_total - used, 0)

    # 到期时间
    expired_at_ts = user['expired_at']
    if expired_at_ts and int(expired_at_ts) > 0:
        expire_dt = datetime.datetime.utcfromtimestamp(int(expired_at_ts))
        expire_iso = expire_dt.strftime('%Y-%m-%dT%H:%M:%SZ')
        now_ts = int(time.time())
        days_remaining = max((int(expired_at_ts) - now_ts) // 86400, 0)
    else:
        expire_iso = None
        days_remaining = None

    # ── 设备在线计数 ──────────────────────────────────────────────
    # v2_user.online_count 由 XBoard DeviceStateService 按 IP 去重写入（600s TTL），
    # 但从不主动归零。与 yuebot DAO 的 batch_check_online_device_counts 一样，
    # 做 10 分钟新鲜度过滤：last_online_at 过期则把 online_count 视为 0。
    # 同步见 /opt/telegram-bot/yue/dao/v2_user.py (DEVICE_ONLINE_STALE_SECONDS)
    # 和 /home/xboard/yue-to/plugins/YueOnlineCount/Plugin.php (STALE_AFTER_SECONDS)。
    DEVICE_ONLINE_STALE_SECONDS = 600
    online_count_raw = int(user['online_count'] or 0)
    last_online_at = user['last_online_at']
    online_fresh = False
    if last_online_at is not None:
        if hasattr(last_online_at, 'timestamp'):
            age = time.time() - last_online_at.timestamp()
            online_fresh = age <= DEVICE_ONLINE_STALE_SECONDS
    online_count = online_count_raw if online_fresh else 0
    # device_limit 优先取用户级覆盖，否则回落到套餐级
    device_limit = user['device_limit'] or user['plan_device_limit'] or 0
    last_online_iso = None
    if last_online_at is not None and hasattr(last_online_at, 'strftime'):
        last_online_iso = last_online_at.strftime('%Y-%m-%dT%H:%M:%SZ')

    return {
        'status': 'success',
        'data': {
            'email':                    email_masked,
            'plan_name':                user['plan_name'] if user['plan_name'] else '无套餐',
            'transfer_used_bytes':      used,
            'transfer_total_bytes':     transfer_total,
            'transfer_remaining_bytes': remaining,
            'expire_at':                expire_iso,
            'days_remaining':           days_remaining,
            'renewal_url':              RENEWAL_URL or '',
            'online_count':             online_count,
            'device_limit':             int(device_limit),
            'last_online_at':           last_online_iso,
        },
    }


@app.get('/api/client/account/actions')
def account_actions():
    """返回常用操作链接，无需认证。"""
    return {
        'status': 'success',
        'data': {
            'renew_url':            RENEWAL_URL or '',
            'feedback_url':         FEEDBACK_URL or '',
            'telegram_group_url':   TELEGRAM_GROUP_URL or '',
            'status_page_url':      STATUS_PAGE_URL or '',
        },
    }


@app.get('/api/client/account/notices')
def account_notices(user_id: int = Depends(validate_token), authorization: str = Header(...)):
    """透传 XBoard 公告列表，失败时返回空列表。"""
    req = urllib.request.Request(
        f'{XBOARD_BASE}/api/v1/user/notice/fetch',
        headers={'Authorization': authorization, 'Accept': 'application/json'},
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            body = _json.loads(resp.read())
        notices = body.get('data', [])
        # data 可能是 None（XBoard 无公告时返回 null）
        if not isinstance(notices, list):
            notices = []
        return {'status': 'success', 'data': notices}
    except Exception as e:
        logger.warning('XBoard notice fetch error: %s', e)
        return {'status': 'success', 'data': []}


@app.get('/api/client/home')
def home_config():
    """首页配置 — 无需认证。v2: 改为从 DB settings 表读取。"""
    # 尝试从 DB settings 表读自定义配置，fallback 到默认值
    config = {
        'banners': None,          # null = 客户端用本地默认
        'quickActions': {
            'showSmartSelect': True,
            'showSceneMode': True,
            'showSpeedTest': True,
        },
        'embyPreview': {
            'source': 'recent',
            'maxItems': 10,
        },
        'showServiceStatusBar': True,
        'sceneModes': None,       # null = 客户端用本地预设
    }
    try:
        with get_cursor() as cur:
            cur.execute("SELECT key, value FROM v2_settings WHERE key LIKE 'app_home_%%'")
            for row in cur.fetchall():
                k = row['key'].replace('app_home_', '')
                try:
                    config[k] = _json.loads(row['value'])
                except Exception:
                    pass
    except Exception:
        pass  # DB 不可用时返回默认配置
    return {'status': 'success', 'data': config}


from pydantic import BaseModel as _BaseModel

class _FeedbackBody(_BaseModel):
    content: str = ''
    contact: str = ''

@app.post('/api/client/feedback')
def submit_feedback(body: _FeedbackBody):
    """接收用户反馈，存入 DB。"""
    content = body.content.strip()
    contact = body.contact.strip()
    if not content:
        raise HTTPException(status_code=400, detail='content_required')
    try:
        with get_cursor() as cur:
            cur.execute(
                "INSERT INTO app_feedback (content, contact, created_at) VALUES (%s, %s, NOW())",
                (content[:500], contact[:200]),
            )
    except Exception as e:
        logger.warning('Feedback save error: %s', e)
    return {'status': 'success', 'message': 'ok'}


@app.get('/health')
def health():
    return {'status': 'ok'}


# ─── Web AI 反馈端点 ────────────────────────────────────────────────────────
# 收集用户对 AI 回复的 👍/👎，写入 ai_feedback 表，供准确率日报聚合。
#
# 使用流程：
#   1. /api/faq/ai 或 /api/xboard/ai 返回 ref_key 字段
#   2. 前端展示"有用 / 不准"按钮，点击时 POST /api/faq/ai/feedback
#   3. 本端点根据 ref_key 回查 _web_meta_cache 写入 channel/intent/model

import time as _time
import threading as _threading

_web_meta_cache: dict = {}
_web_meta_lock = _threading.Lock()
_WEB_META_TTL = 1800  # 30 分钟

def _cache_web_meta(ref_key: str, channel: str, intent: str, model: str, v2_user_id=None):
    with _web_meta_lock:
        _web_meta_cache[ref_key] = {
            'channel': channel, 'intent': intent, 'model': model,
            'v2_user_id': v2_user_id, '_ts': _time.monotonic(),
        }
        now = _time.monotonic()
        expired = [k for k, v in _web_meta_cache.items() if now - v['_ts'] > _WEB_META_TTL]
        for k in expired:
            del _web_meta_cache[k]


def _get_web_meta(ref_key: str) -> dict:
    with _web_meta_lock:
        return dict(_web_meta_cache.get(ref_key, {}))


class _AiFeedbackBody(_BaseModel):
    ref_key: str
    score: int  # 1 有用, -1 不准


@app.post('/api/faq/ai/feedback')
def submit_ai_feedback(body: _AiFeedbackBody, request: _Request):
    """接收 Web/XBoard AI 回复的用户反馈，写入 ai_feedback 表。"""
    ref_key = body.ref_key.strip()[:64]
    if not ref_key or body.score not in (1, -1):
        raise HTTPException(status_code=400, detail='invalid_params')
    meta = _get_web_meta(ref_key)
    channel = meta.get('channel', 'web')
    intent = meta.get('intent') or None
    model = meta.get('model') or None
    v2_user_id = meta.get('v2_user_id') or None
    try:
        with get_cursor() as cur:
            cur.execute(
                """INSERT INTO ai_feedback
                   (source, ref_key, channel, tg_user_id, v2_user_id, score, intent, model)
                   VALUES ('ai_reply', %s, %s, NULL, %s, %s, %s, %s)
                   ON CONFLICT (source, ref_key) WHERE tg_user_id IS NULL DO UPDATE SET
                     score = EXCLUDED.score, created_at = NOW()""",
                (ref_key, channel, v2_user_id, body.score, intent, model),
            )
        logger.info("web ai_feedback: channel=%s intent=%s score=%d ref=%s",
                    channel, intent or '', body.score, ref_key)
        return {'status': 'success'}
    except Exception as e:
        logger.warning('ai_feedback save error: %s', e)
        raise HTTPException(status_code=500, detail='db_error')


# ─── FAQ 自动回复搜索（公开，无需认证） ──────────────────────────────────────

_faq_cache: dict = {'exact': {}, 'fuzzy': []}
_faq_cache_ts: float = 0.0
_FAQ_TTL = 300  # 5分钟刷新一次
_FAQ_FAST_PATH_ENABLED = os.getenv('YUE_LEGACY_FAQ_FAST_PATH', '0') == '1'

def _load_faq() -> dict:
    global _faq_cache, _faq_cache_ts
    now = time.time()
    if now - _faq_cache_ts < _FAQ_TTL:
        return _faq_cache
    try:
        with get_cursor() as cur:
            cur.execute("SELECT keyword, reply_text FROM bot_auto_reply ORDER BY id")
            rows = cur.fetchall()
        exact: dict[str, str] = {}
        fuzzy: list[tuple[list, str]] = []
        for r in rows:
            raw = r['keyword'].strip()
            reply = r['reply_text']
            for variant in [v.strip() for v in raw.split('|') if v.strip()]:
                tokens = variant.split()
                if len(tokens) >= 2:
                    fuzzy.append((tokens, reply))
                else:
                    exact[variant] = reply
        _faq_cache = {'exact': exact, 'fuzzy': fuzzy}
        _faq_cache_ts = now
        logger.info('FAQ cache refreshed: %d exact, %d fuzzy', len(exact), len(fuzzy))
    except Exception as e:
        logger.warning('FAQ cache load error: %s', e)
    return _faq_cache

def _search_faq(text: str):
    faq = _load_faq()
    if not faq or not faq.get('exact'):
        return None
    exact, fuzzy = faq['exact'], faq['fuzzy']
    # 1. 精确匹配
    if text in exact:
        return exact[text]
    # 2. 子串匹配 — 优先匹配最长关键词，短关键词（≤3字）只精确匹配
    best_kw_len, best_reply = 0, None
    for kw, rep in exact.items():
        if len(kw) <= 3 and kw != text:
            continue
        if kw in text and len(kw) > best_kw_len:
            best_kw_len = len(kw)
            best_reply = rep
    if best_reply:
        return best_reply
    # 3. 模糊匹配（≥60% token 命中，至少 2 个）
    best_score, best_reply = 0.0, None
    for tokens, rep in fuzzy:
        matched = sum(1 for t in tokens if t in text)
        if matched < 2:
            continue
        score = matched / len(tokens)
        if score >= 0.6 and score > best_score:
            best_score, best_reply = score, rep
    return best_reply

@app.get('/api/faq/search')
def faq_search(q: str = ''):
    text = q.strip()[:100]
    if not text:
        return {'status': 'success', 'data': {'answer': None, 'matched': False}}
    if not _FAQ_FAST_PATH_ENABLED:
        return {'status': 'success', 'data': {'answer': None, 'matched': False}}
    answer = _search_faq(text)
    return {'status': 'success', 'data': {'answer': answer, 'matched': answer is not None}}


# ─── AI 客服 fallback（FAQ 未命中时调 OpenRouter LLM） ────────────────────────

_OPENROUTER_KEY = os.getenv('OPENROUTER_API_KEY', '')
_OPENROUTER_MODEL = os.getenv('OPENROUTER_MODEL', 'anthropic/claude-haiku-4.5')
_OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions'

_AI_SYSTEM_PROMPT = """你叫小悦，悦通加速的在线客服助手。说话简短自然，不装正式。

回答原则：
- 只回答用户问到的内容，不主动扩展无关信息
- 默认1-3句，够用就行，不写小作文
- 不确定说不知道，让提工单或联系管理员
- 协议技术架构IP说不懂，不猜不编
- 不主动推荐套餐/续费/升级/活动，除非用户问
- 不用"还有其他问题随时问"这类收尾套话
- 你是真人，不要说"作为AI"这种话

悦通业务知识：
- 官网 yue.to，客户端推荐 YueLink（全平台），也能用 Clash Meta（Clash Verge Rev）/ Stash / Shadowrocket，订阅链接通用。原版 Clash 已停更不兼容，必须用 Clash Meta
- 悦视频在 YueLink 第三个 tab，套餐附赠，内容免费，访问时需开启悦通代理。内容库不定期更新，不保证特定影片持续可用
- 节点分四类：专属节点（💎 套餐附带，最稳）/ 家宽节点（💎 住宅 IP）/ AI 解锁节点（💎 ChatGPT/Claude/Gemini 专线）/ 普通节点（覆盖广，含 IPv6 稀有地区）。HK/TW/JP/US/SG 是高频热门，UK/欧洲适合跨区，具体地区列表以面板「订阅」页为准，不要报具体数量
- 套餐月付季付年付，年付最划算。购买后不退款，任何套餐不支持退款退费
- 购买新套餐会**替换**现有套餐，不叠加。续费同款是延期不替换。想同时跑两个套餐要两个账号
- 签到领流量或余额，流量是扣已用的（不是加总量），连签有加成（8天×1.2，15天×1.3，30天×1.5），断签减半不归零
- 竞猜玩骰子赢了扣已用流量（奖励），输了加已用流量（惩罚），输的找不回来
- 积分靠竞猜攒，下注越多赚越多（<10GB=1分，10-49GB=2分，50-99GB=3分，100-199GB=4分，200-499GB=5分，500GB+=8分），可换流量/补签卡/加次数/保险卡/赛事券/幸运抽奖
- 每日任务：签到+竞猜+查流量，完成有额外奖励
- **没有优惠码、折扣码、邀请码**，不搞促销码，选年付或季付性价比最高
- YueLink独有：游戏加速、悦视频、AI工具集成
- 设备在线数取决于套餐等级，超限先警告，5分钟内不减少设备会重置订阅链接（需要重新导入）
- 支付：支持支付宝、微信、USDT（USDT 手续费 8%）
- 没有限速，跑满本地带宽。觉得慢是节点选错了或本地网络问题
- 邀请好友：面板有邀请链接，好友消费你拿佣金，佣金可兑换竞猜次数
- iOS客户端：YueLink iOS版开发中，目前用Shadowrocket或Stash
- 工单/反馈：面板右下角点「工单」提交，管理员看到会处理
- 连不上排查：确认套餐未过期→更新订阅→换节点→重启客户端→切换连接方式→换设备测试→实在不行提工单"""

# AI 请求频率限制：每 IP 每分钟 20 次
_ai_rate: dict[str, list[float]] = {}
_AI_RATE_LIMIT = 20
_AI_RATE_WINDOW = 60

def _cleanup_ai_rate():
    """定期清理不再活跃的 IP 记录（防内存泄漏）
    注意：APScheduler 在后台线程运行，必须对 dict 做快照迭代，避免迭代时并发修改崩溃。"""
    cutoff = time.time() - _AI_RATE_WINDOW * 2
    stale = [ip for ip, reqs in list(_ai_rate.items()) if not reqs or reqs[-1] < cutoff]
    for ip in stale:
        _ai_rate.pop(ip, None)
    # 同步清理 _rate_store 中长期无请求的 IP key
    cutoff_rate = time.time() - _RATE_WINDOW * 10
    stale_rate = [ip for ip, reqs in list(_rate_store.items()) if not reqs or reqs[-1] < cutoff_rate]
    for ip in stale_rate:
        _rate_store.pop(ip, None)

from pydantic import BaseModel as _BaseModel
from fastapi.responses import StreamingResponse
import re as _re
import http.client as _http_client
import urllib.parse as _urlparse

# AI 响应质检
_AI_SLIP_RES = [
    _re.compile(r'作为(一个)?(AI|人工智能|语言模型)(助手|客服)?[，,]?\s*'),
    _re.compile(r'我(只)?是(一个)?(AI|人工智能|虚拟|语言模型)(助手)?[，,。]?\s*'),
    _re.compile(r'(很高兴|非常高兴)(能够)?为[你您](服务|解答)[！!。]?\s*'),
    _re.compile(r'希望(以上|这些)(信息|内容|回答)(能够)?对[你您]有(所)?帮助[！!。]?\s*'),
    _re.compile(r'如果[你您](还有|有)(其他|任何)(问题|疑问)[，,]?(随时|欢迎)?(问我|提问|咨询|联系)[。！!]?\s*'),
    _re.compile(r'有什么(其他)?(我)?可以帮[你您]的[吗？?]?\s*'),
]

def _clean_ai_response(text: str) -> str:
    """清理 AI 穿帮和格式"""
    if not text:
        return text
    for p in _AI_SLIP_RES:
        text = p.sub('', text)
    text = _re.sub(r'^#{1,3}\s+', '', text, flags=_re.MULTILINE)
    text = _re.sub(r'\*\*(.+?)\*\*', r'\1', text)
    return text.strip()

class _AiQuery(_BaseModel):
    q: str
    history: list = []

def _get_client_ip(request: _Request) -> str:
    ip = request.client.host if request.client else '0.0.0.0'
    if ip in ('127.0.0.1', '::1'):
        ip = request.headers.get('x-forwarded-for', ip).split(',')[0].strip()
    return ip

def _check_rate(ip: str) -> bool:
    """返回 True 表示超限"""
    now = time.time()
    reqs = _ai_rate.get(ip, [])
    reqs = [t for t in reqs if now - t < _AI_RATE_WINDOW]
    if len(reqs) >= _AI_RATE_LIMIT:
        return True
    reqs.append(now)
    _ai_rate[ip] = reqs
    return False

def _resolve_web_context(request_headers: dict, text: str):
    """返回 (session_id, user_profile, node_diag)"""
    import uuid
    # session_id: 优先用 X-Session-Id header，否则随机
    session_id = request_headers.get('x-session-id', '') or str(uuid.uuid4())
    user_profile = _try_get_user_profile_sync(request_headers)
    node_diag = _detect_and_diagnose_node(text)
    return session_id, user_profile, node_diag


def _try_get_user_profile_sync(request_headers: dict):
    """尝试从 Authorization header 获取用户画像，失败返回 None（不阻断请求）。

    委托给 web_gateway.get_user_profile_pg，统一实现（含 balance/commission）。
    """
    from web_gateway import get_user_profile_pg
    auth = request_headers.get('authorization', '')
    return get_user_profile_pg(auth, XBOARD_BASE, get_cursor)

_NODE_FAULT_WORDS = ('挂了', '崩了', '断了', '连不上', '不能用', '用不了', '炸了',
                     '废了', '瘫了', '超时', '报错', '打不开', '不行了', '有问题', '故障', '异常')
_REGION_KW = {
    '香港': '香港', 'hk': '香港', '港': '香港', '日本': '日本', 'jp': '日本', '东京': '日本',
    '美国': '美国', 'us': '美国', '台湾': '台湾', 'tw': '台湾', '新加坡': '新加坡', 'sg': '新加坡',
    '韩国': '韩国', 'kr': '韩国', '泰国': '泰国', '英国': '英国', '印度': '印度',
    '澳大利亚': '澳大利亚', '澳洲': '澳大利亚', '马来西亚': '马来西亚', '越南': '越南',
    '土耳其': '土耳其', '巴西': '巴西', '阿联酋': '阿联酋', '迪拜': '阿联酋',
    '尼日利亚': '尼日利亚', '西班牙': '西班牙', '瑞典': '瑞典',
}

def _detect_and_diagnose_node(text):
    """检测节点投诉并调 YueOps 内部 API 诊断，返回结果字符串或 None"""
    text_lower = text.lower()
    region = None
    for kw, rname in _REGION_KW.items():
        if kw in text_lower:
            region = rname
            break
    if not region or not any(w in text for w in _NODE_FAULT_WORDS):
        return None
    try:
        body = _json.dumps({"region": region}).encode()
        req = urllib.request.Request(
            'http://127.0.0.1:8010/api/internal/diagnose',
            data=body, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = _json.loads(resp.read())
        action = data.get('action', 'none')
        unhealthy = data.get('unhealthy', [])
        servers = data.get('servers', [])
        online = sum(1 for s in servers if s.get('online'))
        if not unhealthy:
            return f"{region}节点监控正常（{online}/{len(servers)}台在线），可能是用户本地网络问题"
        if action == 'fixing':
            return f"已检测到{region}有{len(unhealthy)}台离线，正在自动重启，约30秒后恢复"
        return f"{region}节点状态：{data.get('message','')}"
    except Exception:
        return None


def _build_messages(text, history_raw, faq_answer, user_profile):
    """构建发给 OpenRouter 的 messages 数组"""
    clean = []
    for m in (history_raw or [])[-20:]:
        if isinstance(m, dict) and m.get('role') in ('user', 'assistant') and m.get('content'):
            clean.append({'role': m['role'], 'content': str(m['content'])[:300]})

    sys_prompt = _AI_SYSTEM_PROMPT
    if user_profile:
        from support_core.llm import CACHE_BOUNDARY_MARKER as _CBM
        sys_prompt += _CBM + f"[用户信息：套餐「{user_profile['plan']}」，剩余流量 {user_profile['remaining_gb']}GB"
        if user_profile['days'] is not None:
            sys_prompt += f"，还有 {user_profile['days']} 天到期"
        sys_prompt += "。仅在用户主动问相关问题时才参考，不要主动提起。]"

    msgs = [{'role': 'system', 'content': sys_prompt}]
    msgs.extend(clean)

    # 节点故障自动诊断+修复
    diag = _detect_and_diagnose_node(text)
    msgs.append({'role': 'user', 'content': text})
    if diag:
        msgs.append({'role': 'system', 'content': f'[系统诊断结果：{diag}]\n用你自己的话告诉用户这个结果，简短自然。'})
    elif faq_answer:
        faq_plain = _re.sub('<[^>]+>', '', faq_answer).strip()[:400]
        msgs.append({'role': 'system', 'content': f'[FAQ参考信息：{faq_plain}]\n请参考以上信息，用你自己的话自然回答。不要照搬原文格式，不要列清单。'})
    return msgs

# ── 非流式端点（兼容旧 widget） ──

@app.post('/api/faq/ai')
async def faq_ai(body: _AiQuery, request: _Request):
    if not _OPENROUTER_KEY:
        return {'status': 'error', 'message': 'AI 服务未配置'}
    text = body.q.strip()[:200]
    if not text or len(text) < 2:
        return {'status': 'error', 'message': '问题太短'}
    if _check_rate(_get_client_ip(request)):
        return {'status': 'error', 'message': '请求过于频繁，请稍后再试'}

    # 旧 FAQ 快速路径默认关闭：bot_auto_reply 中有过期页面名、硬编码套餐和人工引导。
    faq_answer = _search_faq(text) if _FAQ_FAST_PATH_ENABLED else None
    if _FAQ_FAST_PATH_ENABLED and faq_answer:
        logger.info("Web AI: faq hit, ip=%s query=%r", _get_client_ip(request), text[:50])
        return {'status': 'success', 'data': {'answer': faq_answer, 'source': 'faq'}}

    import asyncio
    from web_gateway import process_sync, classify_intent

    hdrs = dict(request.headers)
    session_id, user_profile, node_diag = await asyncio.to_thread(
        _resolve_web_context, hdrs, text
    )
    intent = classify_intent(text)

    logger.info("Web AI: ip=%s intent=%s profile=%s query=%r",
                _get_client_ip(request), intent, bool(user_profile), text[:50])

    try:
        content = await asyncio.wait_for(
            asyncio.to_thread(
                process_sync, text, session_id, body.history,
                user_profile, faq_answer, node_diag, "web", get_cursor,
            ),
            timeout=30,
        )
    except asyncio.TimeoutError:
        logger.warning("Web AI timeout: ip=%s query=%r", _get_client_ip(request), text[:50])
        return {'status': 'error', 'message': '回复超时，请稍后重试'}
    if not content:
        return {'status': 'error', 'message': 'AI 服务暂时不可用，请稍后重试'}
    import uuid as _uuid
    ref_key = f"web:{session_id}:{_uuid.uuid4().hex[:8]}"
    _cache_web_meta(ref_key, 'web', intent,
                    os.getenv('OPENROUTER_MODEL', ''),
                    (user_profile or {}).get('v2_user_id'))
    return {'status': 'success', 'data': {'answer': content, 'source': 'ai', 'ref_key': ref_key}}

# ── XBoard 面板专用 AI 端点（已登录，channel='xboard'）──

@app.post('/api/xboard/ai')
async def xboard_ai(body: _AiQuery, request: _Request):
    """XBoard 面板客服：已登录用户，走 support_core 统一内核"""
    if not _OPENROUTER_KEY:
        return {'status': 'error', 'message': 'AI 服务未配置'}
    text = body.q.strip()[:300]
    if not text or len(text) < 2:
        return {'status': 'error', 'message': '问题太短'}
    if _check_rate(_get_client_ip(request)):
        return {'status': 'error', 'message': '请求过于频繁，请稍后再试'}

    # 旧 FAQ 快速路径默认关闭：面板客服必须走 facts-first AI 内核。
    faq_answer = _search_faq(text) if _FAQ_FAST_PATH_ENABLED else None
    if _FAQ_FAST_PATH_ENABLED and faq_answer:
        logger.info("XBoard AI: faq hit, query=%r", text[:50])
        return {'status': 'success', 'data': {'answer': faq_answer, 'source': 'faq', 'channel': 'xboard'}}

    import asyncio, uuid as _uuid
    from web_gateway import process_sync

    hdrs = dict(request.headers)
    auth = hdrs.get('authorization', '')
    session_id, user_profile, node_diag = await asyncio.to_thread(
        _resolve_web_context, hdrs, text
    )
    if not session_id or session_id == str(_uuid.UUID(int=0)):
        session_id = auth[-16:] if auth else str(_uuid.uuid4())

    # 把 bearer_token 传入 user_profile 供 support_core 使用
    if user_profile:
        user_profile['_bearer_token'] = auth

    logger.info("XBoard AI: profile=%s query=%r", bool(user_profile), text[:50])

    try:
        content = await asyncio.wait_for(
            asyncio.to_thread(
                process_sync, text, session_id, body.history,
                user_profile, faq_answer, node_diag, "xboard", get_cursor,
            ),
            timeout=30,
        )
    except asyncio.TimeoutError:
        logger.warning("XBoard AI timeout: query=%r", text[:50])
        return {'status': 'error', 'message': '回复超时，请稍后重试'}
    if not content:
        return {'status': 'error', 'message': 'AI 服务暂时不可用，请稍后重试'}

    import uuid as _uuid
    ref_key_xb = f"xboard:{session_id}:{_uuid.uuid4().hex[:8]}"
    v2uid = (user_profile or {}).get('v2_user_id')
    _cache_web_meta(ref_key_xb, 'xboard', '',
                    os.getenv('OPENROUTER_MODEL', ''), v2uid)
    return {'status': 'success', 'data': {
        'answer': content, 'source': 'ai', 'channel': 'xboard', 'ref_key': ref_key_xb,
    }}


# ── SSE 上下文准备（与普通 /api/faq/ai 口径对齐） ──

def _prepare_web_ai_context(
    text: str,
    session_id: str,
    user_profile: dict | None,
    node_diag: str | None,
    history: list,
    channel: str = "web",
) -> dict:
    """为 SSE 流式端点准备 AI 上下文，与 process_sync 对齐。

    包含：intent 分类 / model 选择（model_router.select）/
          KB 检索 / facts 注入 / prompt 构建 / ref_key 生成。

    返回 keys：
        intent_enum, intent, model, params, should_process,
        messages, ref_key, v2_uid
    """
    import uuid as _uuid_mod
    import sys as _sys, os as _os
    _bot_path = _os.path.join(_os.path.dirname(__file__), '..', 'telegram-bot', 'yue')
    if _bot_path not in _sys.path:
        _sys.path.insert(0, _bot_path)

    from ai_gateway.intent import classify as _classify
    from ai_gateway import model_router as _mr
    from support_core.prompt import build_prompt as _build_prompt
    from support_core.facts import collect_facts as _collect_facts
    from support_core.kb import (
        kb_search as _kb_search,
        intent_to_kb_category as _intent_to_kb_cat,
        should_search_kb as _should_search_kb,
    )
    from support_core.llm import build_messages as _build_messages

    intent_enum = _classify(text, is_direct=True)
    model, params, should_process = _mr.select(intent_enum)
    router_reason = _mr.get_budget_state()

    faq_matches = (
        _kb_search(text, category=_intent_to_kb_cat(intent_enum), channel=channel)
        if _should_search_kb(intent_enum) else []
    )
    v2_uid = (user_profile or {}).get("v2_user_id")
    extra_facts = _collect_facts(
        intent_enum, v2_uid, channel, None,
        profile_dict=user_profile, text=text,
        get_cursor_fn=get_cursor,
    )
    profile_str = None
    if user_profile:
        p = user_profile
        profile_str = f"套餐「{p.get('plan','?')}」，剩余{p.get('remaining_gb',0)}GB"

    system = _build_prompt(intent_enum, profile_str, faq_matches, node_diag, extra_facts)
    messages = _build_messages(system, history or [], text)
    ref_key = f"{channel}:{session_id}:{_uuid_mod.uuid4().hex[:8]}"

    return {
        "intent_enum":    intent_enum,
        "intent":         intent_enum.value,
        "model":          model,
        "params":         params,
        "should_process": should_process,
        "messages":       messages,
        "ref_key":        ref_key,
        "v2_uid":         v2_uid,
        "router_reason":  router_reason,
    }


# ── SSE 流式端点 ──

@app.post('/api/faq/ai/stream')
async def faq_ai_stream(body: _AiQuery, request: _Request):
    if not _OPENROUTER_KEY:
        return JSONResponse({'status': 'error', 'message': 'AI 服务未配置'})
    text = body.q.strip()[:200]
    if not text or len(text) < 2:
        return JSONResponse({'status': 'error', 'message': '问题太短'})
    if _check_rate(_get_client_ip(request)):
        return JSONResponse({'status': 'error', 'message': '请求过于频繁'})

    import asyncio
    from web_gateway import _track, _estimate_cost
    from datetime import date as _date

    # ── 上下文准备（IO 在线程池中执行） ──
    hdrs = dict(request.headers)
    session_id, user_profile, node_diag = await asyncio.to_thread(
        _resolve_web_context, hdrs, text
    )
    ctx = await asyncio.to_thread(
        _prepare_web_ai_context,
        text, session_id, user_profile, node_diag, body.history or [], "web",
    )
    intent_enum = ctx["intent_enum"]

    # ── 护栏（SKIP / 安全 / 预算） ──
    import sys as _sys, os as _os
    _bot_path = _os.path.join(_os.path.dirname(__file__), '..', 'telegram-bot', 'yue')
    if _bot_path not in _sys.path:
        _sys.path.insert(0, _bot_path)
    from ai_gateway.types import Intent as _Intent, AiRequest as _AiReq, Channel as _Ch
    if intent_enum == _Intent.SKIP:
        return JSONResponse({'status': 'error', 'message': '无法理解'})
    from ai_gateway.safety import check_high_risk as _check_hr
    _safe = _check_hr(_AiReq(channel=_Ch.WEB, text=text, user_id=session_id, is_direct=True))
    if _safe is not None:
        return JSONResponse({'status': 'success', 'data': {'answer': _safe.text, 'source': 'safety'}})
    if not ctx["should_process"]:
        return JSONResponse({'status': 'error', 'message': '小悦今天太忙了，晚点再来～'})

    # ── 缓存 ref_key 供反馈接口使用 ──
    ref_key = ctx["ref_key"]
    _cache_web_meta(ref_key, "web", ctx["intent"], ctx["model"], ctx["v2_uid"])

    model    = ctx["model"]
    params   = ctx["params"]
    messages = ctx["messages"]

    logger.info("Web AI stream: ip=%s intent=%s model=%s query=%r",
                _get_client_ip(request), ctx["intent"], model.split('/')[-1], text[:50])

    def _stream_gen():
        conn = None
        _output_chars = 0
        try:
            # ── 首帧：meta（ref_key / intent / model / tier）──
            yield f'data: {_json.dumps({"meta": {"ref_key": ref_key, "channel": "web", "intent": ctx["intent"], "model": model, "tier": params.get("tier", "")}}, ensure_ascii=False)}\n\n'

            parsed = _urlparse.urlparse(_OPENROUTER_URL)
            conn = _http_client.HTTPSConnection(parsed.hostname, timeout=20)
            from support_core.llm import apply_anthropic_cache as _aac
            payload = _json.dumps({
                'model':       model,
                'messages':    _aac(messages, model),
                'max_tokens':  params.get('max_tokens', 280),
                'temperature': params.get('temperature', 0.7),
                'stream':      True,
            })
            conn.request('POST', parsed.path, body=payload, headers={
                'Authorization': f'Bearer {_OPENROUTER_KEY}',
                'Content-Type': 'application/json', 'Accept': 'text/event-stream',
            })
            resp = conn.getresponse()
            if resp.status != 200:
                yield f'data: {_json.dumps({"e": "AI 服务暂时不可用"}, ensure_ascii=False)}\n\n'
                yield 'data: [DONE]\n\n'
                return

            buf = ''
            in_think = False
            for chunk in resp:
                buf += chunk.decode('utf-8', errors='replace')
                while '\n' in buf:
                    line, buf = buf.split('\n', 1)
                    line = line.strip()
                    if not line or not line.startswith('data: '):
                        continue
                    payload_str = line[6:]
                    if payload_str == '[DONE]':
                        yield 'data: [DONE]\n\n'
                        return
                    try:
                        obj = _json.loads(payload_str)
                        delta = obj.get('choices', [{}])[0].get('delta', {})
                        token = delta.get('content', '')
                        if not token:
                            continue
                        if '<think>' in token:
                            in_think = True
                            token = token.split('<think>')[0]
                        if '</think>' in token:
                            in_think = False
                            after = token.split('</think>')[-1]
                            if after:
                                _output_chars += len(after)
                                yield f'data: {_json.dumps({"t": after}, ensure_ascii=False)}\n\n'
                            continue
                        if in_think:
                            continue
                        if token:
                            _output_chars += len(token)
                            yield f'data: {_json.dumps({"t": token}, ensure_ascii=False)}\n\n'
                    except (_json.JSONDecodeError, IndexError, KeyError):
                        continue
            yield 'data: [DONE]\n\n'
        except Exception as e:
            logger.warning('SSE stream error: %s', e)
            yield f'data: {_json.dumps({"e": "连接中断，请重试"}, ensure_ascii=False)}\n\n'
            yield 'data: [DONE]\n\n'
        finally:
            if conn:
                try:
                    conn.close()
                except Exception:
                    pass
            # 成本追踪：流式无真实 usage，字符数保守估算（~3字/token），标记 usage_estimated=True
            try:
                import threading as _thr
                est_tokens = max(_output_chars // 3, 1) if _output_chars > 0 else 0
                est_cost = _estimate_cost(model, est_tokens)
                _thr.Thread(
                    target=_track,
                    kwargs=dict(
                        session_id=session_id, channel="web", intent=ctx["intent"],
                        model=model, tokens=est_tokens, cost=est_cost,
                        day=str(_date.today()), get_cursor=get_cursor,
                        usage_estimated=True,
                        model_tier=params.get("tier", ""),
                        router_reason=ctx.get("router_reason", ""),
                    ),
                    daemon=True,
                ).start()
            except Exception:
                pass

    return StreamingResponse(_stream_gen(), media_type='text/event-stream',
                             headers={'Cache-Control': 'no-cache', 'X-Accel-Buffering': 'no'})


# ─── 工单 AI 自动回复 Worker ─────────────────────────────────────────────────

_TICKET_ADMIN_ID = 1  # XBoard 管理员 user_id
# 2026 策略：
#   提现 → 跳 AI 留人工（_TICKET_PAYOUT_KEYWORDS）
#   退款 → 硬拒绝政策，固定回复 + auto_close（_TICKET_REFUND_KEYWORDS）
#   其余高风险 → AI 先接 shadow_queue 记录（由 adapters/ticketing.py 处理）
#
# 同步规则：以下两组必须与 telegram-bot/yue/ticketing/sensitive_keywords.py
# 的 PAYOUT_KW / REFUND_KW 保持一致（2026-04-17 根据 90 天真实工单样本校准）。
_TICKET_PAYOUT_KEYWORDS = (
    '提现', '提款', '取款',
    '佣金提现', '佣金到账', '怎么提取', '能提取', '提取佣金', '佣金能提',
    '提现扣除', '提现被扣', '提现手续费', '提现扣了',
    '提不出来', '提不了', '提不到',
    '多久到账', '多久能到', '还没到账', '什么时候到账', '迟迟没到',
    '提现账号', '提现方式',
)
_TICKET_REFUND_KEYWORDS = (
    '退款', '退钱', '退费', '退回来', '退订',
    '要退', '申请退', '想退', '给我退', '请求退', '要求退', '快处理退',
    '全退', '全额退', '想退款重新',
    '能退吗', '能退款', '可以退', '能不能退', '能退么', '退款通道',
    '如何申请退', '如何退款',
    '取消订阅', '不想用了',
)
_TICKET_REFUND_REPLY = (
    "不支持退款。购买后一律不退，这是平台统一政策。\n"
    "使用中有问题把情况发过来（节点/客户端/错误信息），我们帮你排查。"
)

# ── 自动回复 + 自动关单类工单（无需 AI，固定模板即可） ──
_TICKET_AUTO_CLOSE_RULES = [
    {
        'keywords': ('领奖', '兑奖', '中奖', '领取奖品', '抽奖领取', '中奖了', '领取', '兑换奖品'),
        'reply': (
            "🎁 恭喜中奖！领奖流程：\n\n"
            "1️⃣ 确认你的 TG 已绑定悦通账号（私聊机器人 /start）\n"
            "2️⃣ 奖品会在 24 小时内由管理员发放到你的账户余额\n"
            "3️⃣ 余额可直接用于续费或购买套餐\n\n"
            "如果超过 24 小时未收到，请再次提交工单并附上你的 TG 用户名～"
        ),
        'auto_close': True,
    },
    {
        'keywords': ('余额转移', '转余额', '帐户申请余额转移', '超能卡', '全能卡'),
        'reply': (
            "💰 余额转移说明：\n\n"
            "目前不支持自助余额转移，需要管理员手动操作。\n"
            "请在工单里注明：\n"
            "• 转出账号（邮箱）\n"
            "• 转入账号（邮箱）\n"
            "• 转移金额\n\n"
            "管理员会在工作时间内处理，请耐心等待～"
        ),
        'auto_close': False,
    },
    {
        'keywords': ('修改邮箱', '更改邮箱', '换邮箱', '改邮箱'),
        'reply': (
            "📧 修改邮箱需要验证身份，请提供：\n\n"
            "• 当前账号邮箱\n"
            "• 想要改成的新邮箱\n"
            "• 最近一次购买记录（金额+日期）\n\n"
            "管理员会在工作时间内处理～"
        ),
        'auto_close': False,
    },
    {
        'keywords': ('红包', '红包码', '兑换码', '优惠码在哪'),
        'reply': (
            "🧧 红包码/优惠码使用方法：\n\n"
            "在面板「优惠券」页面输入红包码即可兑换。\n"
            "如遇到「优惠码无效」，可能已过期或已被使用～"
        ),
        'auto_close': True,
    },
]


def _match_auto_close_rule(subject: str, content: str):
    """检查工单是否匹配自动回复+关单规则"""
    full = f"{subject} {content}"
    for rule in _TICKET_AUTO_CLOSE_RULES:
        if any(kw in full for kw in rule['keywords']):
            return rule
    return None
_ticket_last_check_id = 0   # 上次处理到的消息 ID
_ticket_in_flight: set  = set()  # Fix-1: 本轮已加入处理队列的 ticket_id，防同 ticket 重复回复

_TICKET_SYSTEM_PROMPT = """你叫小悦，悦通加速的客服。用户在面板提交了工单，你来回复。

回答原则：只答用户问到的，两三句话搞定，不写小作文。不确定的转人工。

你知道的：
- 客户端推荐：YueLink（全平台首选），iOS 用 Stash 或 Shadowrocket，路由器用 OpenClash
- 连不上排查：确认套餐未过期→更新订阅→换节点（推荐韩国/台湾/美国）→重启客户端→切换连接方式试试
- 节点全红：大概率订阅没更新，先手动更新订阅链接
- 速度慢：先换节点试试，推荐距离近的（香港/台湾/日本），避开高峰期(20-23点)
- 设备超限：先减少设备数，超时不减会重置订阅链接
- 订阅链接：面板首页→一键订阅→复制链接→粘贴到客户端
- 导入失败/配置文件切换失败：删除旧配置→重新导入订阅链接→等待更新完成
- iOS 小火箭设置：添加节点→粘贴订阅链接→选节点→连接
- Windows Defender SmartScreen 拦截：点击"更多信息"→"仍要运行"即可
- 签到：TG 群发"签到"或 YueLink App 签到，每天两次机会
- 竞猜：TG 群发"竞猜"开始，下注流量赢更多
- 购买后不退款（语气平和但明确拒绝）
- 不确定的说"这个我帮你转给技术同事处理"

【严禁捏造】你没有实时节点数据，严禁编造"检测到XX节点离线""系统正在重启""约XX秒后恢复"等内容。如用户反馈节点问题，只能引导排查步骤。"""


def _ticket_worker():
    """定时扫描新工单消息并自动回复

    三段式（读DB → AI处理 → 写DB），通过 adapters/ticketing.py 接入 auto_triage。
    Fix-1: 双层去重 — 本轮 seen_tickets（同 ticket 多条消息只处理最新一条）
           + _ticket_in_flight（跨轮次防止同 ticket 并发重复回复）
    """
    global _ticket_last_check_id, _ticket_in_flight
    if not _OPENROUTER_KEY:
        return

    # feature flag 检查
    try:
        with get_cursor(dictionary=True) as cur:
            cur.execute("SELECT enabled FROM feature_flags WHERE key = 'ticket_auto_triage'")
            row = cur.fetchone()
            if row and not row['enabled']:
                return
    except Exception:
        pass  # 表不存在时继续（降级）

    try:
        # ── 阶段 1：读取待处理工单数据（快速，立即释放连接） ──
        pending = []  # list of (ticket_id, full_text, messages_for_ai, ticket_owner_id, subject)
        with get_cursor() as cur:
            # P1-3 fix: 初始化时找最老的 pending 工单，从那里开始扫（捡起历史积压）
            if _ticket_last_check_id == 0:
                cur.execute("""
                    SELECT COALESCE(MIN(tm.id) - 1, 0) AS start_id
                    FROM v2_ticket_message tm
                    JOIN v2_ticket t ON tm.ticket_id = t.id
                    WHERE t.reply_status = 0 AND t.status = 0 AND tm.user_id != %s
                """, (_TICKET_ADMIN_ID,))
                row = cur.fetchone()
                start_id = row['start_id'] if row and row['start_id'] else 0
                if start_id == 0:
                    cur.execute("SELECT COALESCE(MAX(id), 0) AS max_id FROM v2_ticket_message")
                    _ticket_last_check_id = cur.fetchone()['max_id'] or 0
                    logger.info('工单 worker 初始化：无 pending，从 ID %d 开始', _ticket_last_check_id)
                    return
                _ticket_last_check_id = start_id
                logger.info('工单 worker 初始化：发现 pending 工单，从 ID %d 开始扫描', _ticket_last_check_id)
                # fall through 立即处理 pending 工单

            # 查询新消息（用户发的，非管理员，仅 reply_status=0 的开放工单）
            # reply_status=0 = 待回复，等管理员回复（AI 也按管理员身份回复）
            # 多轮追问：用户每次追问都是新消息 id，会被 tm.id > last_id 自然拾取
            cur.execute("""
                SELECT tm.id, tm.ticket_id, tm.user_id, tm.message,
                       t.subject, t.user_id AS ticket_owner, t.status
                FROM v2_ticket_message tm
                JOIN v2_ticket t ON tm.ticket_id = t.id
                WHERE tm.id > %s
                  AND tm.user_id != %s
                  AND t.status = 0
                  AND t.reply_status = 0
                ORDER BY tm.id
                LIMIT 10
            """, (_ticket_last_check_id, _TICKET_ADMIN_ID))
            new_msgs = cur.fetchall()

            if not new_msgs:
                return

            seen_tickets: set = set()  # Fix-1: 本轮每个 ticket 只取最新一条消息
            for msg in new_msgs:
                _ticket_last_check_id = max(_ticket_last_check_id, msg['id'])
                tid = msg['ticket_id']
                subject = msg['subject'] or ''
                content = msg['message'] or ''

                # Fix-1a: 同 ticket 本轮只处理最后一条（消息按 id 升序，后面的覆盖前面的）
                seen_tickets.add(tid)

                # Fix-1b: 跨轮次防重 — 上一轮已在处理中的 ticket 跳过
                if tid in _ticket_in_flight:
                    continue

                # 检查此消息是否已有管理员回复（DB 级去重）
                cur.execute(
                    "SELECT 1 FROM v2_ticket_message "
                    "WHERE ticket_id = %s AND user_id = %s AND id > %s LIMIT 1",
                    (tid, _TICKET_ADMIN_ID, msg['id'])
                )
                if cur.fetchone():
                    continue

                pending.append((
                    tid,
                    msg['ticket_owner'],   # v2_user_id
                    subject,
                    content,
                ))

            # 去掉 seen_tickets 中已在 pending 之外的旧 in_flight 条目
            _ticket_in_flight = {t for t in _ticket_in_flight if t in seen_tickets}
            # 将本轮 pending 加入 in_flight
            for tid, *_ in pending:
                _ticket_in_flight.add(tid)
        # DB 连接已释放（with 块结束）

        # ── 阶段 2：通过 ticketing adapter 处理（auto_triage + AI）──
        # ticketing adapter 在 telegram-bot 侧，checkin-api 用内联方式调用同逻辑
        import sys, os
        _bot_path = os.path.join(os.path.dirname(__file__), '..', 'telegram-bot', 'yue')
        if _bot_path not in sys.path:
            sys.path.insert(0, _bot_path)

        # _ticket_tokens_by_ticket: 在 call_llm 调用后记录真实 token 数，供后续 tracker 使用
        _ticket_tokens_by_ticket: dict[int, int] = {}

        def _call_llm_for_ticket(messages, max_tokens=140, temperature=0.65,
                                  _ticket_id_hint: int = 0):
            """调用 LLM，返回清理后的回复文本（None 表示失败）。
            实际 token 数记录到 _ticket_tokens_by_ticket[_ticket_id_hint]。
            """
            try:
                from support_core.llm import apply_anthropic_cache as _aac
                payload = _json.dumps({
                    'model': _OPENROUTER_MODEL,
                    'messages': _aac(messages, _OPENROUTER_MODEL),
                    'max_tokens': max_tokens, 'temperature': temperature,
                }).encode()
                req = urllib.request.Request(_OPENROUTER_URL, data=payload, headers={
                    'Authorization': f'Bearer {_OPENROUTER_KEY}',
                    'Content-Type': 'application/json',
                })
                with urllib.request.urlopen(req, timeout=15) as resp:
                    data = _json.loads(resp.read())
                ai_reply = data['choices'][0]['message']['content']
                if '</think>' in ai_reply:
                    ai_reply = ai_reply.split('</think>')[-1].strip()
                cleaned = _clean_ai_response(ai_reply)
                # 记录真实 token；fallback 用输出字符估算
                tokens = int((data.get('usage') or {}).get('total_tokens') or 0)
                if tokens <= 0 and cleaned:
                    tokens = max(len(cleaned) // 3, 1)
                if _ticket_id_hint:
                    _ticket_tokens_by_ticket[_ticket_id_hint] = tokens
                return cleaned
            except Exception as e:
                logger.warning('工单 LLM 调用失败: %s', e)
                return None

        replies = []  # list of (ticket_id, ai_reply)
        try:
            from ticketing.adapters_bridge import process_ticket_message as _ptm
        except Exception:
            # fallback: 直接导入
            try:
                from adapters.ticketing import process_ticket_message as _ptm
            except Exception:
                _ptm = None

        for ticket_id, user_v2_id, subject, content in pending:
            try:
                # ── 优先检查自动回复规则（领奖/兑奖/余额转移等，无需 AI） ──
                auto_rule = _match_auto_close_rule(subject, content)
                if auto_rule:
                    replies.append((ticket_id, auto_rule['reply']))
                    if auto_rule.get('auto_close'):
                        # 标记需要自动关单的 ticket_id
                        if not hasattr(_match_auto_close_rule, '_close_set'):
                            _match_auto_close_rule._close_set = set()
                        _match_auto_close_rule._close_set.add(ticket_id)
                    continue

                # ── 提现：跳过，留给人工处理 ──
                full_text = f"{subject} {content}"
                if any(kw in full_text for kw in _TICKET_PAYOUT_KEYWORDS):
                    logger.info("ticket %s: payout keyword detected, skipping AI reply", ticket_id)
                    continue

                # ── 退款：硬拒绝政策，固定回复 + auto_close ──
                if any(kw in full_text for kw in _TICKET_REFUND_KEYWORDS):
                    logger.info("ticket %s: refund detected, fixed reply + auto-close", ticket_id)
                    replies.append((ticket_id, _TICKET_REFUND_REPLY))
                    if not hasattr(_match_auto_close_rule, '_close_set'):
                        _match_auto_close_rule._close_set = set()
                    _match_auto_close_rule._close_set.add(ticket_id)
                    continue

                if _ptm:
                    # 传入 _ticket_id_hint 使 call_llm 能记录该工单的 token 数
                    import functools as _ft
                    _base_llm = _ft.partial(_call_llm_for_ticket, _ticket_id_hint=ticket_id)

                    # facts-first wrapper：工单内容含询价/账单/支付关键词时注入事实，防捏造
                    _ORDER_KW_TKT = frozenset(('充值', '支付', '订单', '到账', '扣费', '没收到', '付款', '买了', '购买'))
                    def _ticket_facts_llm(messages, max_tokens=140, temperature=0.65,
                                          _base=_base_llm, _uid=user_v2_id, _text=content):
                        from web_gateway import _PRICING_KW, _BILLING_KW, _get_pricing_facts, get_ticket_facts_pg
                        t = _text.lower()
                        extra = []
                        if any(kw in t for kw in _PRICING_KW):
                            pf = _get_pricing_facts(get_cursor)
                            if pf:
                                extra.append(f"[价格事实（按此回答，不得捏造）：\n{pf}]")
                        if _uid and any(kw in t for kw in _BILLING_KW):
                            tf = get_ticket_facts_pg(_uid, get_cursor)
                            if tf:
                                extra.append(f"[工单事实（直接引用）：\n{tf}]")
                        # 订单/支付事实（支付没到账、充值记录等场景）
                        if _uid and any(kw in t for kw in _ORDER_KW_TKT):
                            try:
                                from web_gateway import _get_order_facts as _gof
                                of = _gof(_uid, get_cursor)
                                if of:
                                    extra.append(f"[订单事实（严格按此回答，不得捏造金额/状态）：\n{of}]")
                            except Exception:
                                pass
                        if extra:
                            msgs = list(messages)
                            if msgs and msgs[0].get('role') == 'system':
                                msgs[0] = {**msgs[0], 'content': msgs[0]['content'] + '\n\n' + '\n'.join(extra)}
                            return _base(msgs, max_tokens=max_tokens, temperature=temperature)
                        return _base(messages, max_tokens=max_tokens, temperature=temperature)

                    reply = _ptm(
                        ticket_id=ticket_id,
                        user_v2_id=user_v2_id,
                        subject=subject,
                        message=content,
                        get_cursor=get_cursor,
                        call_llm=_ticket_facts_llm,
                    )
                else:
                    # fallback: 旧逻辑
                    reply = _legacy_ticket_reply(ticket_id, user_v2_id, subject, content)
                if reply:
                    replies.append((ticket_id, reply))
            except Exception as e:
                logger.warning('工单 %d 处理失败: %s', ticket_id, e)

        # ── 阶段 3：写入回复（快速，立即释放连接） ──
        if replies:
            with get_cursor() as cur:
                for ticket_id, ai_reply in replies:
                    now_ts = int(time.time())
                    cur.execute(
                        "INSERT INTO v2_ticket_message (user_id, ticket_id, message, created_at, updated_at) "
                        "VALUES (%s, %s, %s, %s, %s)",
                        (_TICKET_ADMIN_ID, ticket_id, ai_reply, now_ts, now_ts)
                    )
                    # 自动关单规则匹配的工单：status=1（关闭）
                    _close_set = getattr(_match_auto_close_rule, '_close_set', set())
                    if ticket_id in _close_set:
                        cur.execute(
                            "UPDATE v2_ticket SET reply_status = 1, status = 1, last_reply_user_id = %s, updated_at = %s WHERE id = %s",
                            (_TICKET_ADMIN_ID, now_ts, ticket_id)
                        )
                        logger.info('工单 %d 已自动回复+关单（%d字）', ticket_id, len(ai_reply))
                    else:
                        cur.execute(
                            "UPDATE v2_ticket SET reply_status = 1, last_reply_user_id = %s, updated_at = %s WHERE id = %s",
                            (_TICKET_ADMIN_ID, now_ts, ticket_id)
                        )
                        logger.info('工单 %d 已自动回复（%d字）', ticket_id, len(ai_reply))

            # Fix-1 cleanup: 写完后从 in_flight 中移除
            for ticket_id, _ in replies:
                _ticket_in_flight.discard(ticket_id)

    except Exception:
        logger.exception('工单 worker 异常')


def _legacy_ticket_reply(ticket_id, user_v2_id, subject, content):
    """旧版 ticket 处理逻辑（adapters.ticketing 不可用时的 fallback）

    提现 → None（留人工）；退款 → 固定政策回复；其余 fallback None。
    """
    full = f"{subject} {content}"
    if any(kw in full for kw in _TICKET_PAYOUT_KEYWORDS):
        return None   # 提现：跳过，留给人工
    if any(kw in full for kw in _TICKET_REFUND_KEYWORDS):
        return _TICKET_REFUND_REPLY
    return None  # fallback 不具备 AI 能力，其余均不处理


def _auto_resolve_worker():
    """节点恢复自动回填工单（每5分钟）"""
    try:
        with get_cursor(dictionary=True) as cur:
            cur.execute("SELECT enabled FROM feature_flags WHERE key = 'ticket_auto_resolve'")
            row = cur.fetchone()
            if not row or not row['enabled']:
                return
    except Exception:
        return
    try:
        import sys, os
        _bot_path = os.path.join(os.path.dirname(__file__), '..', 'telegram-bot', 'yue')
        if _bot_path not in sys.path:
            sys.path.insert(0, _bot_path)
        from ticketing.auto_resolve import run_auto_resolve
        n = run_auto_resolve(get_cursor)
        if n > 0:
            logger.info('auto_resolve: 自动回填 %d 个工单', n)
    except Exception as e:
        logger.debug('auto_resolve_worker 异常: %s', e)


# ── Emby client endpoint ───────────────────────────────────────────────────

_EMBY_URL = 'https://stream.yue.to'
_EMBY_API_KEY = '82daa86df5ea4b768b871eb151947ff2'
_EMBY_SERVER_ID = 'b965929f40dc4bfea0b5a1027be3e9d3'

@app.get('/api/client/emby')
def client_emby(request: _Request):
    """Return Emby access info for the current user."""
    auth = request.headers.get('authorization', '')
    if not auth:
        raise HTTPException(status_code=401, detail='missing_token')

    # Authenticate via XBoard
    user_info = get_user_profile_pg(auth, XBOARD_BASE, get_cursor)
    email = user_info.get('email', '')
    if not email:
        return {'status': 'fail', 'data': None, 'message': '无法获取用户信息'}

    # Emby username = email with @ replaced by _
    emby_username = email.replace('@', '_').replace('.', '_')

    # Find user in Emby
    try:
        import urllib.request as _ur
        req = _ur.Request(
            f'{_EMBY_URL}/emby/Users?api_key={_EMBY_API_KEY}',
            headers={'Accept': 'application/json'},
        )
        with _ur.urlopen(req, timeout=10) as resp:
            users = _json.loads(resp.read())

        emby_user = None
        for u in users:
            if u['Name'].lower() == emby_username.lower():
                emby_user = u
                break

        if not emby_user:
            return {'status': 'success', 'data': {'emby_url': None, 'auto_login_url': None}}

        user_id = emby_user['Id']
        auto_login_url = (
            f'{_EMBY_URL}/web/index.html'
            f'?userId={user_id}'
            f'&accessToken={_EMBY_API_KEY}'
            f'&serverId={_EMBY_SERVER_ID}'
        )

        return {
            'status': 'success',
            'data': {
                'emby_url': _EMBY_URL,
                'auto_login_url': auto_login_url,
            },
        }
    except Exception as e:
        logger.warning('Emby lookup failed: %s', e)
        return {'status': 'fail', 'data': None, 'message': '媒体服务暂时不可用'}


# ── Anonymous telemetry ────────────────────────────────────────────────────

from pydantic import BaseModel as _TBaseModel, Field as _TField
from typing import List as _TList

class _TelemetryBatch(_TBaseModel):
    events: _TList[dict] = _TField(default_factory=list)


_NODE_EVENT_NAMES = {
    'node_urltest', 'node_select', 'connect_start', 'connect_ok', 'connect_fail',
    'relay_selected', 'relay_failed', 'node_error',
}
_NPS_EVENT_NAMES = {'nps_response', 'nps_submit', 'nps_score'}


def _telemetry_hash_id(value) -> str | None:
    value = str(value or '').strip()
    if not value:
        return None
    payload = f'{TELEMETRY_ID_SALT}:{value}'.encode('utf-8', errors='ignore')
    return hashlib.sha256(payload).hexdigest()[:32]


def _telemetry_str(value, limit: int = 128) -> str | None:
    if value is None:
        return None
    value = str(value).strip()
    if not value:
        return None
    return value[:limit]


def _telemetry_int(value, default: int | None = None) -> int | None:
    try:
        if value is None or value == '':
            return default
        return int(float(value))
    except Exception:
        return default


def _telemetry_ts(ev: dict, server_ts: int) -> int:
    ts = _telemetry_int(ev.get('ts'), server_ts) or server_ts
    # Ignore impossible client clocks; keep the server-side receipt time.
    if ts < 1577836800000 or ts > server_ts + 7 * 86400000:
        return server_ts
    return ts


def _normalize_protocol(value) -> str | None:
    value = _telemetry_str(value, 32)
    if not value:
        return None
    low = value.lower()
    if low in ('hy2', 'hysteria', 'hysteria2'):
        return 'hysteria2'
    if low in ('vless', 'reality', 'vless-reality'):
        return 'vless'
    return low[:32]


def _telemetry_safe_json(value, depth: int = 0):
    if depth > 4:
        return None
    if value is None or isinstance(value, (bool, int, float)):
        return value
    if isinstance(value, str):
        return value[:512]
    if isinstance(value, list):
        if depth == 0:
            value = value[:100]
        return [_telemetry_safe_json(v, depth + 1) for v in value[:100]]
    if isinstance(value, dict):
        out = {}
        for i, (k, v) in enumerate(value.items()):
            if i >= 100:
                break
            key = str(k)[:80]
            low = key.lower()
            if low in ('authorization', 'token', 'access_token', 'password', 'email'):
                out[key] = '[redacted]'
            elif low == 'nodes' and isinstance(v, list):
                out[key] = {'count': len(v), 'omitted': True}
            else:
                out[key] = _telemetry_safe_json(v, depth + 1)
        return out
    return str(value)[:256]


def _telemetry_path_class_for_xb_server_id(xb_server_id) -> str | None:
    xb_server_id = _telemetry_int(xb_server_id)
    if xb_server_id is None:
        return None
    try:
        stat = os.stat(TELEMETRY_NODE_INVENTORY_PATH)
        mtime = stat.st_mtime
        if _telemetry_path_cache.get('mtime') != mtime:
            with open(TELEMETRY_NODE_INVENTORY_PATH, 'r', encoding='utf-8') as fh:
                rows = _json.load(fh)
            by_id = {}
            if isinstance(rows, list):
                for row in rows:
                    if not isinstance(row, dict):
                        continue
                    rid = _telemetry_int(row.get('id'))
                    path_class = _telemetry_str(row.get('path_class'), 32)
                    if rid is not None and path_class:
                        by_id[rid] = path_class
            _telemetry_path_cache['mtime'] = mtime
            _telemetry_path_cache['by_id'] = by_id
    except Exception:
        return None
    return (_telemetry_path_cache.get('by_id') or {}).get(xb_server_id)


def _telemetry_request_ip(request: _Request) -> str:
    peer = (request.client.host if request.client else '') or ''
    try:
        peer_addr = ipaddress.ip_address(peer)
        trusted_proxy = peer_addr.is_loopback or peer_addr.is_private
    except Exception:
        trusted_proxy = False
    if trusted_proxy:
        forwarded = request.headers.get('x-forwarded-for', '').split(',')[0].strip()
        if forwarded:
            return forwarded
    return peer


# yuelink:cymru-v6+carrier
# Major Chinese ISP ASN -> coarse carrier (CT/CU/CM/EDU). Anything else
# routed in CN falls through to CN_OTHER on the call site below.
_CN_CARRIER_ASN = {
    # China Telecom (incl. CN2 GIA)
    4134: 'CT', 4812: 'CT', 4811: 'CT', 17621: 'CT', 17816: 'CT',
    23724: 'CT', 9929: 'CT', 4847: 'CT', 23764: 'CT',
    # China Unicom
    4837: 'CU', 4808: 'CU', 17622: 'CU',
    # China Mobile
    9808: 'CM', 56040: 'CM', 24400: 'CM', 134810: 'CM', 137697: 'CM',
    9394: 'CM', 56046: 'CM', 24445: 'CM',
    # CERNET (education)
    4538: 'EDU', 4565: 'EDU',
}


def _cymru_qname(addr) -> str:
    if addr.version == 4:
        return '.'.join(reversed(str(addr).split('.'))) + '.origin.asn.cymru.com'
    # IPv6: expand to 32 nibble groups, reverse, dot-join, add origin6 suffix.
    nibbles = addr.exploded.replace(':', '')
    return '.'.join(reversed(nibbles)) + '.origin6.asn.cymru.com'


def _telemetry_client_context(ip: str) -> dict:
    try:
        addr = ipaddress.ip_address(ip)
    except Exception:
        return {}
    if addr.is_loopback or addr.is_private or addr.is_multicast or addr.is_unspecified:
        return {}
    cache_key = hashlib.sha256(
        f'{TELEMETRY_ID_SALT}:ip:{ip}'.encode('utf-8', errors='ignore')
    ).hexdigest()[:16]
    now = time.time()
    cached = _telemetry_client_net_cache.get(cache_key)
    if cached and now - cached[0] < 3600:
        return dict(cached[1])
    qname = _cymru_qname(addr)
    # yuelink:cymru-retry-no-failure-cache
    # 2-attempt loop: recursive DNS to origin*.asn.cymru.com is flaky
    # under cache miss, especially for v6 which queries fewer roots.
    # Failed lookups deliberately do NOT write the cache so the next
    # request retries instead of locking the IP out for an hour.
    ctx = {}
    for attempt in range(2):
        try:
            result = subprocess.run(
                ['dig', '+time=2', '+tries=2', '+short', 'TXT', qname],
                text=True,
                capture_output=True,
                timeout=max(1.0, TELEMETRY_CYMRU_TIMEOUT),
            )
            line = (result.stdout or '').splitlines()[0] if result.stdout else ''
            line = line.replace('"', '').strip()
            if not line:
                if attempt == 0:
                    time.sleep(0.3)
                    continue
                break
            parts = [p.strip() for p in line.split('|')]
            if len(parts) >= 3:
                asn = _telemetry_int(parts[0])
                cc = _telemetry_str(parts[2], 2)
                if asn is not None:
                    ctx['client_asn'] = asn
                if cc:
                    cc_upper = cc.upper()
                    ctx['client_cc'] = cc_upper
                    if cc_upper == 'CN':
                        ctx['client_region_coarse'] = 'CN'
                        ctx['client_carrier'] = _CN_CARRIER_ASN.get(asn, 'CN_OTHER')
            break
        except Exception:
            if attempt == 0:
                continue
    if ctx:
        _telemetry_client_net_cache[cache_key] = (now, ctx)
        if len(_telemetry_client_net_cache) > 4096:
            _telemetry_client_net_cache.clear()
    return dict(ctx)


def _telemetry_event_props(
    ev: dict,
    client_hash: str | None,
    session_hash: str | None,
    client_context: dict | None = None,
) -> dict:
    props = _telemetry_safe_json(dict(ev)) or {}
    if client_hash:
        props['client_id'] = client_hash
    else:
        props.pop('client_id', None)
    if session_hash:
        props['session_id'] = session_hash
    else:
        props.pop('session_id', None)
    xb_server_id = _telemetry_int(ev.get('xb_server_id') or props.get('xb_server_id'))
    path_class = _telemetry_path_class_for_xb_server_id(xb_server_id)
    if path_class:
        props['path_class'] = path_class
    for key, value in (client_context or {}).items():
        if value is not None:
            props[key] = value
    return props


def _telemetry_bool_smallint(value) -> int | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return 1 if value else 0
    if isinstance(value, (int, float)):
        return 1 if value else 0
    low = str(value).strip().lower()
    if low in ('1', 'true', 'yes', 'ok', 'success'):
        return 1
    if low in ('0', 'false', 'no', 'fail', 'failed', 'error'):
        return 0
    return None


def _telemetry_upsert_identity(cur, fp, protocol, ts, node: dict | None = None):
    fp = _telemetry_str(fp, 64)
    if not fp:
        return
    node = node or {}
    label = _telemetry_str(node.get('label') or node.get('name'), 200)
    region = _telemetry_str(node.get('region'), 50)
    sid = _telemetry_str(node.get('sid') or node.get('server_sid'), 80)
    xb_server_id = _telemetry_int(
        node.get('xb_server_id') or node.get('server_id') or node.get('node_id') or node.get('id')
    )
    protocol = _normalize_protocol(node.get('protocol') or node.get('type') or protocol)
    cur.execute(
        f"""
        INSERT INTO {_telemetry_sql('node_identity')} AS ni
            (current_fp, label, protocol, region, sid, xb_server_id, first_seen, last_seen)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (current_fp) DO UPDATE SET
            label = COALESCE(NULLIF(EXCLUDED.label, ''), ni.label),
            protocol = COALESCE(NULLIF(EXCLUDED.protocol, ''), ni.protocol),
            region = COALESCE(NULLIF(EXCLUDED.region, ''), ni.region),
            sid = COALESCE(NULLIF(EXCLUDED.sid, ''), ni.sid),
            xb_server_id = COALESCE(EXCLUDED.xb_server_id, ni.xb_server_id),
            last_seen = GREATEST(ni.last_seen, EXCLUDED.last_seen),
            retired_at = NULL
        """,
        (fp, label, protocol, region, sid, xb_server_id, ts, ts),
    )


def _telemetry_store_batch(events: list[dict], client_context: dict | None = None) -> tuple[int, int]:
    if _telemetry_pool is None:
        return 0, 0

    server_ts = int(time.time() * 1000)
    stored = 0
    node_stored = 0
    with get_telemetry_cursor() as cur:
        if cur is None:
            return 0, 0
        _ensure_telemetry_schema(cur)
        for raw in events[:50]:
            if not isinstance(raw, dict):
                continue
            name = _telemetry_str(raw.get('event') or 'unknown', 80) or 'unknown'
            ts = _telemetry_ts(raw, server_ts)
            platform = _telemetry_str(raw.get('platform'), 32)
            version = _telemetry_str(raw.get('version'), 40)
            client_hash = _telemetry_hash_id(raw.get('client_id'))
            session_hash = _telemetry_hash_id(raw.get('session_id'))
            props = _telemetry_event_props(raw, client_hash, session_hash, client_context)

            cur.execute(
                f"""
                INSERT INTO {_telemetry_sql('events')}
                    (ts, server_ts, day, event, client_id, session_id, platform, version, props)
                VALUES (%s, %s, to_timestamp(%s / 1000.0)::date, %s, %s, %s, %s, %s, %s)
                """,
                (
                    ts, server_ts, ts, name, client_hash, session_hash,
                    platform, version, psycopg2.extras.Json(props),
                ),
            )
            stored += 1

            nodes = raw.get('nodes')
            if name == 'node_inventory' and isinstance(nodes, list):
                for node in nodes[:500]:
                    if isinstance(node, dict):
                        _telemetry_upsert_identity(
                            cur,
                            node.get('fp'),
                            node.get('type') or node.get('protocol'),
                            ts,
                            node,
                        )

            fp = _telemetry_str(raw.get('fp'), 64)
            protocol = _normalize_protocol(raw.get('type') or raw.get('protocol'))
            if fp:
                _telemetry_upsert_identity(cur, fp, protocol, ts, raw)

            if fp or name in _NODE_EVENT_NAMES:
                ok = _telemetry_bool_smallint(raw.get('ok'))
                if name == 'connect_ok' and ok is None:
                    ok = 1
                elif name in ('connect_fail', 'relay_failed', 'node_error') and ok is None:
                    ok = 0
                cur.execute(
                    f"""
                    INSERT INTO {_telemetry_sql('node_events')}
                        (ts, day, client_id, platform, version, event, fp, type, region,
                         delay_ms, ok, reason, group_name)
                    VALUES
                        (%s, to_timestamp(%s / 1000.0)::date, %s, %s, %s, %s, %s, %s, %s,
                         %s, %s, %s, %s)
                    """,
                    (
                        ts, ts, client_hash, platform, version, name, fp, protocol,
                        _telemetry_str(raw.get('region'), 50),
                        _telemetry_int(raw.get('delay_ms') or raw.get('latency_ms')),
                        ok,
                        _telemetry_str(raw.get('reason') or raw.get('error'), 200),
                        _telemetry_str(raw.get('group_name') or raw.get('group'), 200),
                    ),
                )
                node_stored += 1

            if name in _NPS_EVENT_NAMES or 'nps' in name:
                score = _telemetry_int(raw.get('score'))
                if score is not None and 0 <= score <= 10:
                    cur.execute(
                        f"""
                        INSERT INTO {_telemetry_sql('nps_responses')}
                            (ts, day, client_id, platform, version, score, comment)
                        VALUES (%s, to_timestamp(%s / 1000.0)::date, %s, %s, %s, %s, %s)
                        """,
                        (
                            ts, ts, client_hash, platform, version, score,
                            _telemetry_str(raw.get('comment'), 1000),
                        ),
                    )

    return stored, node_stored


def _telemetry_parse_flag(value: str):
    try:
        return _json.loads(value)
    except Exception:
        low = str(value).strip().lower()
        if low in ('true', '1', 'yes', 'on'):
            return True
        if low in ('false', '0', 'no', 'off', ''):
            return False
        return value


def _telemetry_rollout_enabled(client_hash: str | None, key: str, rollout_pct: int | None) -> bool:
    pct = max(0, min(100, int(rollout_pct if rollout_pct is not None else 100)))
    if pct >= 100:
        return True
    if pct <= 0:
        return False
    seed = f'{client_hash or "anonymous"}:{key}'.encode('utf-8', errors='ignore')
    bucket = int(hashlib.sha256(seed).hexdigest()[:8], 16) % 100
    return bucket < pct


@app.get('/api/client/telemetry/flags')
async def client_telemetry_flags(request: _Request):
    """Return anonymous telemetry feature flags. Fails open with an empty flag map."""
    client_hash = _telemetry_hash_id(request.query_params.get('client_id', ''))
    flags = {}
    updated_at = 0
    try:
        with get_telemetry_cursor() as cur:
            if cur is not None:
                _ensure_telemetry_schema(cur)
                cur.execute(
                    f"SELECT key, value_json, rollout_pct, updated_at FROM {_telemetry_sql('feature_flags')}"
                )
                for key, value_json, rollout_pct, row_updated_at in cur.fetchall():
                    key = str(key)
                    value = _telemetry_parse_flag(value_json)
                    if _telemetry_rollout_enabled(client_hash, key, rollout_pct):
                        flags[key] = value
                    else:
                        flags[key] = False
                    try:
                        updated_at = max(updated_at, int(row_updated_at or 0))
                    except Exception:
                        pass
    except Exception as e:
        logger.debug('Telemetry flags unavailable: %s', e)
    return {'ok': True, 'flags': flags, 'data': flags, 'updated_at': updated_at}

@app.post('/api/client/telemetry')
async def client_telemetry(body: _TelemetryBatch, request: _Request):
    """Accept anonymous usage events. No PII — just event name + platform + version."""
    ip = _telemetry_request_ip(request)
    client_context = _telemetry_client_context(ip)
    events = body.events[:50]
    try:
        stored, node_stored = _telemetry_store_batch(events, client_context)
    except Exception as e:
        stored, node_stored = 0, 0
        logger.warning('Telemetry store failed: %s', e)

    try:
        names: dict[str, int] = {}
        versions: dict[str, int] = {}
        for ev in events:
            name = str(ev.get('event', 'unknown'))[:64]
            version = str(ev.get('version', '?'))[:32]
            names[name] = names.get(name, 0) + 1
            versions[version] = versions.get(version, 0) + 1
        logger.info(
            "[TELEMETRY] batch asn=%s cc=%s count=%s stored=%s node_stored=%s events=%s versions=%s",
            client_context.get('client_asn'), client_context.get('client_cc'),
            len(events), stored, node_stored, names, versions,
        )
    except Exception:
        pass
    return {'ok': True, 'count': len(events), 'stored': stored, 'node_stored': node_stored}
