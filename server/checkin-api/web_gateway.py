"""Web/XBoard Chat Gateway — 统一走 support_core 内核

v2 (2026-04): 删除独立实现的意图/prompt/质检/成本追踪代码，
改为调用 telegram-bot/yue/support_core.process_core()，
保证全渠道规则一致。仅保留 Web 特有逻辑（bearer token 解析）。
"""
from __future__ import annotations

# 确保 support_core 可导入（checkin-api 是独立进程）
import sys as _sys, os as _os
_bot_path = _os.path.join(_os.path.dirname(__file__), '..', 'telegram-bot', 'yue')
if _bot_path not in _sys.path:
    _sys.path.insert(0, _bot_path)

import json as _json
import logging
import os
import re
import threading
import time
import urllib.request
from datetime import date
from typing import Optional

logger = logging.getLogger(__name__)

OPENROUTER_KEY   = os.getenv("OPENROUTER_API_KEY", "")
OPENROUTER_MODEL = os.getenv("OPENROUTER_MODEL", "anthropic/claude-haiku-4.5")
OPENROUTER_URL   = "https://openrouter.ai/api/v1/chat/completions"

MONTHLY_BUDGET   = float(os.getenv("AI_MONTHLY_BUDGET", "59.0"))

# ── 意图关键词（精简版，与 tg_group 对齐）──
_COMPLAINT_KW = (
    '连不上', '用不了', '打不开', '上不去', '不能用', '没法用',
    '挂了', '崩了', '断了', '不稳定', '太卡了', '全挂了',
)
_SUPPORT_KW = frozenset((
    '套餐', '流量', '签到', '购买', '续费', '到期', '退款', '价格',
    '订阅', '节点', '客户端', '设备', '积分', '兑换', '工单', '账号',
    '密码', '登录', '充值', '支付', '官网', '下载', '速度', '延迟',
    '悦视频', '游戏加速', 'yuelink', 'clash',
))
_GREETING_KW = ('你好', '在吗', '嗨', 'hi', 'hello', '早上好', '晚上好')
_NOISE_RE = re.compile(
    r'^(哈哈+|2333*|666+|ok|好的|收到|感谢|谢谢|thx|thanks?|对|是的|嗯+|哦+|知道了|了解|明白|\+1|\.+|！+)$',
    re.IGNORECASE
)

# ── 高风险护栏（退款/提现/被盗/投诉，不走 LLM）──
_HIGH_RISK_KW: frozenset[str] = frozenset((
    '退款', '退钱', '退费', '全退', '申请退',
    '提现', '提款', '佣金提现', '佣金到账', '提不出来', '提不了',
    '投诉', '维权', '举报', '律师', '骗我', '欺骗', '欺诈', '被骗',
    '消费者协会', '315',
    '被盗', '账号被盗', '盗号', '封号', '账号封了', '申请解封',
))
_SPECIFIC_AMOUNT_RE = re.compile(
    r'(退|赔|补偿|给我|转给|打给)[^\d]{0,4}(\d+\.?\d*)\s*(元|块|rmb|cny|usd|\$|￥)',
    re.IGNORECASE,
)
_ORDER_STATUS_RE = re.compile(
    r'(订单|充值|支付|付款)(状态|记录|显示|成功|失败|没到账|被吞)',
)

_HIGH_RISK_REPLIES: dict[str, str] = {
    "payout": "佣金提现小悦没办法直接操作，需要后台处理。在面板「工单」里说一下提现金额和收款方式就行～",
    "refund": "退款政策是购买后不退款，这个没有例外。有其他问题可以继续问我。",
    "dispute": "收到，这个情况我帮你记录下来了。",
    "stolen": "账号安全问题很紧急，我帮你记录了。请尽快改密码，有问题继续问我。",
    "amount": "金额问题我帮你查一下订单记录。如果查不到，把支付截图发给我看看。",
    "order": "我帮你查一下充值记录。如果没查到，把支付截图发给我看看。",
}


def _billing_safety_check(text: str) -> str | None:
    """命中高风险关键词则返回固定安全回复，否则返回 None。

    充值/支付状态/订单查询（_ORDER_STATUS_RE）不在此处拦截——
    这类问题应走 facts 注入路径（v2_order 真实数据），避免误杀能自助解答的场景。
    只拦截：退款请求、提现、投诉/维权、账号被盗、明确要求特定金额。
    """
    t = text.lower()
    if any(kw in t for kw in ('退款', '退钱', '退费', '全退', '申请退')):
        return _HIGH_RISK_REPLIES["refund"]
    if any(kw in t for kw in ('提现', '提款', '佣金提现', '佣金到账', '提不出来', '提不了')):
        return _HIGH_RISK_REPLIES["payout"]
    if any(kw in t for kw in ('投诉', '维权', '举报', '律师', '骗我', '欺骗', '欺诈', '被骗', '消费者协会', '315')):
        return _HIGH_RISK_REPLIES["dispute"]
    if any(kw in t for kw in ('被盗', '账号被盗', '盗号', '封号', '账号封了', '申请解封')):
        return _HIGH_RISK_REPLIES["stolen"]
    if _SPECIFIC_AMOUNT_RE.search(text):
        return _HIGH_RISK_REPLIES["amount"]
    # 注意：充值/支付状态/订单没到账 —— 不在此拦截，走 facts 注入路径
    return None


def classify_intent(text: str) -> str:
    t = text.lower().strip()
    if len(text) <= 2 or _NOISE_RE.match(t):
        return "skip"
    if any(t.startswith(g) or t == g for g in _GREETING_KW):
        return "greeting"
    if any(kw in text for kw in _COMPLAINT_KW):
        return "complaint"
    if any(kw in t for kw in _SUPPORT_KW):
        return "support"
    has_q = '?' in text or '？' in text
    if has_q or len(text) >= 8:
        return "support"
    return "chat"


# ── 预算检查（读 DB 日汇总）──
_budget_cache: tuple[float, float] = (0.0, 0.0)  # (value, expire_ts)
_budget_lock = threading.Lock()


def _get_monthly_spent(get_cursor) -> float:
    global _budget_cache
    with _budget_lock:
        val, exp = _budget_cache
        if time.time() < exp:
            return val
    try:
        month = date.today().strftime("%Y-%m")
        with get_cursor(dictionary=True) as cur:
            cur.execute(
                "SELECT COALESCE(SUM(cost_usd), 0) AS total FROM ai_cost_daily WHERE date::text LIKE %s",
                (f"{month}%",),
            )
            row = cur.fetchone()
            spent = float(row["total"]) if row else 0.0
        with _budget_lock:
            _budget_cache = (spent, time.time() + 60)  # 缓存60s
        return spent
    except Exception:
        return 0.0


def budget_ok(get_cursor, intent: str) -> bool:
    """True = 可以继续调 LLM"""
    if MONTHLY_BUDGET <= 0:
        return True
    spent = _get_monthly_spent(get_cursor)
    ratio = spent / MONTHLY_BUDGET
    if ratio >= 0.95:
        return False
    if ratio >= 0.85 and intent not in ("complaint", "billing", "support"):
        return False
    return True


# ── 主处理函数（同步，用于非流式端点）──

def process_sync(
    text: str,
    session_id: str,
    history: list,
    user_profile: Optional[dict],
    faq_answer: Optional[str],
    node_diag: Optional[str],
    channel: str,
    get_cursor,
) -> Optional[str]:
    """同步调用 support_core 统一内核，返回回复文本或 None

    v2: 删除独立实现的意图/prompt/质检，改为走 support_core.process_core()。
    Web 特有的 bearer token 解析由调用方完成后传入 user_profile。
    """
    from support_core import process_core
    from ai_gateway.types import AiRequest, Channel

    # 构造统一请求
    ch = Channel.XBOARD if channel == "xboard" else Channel.WEB
    extra = {}
    if user_profile:
        extra["v2_user_id"] = user_profile.get("v2_user_id")
        extra["bearer_token"] = user_profile.get("_bearer_token")

    request = AiRequest(
        channel=ch,
        text=text,
        user_id=session_id,
        history=history or [],
        is_direct=True,  # Web/XBoard 都是用户主动发起
        extra=extra,
    )

    resp = process_core(request, get_cursor_fn=get_cursor)

    if resp.handled and resp.text:
        # 持久化会话（跨渠道续接）
        try:
            from support_core.session import save_turn
            v2_uid = extra.get("v2_user_id")
            save_turn(channel, session_id, text, resp.text,
                      resp.intent.value if resp.intent else "",
                      v2_user_id=v2_uid)
        except Exception:
            pass
        return resp.text
    return None


# ── 消息构建 ──

# LEGACY: SSE 流式路径仍在用这些常量，process_sync 已改为走 support_core
# 后续统一 SSE 路径后可删除
_PERSONA = """你叫小悦，悦通加速的客服。说话简洁自然，像朋友聊天。
直接回答1-3句，不猜不编，不用客服套话。你不是AI。所有问题自己解答，不要让用户找管理员或提工单（提现除外）。余额月底自动清零。"""

_BIZ = """
- 官网 yue.to，客户端推荐 YueLink，也能用 Clash Meta / Stash / Shadowrocket。原版 Clash 已停更不兼容，必须用 Clash Meta
- 套餐月付季付年付，购买后不退款，新套餐替换旧套餐。续费同款是延期不替换
- 签到领流量（扣已用）或余额，连签有加成（8天×1.2，15天×1.3，30天×1.5）；连签满7/14/30/60/90天有额外余额里程碑奖励；断签减半不归零；余额月底自动清零
- 竞猜赢了扣已用流量，输了加已用流量。积分靠竞猜攒（<10GB=1分，10-49GB=2分，50-99GB=3分，100-199GB=4分，200-499GB=5分，500GB+=8分），可换流量/补签卡/加次数/保险卡/赛事券/幸运抽奖
- 每日任务：签到+竞猜+查流量，完成有额外奖励
- iOS客户端：YueLink iOS版开发中，目前用Shadowrocket或Stash
- 支付：支付宝、微信、USDT（手续费8%）
- 没有优惠码，没有限速"""

_TROUBLESHOOT = """连不上排查：1.套餐过期？2.更新订阅？3.换节点（韩/台/美）4.重启客户端 5.切换连接方式 6.换网络"""

_INTENT_PARAMS = {
    "greeting":  {"max_tokens": 60,  "temperature": 0.9},
    "support":   {"max_tokens": 140, "temperature": 0.65},
    "complaint": {"max_tokens": 140, "temperature": 0.6},
    "chat":      {"max_tokens": 120, "temperature": 0.85},
}


def _get_pricing_facts(get_cursor) -> str:
    """从 v2_plan 查当前在售套餐，返回 prompt 注入文本。失败返回空字符串。"""
    import json as _j
    _PERIOD_CN = {
        "monthly": "月付", "quarterly": "季付",
        "half_yearly": "半年付", "yearly": "年付",
        "onetime": "一次性",
    }
    try:
        with get_cursor(dictionary=True) as cur:
            cur.execute(
                "SELECT name, transfer_enable, prices FROM v2_plan"
                " WHERE show = true AND sell = true ORDER BY sort ASC NULLS LAST, id ASC LIMIT 5",
            )
            rows = cur.fetchall()
        if not rows:
            return "当前暂无在售套餐，请到官网 yue.to 查看。"
        lines = ["当前在售套餐："]
        for r in rows:
            name = r.get("name") or "?"
            gb = int(r.get("transfer_enable") or 0)
            raw = r.get("prices") or {}
            if isinstance(raw, str):
                try: raw = _j.loads(raw)
                except Exception: raw = {}
            price_parts = []
            for period in ("monthly", "quarterly", "yearly", "onetime"):
                val = raw.get(period)
                if val not in (None, "", 0, "0"):
                    try:
                        price_parts.append(f"{_PERIOD_CN.get(period, period)}¥{float(val)/100:.0f}")
                    except (ValueError, TypeError):
                        pass
            price_str = " / ".join(price_parts) or "见官网"
            lines.append(f"  · {name}（{gb}GB）：{price_str}")
        return "\n".join(lines)
    except Exception:
        return ""


def get_ticket_facts_pg(v2_user_id: Optional[int], get_cursor) -> str:
    """查询用户最近工单状态，返回 prompt 注入文本。

    供 checkin-api 内部 AI 端点调用（PG 直查）。
    reply_status: 0=待回复（等管理员），1=已回复（等用户）
    """
    if not v2_user_id:
        return ""
    _STATUS_CN = {0: "待回复（处理中）", 1: "已回复（等用户回复）"}
    try:
        with get_cursor(dictionary=True) as cur:
            cur.execute(
                "SELECT id, subject, reply_status, updated_at"
                " FROM v2_ticket WHERE user_id = %s ORDER BY id DESC LIMIT 2",
                (v2_user_id,),
            )
            tickets = cur.fetchall() or []
        if not tickets:
            return "暂未查到该用户的工单记录。"
        lines = ["该用户最近工单："]
        for t in tickets:
            status = _STATUS_CN.get(t.get("reply_status", 0), "未知")
            subj = (t.get("subject") or "（无标题）")[:40]
            upd = str(t.get("updated_at") or "")[:16]
            line = f"  · 工单#{t['id']}「{subj}」：{status}"
            if upd:
                line += f"  [{upd}]"
            lines.append(line)
        return "\n".join(lines)
    except Exception:
        return ""


def get_user_profile_pg(auth_header: str, xboard_base: str, get_cursor) -> Optional[dict]:
    """通过 XBoard Bearer token 查用户完整画像（含 balance/commission/subscribe_url）。

    供 main.py 各 AI 端点调用，替代内联 SQL。
    失败或匿名均返回 None（不抛异常）。
    """
    if not auth_header or not auth_header.lower().startswith('bearer '):
        return None
    try:
        req = urllib.request.Request(
            f'{xboard_base}/api/v1/user/info',
            headers={'Authorization': auth_header, 'Accept': 'application/json'},
        )
        with urllib.request.urlopen(req, timeout=3) as resp:
            body = _json.loads(resp.read())
        if body.get('status') != 'success':
            return None
        email = (body.get('data') or {}).get('email')
        if not email:
            return None
        with get_cursor(dictionary=True) as cur:
            cur.execute(
                '''SELECT u.id AS v2_user_id, u.u, u.d, u.transfer_enable,
                          u.expired_at, u.token, u.balance, u.commission_balance,
                          p.name AS plan_name
                   FROM v2_user u LEFT JOIN v2_plan p ON u.plan_id = p.id
                   WHERE u.email = %s''',
                (email,),
            )
            row = cur.fetchone()
        if not row:
            return None
        used = int(row['u'] or 0) + int(row['d'] or 0)
        te = int(row['transfer_enable'] or 0)
        remaining_gb = round(max(te - used, 0) / 1024**3, 1)
        exp = int(row['expired_at'] or 0)
        days = max((exp - int(time.time())) // 86400, 0) if exp > 0 else None
        subscribe_url = None
        if row.get('token'):
            subscribe_url = f"{xboard_base}/api/v1/client/subscribe?token={row['token']}"
        balance = round(int(row.get('balance') or 0) / 100, 2)
        commission = round(int(row.get('commission_balance') or 0) / 100, 2)
        return {
            'v2_user_id':    int(row['v2_user_id']),
            'plan':          row.get('plan_name') or '无套餐',
            'remaining_gb':  remaining_gb,
            'days':          days,
            'subscribe_url': subscribe_url,
            'balance':       balance,
            'commission':    commission,
        }
    except Exception:
        return None


def _build_system(intent: str, profile: Optional[dict],
                  faq: Optional[str], diag: Optional[str],
                  get_cursor=None) -> str:
    parts = [_PERSONA]
    if intent in ("support", "complaint"):
        parts.append(_BIZ)
    if intent == "complaint":
        parts.append(_TROUBLESHOOT)
    # Fix-8 (P2): chat/greeting 不注入业务知识，避免回答 Spotify/Google 等问题时推荐 YueLink
    # Fix-8 (P2): chat/greeting 不注入用户信息和诊断，避免闲聊被业务信息污染
    if profile and intent not in ("chat", "greeting"):
        p = profile
        line = f"套餐「{p.get('plan','?')}」，剩余{p.get('remaining_gb',0)}GB"
        if p.get("days") is not None:
            line += f"，{p['days']}天到期"
        parts.append(f"\n[用户信息：{line}。仅用户主动问时参考。]")
        # 订阅链接（已认证用户，仅 support/complaint 意图注入）
        if p.get("subscribe_url") and intent in ("support", "complaint"):
            parts.append(f"\n[该用户订阅链接（直接给用户，勿自行截短）：{p['subscribe_url']}]")
    if diag and intent not in ("chat", "greeting"):
        parts.append(f"\n[系统诊断：{diag}，简短告知用户。]")
    if faq and not diag and intent not in ("chat", "greeting"):
        # Fix-8: chat/greeting 不注入 FAQ，避免无关业务内容污染闲聊回复
        faq_plain = re.sub(r'<[^>]+>', '', faq).strip()[:400]
        parts.append(f"\n[FAQ参考：{faq_plain}，用自己话自然回答。]")
    # 订单/支付查询 fallback 指令：查不到时必须引导人工，不允许猜测
    if intent in ("support", "billing"):
        parts.append(
            "\n[订单/支付规则：若用户询问充值是否到账、订单状态、支付记录，"
            "且[事实数据]中无对应订单，必须回答："
            "「帮你查了没找到记录，把支付截图发给我看看」"
            "不允许猜测、编造任何订单状态或金额。]"
        )
    return "".join(parts)


def _build_system_with_pricing(intent: str, profile: Optional[dict],
                               faq: Optional[str], diag: Optional[str],
                               get_cursor=None) -> str:
    """_build_system 的升级版：support 意图时注入套餐价格事实数据（无 text 时的向后兼容版）"""
    base = _build_system(intent, profile, faq, diag)
    if intent in ("support",) and get_cursor is not None:
        pricing = _get_pricing_facts(get_cursor)
        if pricing:
            base += f"\n\n[事实数据（严格按此回答价格，不得捏造）：\n{pricing}]"
    return base


# ── 事实关键词触发器 ──
_PRICING_KW = frozenset((
    '套餐', '价格', '多少钱', '费用', '月付', '季付', '年付',
    '购买', '续费', '升级', '怎么买', '买哪个', '便宜', '划算', '充值多少',
))
_BILLING_KW = frozenset((
    '工单', '订单', '充值记录', '到账', '扣费', '账单', '佣金',
    '还没到', '没收到', '支付状态', '余额对不上',
))


def _build_system_with_facts(intent: str, profile: Optional[dict],
                              faq: Optional[str], diag: Optional[str],
                              get_cursor=None, text: str = "") -> str:
    """facts-first 升级版：按 text 关键词精准注入 pricing / ticket 事实。

    · 含询价词 + support/complaint → 注入真实价格表（防捏造）
    · 含账单/工单词 + 已认证用户 → 注入最近工单状态
    · 无关键词时不查 DB，节省 RTT
    """
    base = _build_system(intent, profile, faq, diag)
    t = text.lower()

    if intent in ("support", "complaint") and get_cursor is not None:
        # 询价注入
        if any(kw in t for kw in _PRICING_KW):
            pricing = _get_pricing_facts(get_cursor)
            if pricing:
                base += f"\n\n[事实数据（严格按此回答价格，不得捏造）：\n{pricing}]"

        # 工单/账单状态注入（仅已认证用户）
        if profile:
            v2_uid = profile.get("v2_user_id")
            if v2_uid and any(kw in t for kw in _BILLING_KW):
                ticket_facts = get_ticket_facts_pg(v2_uid, get_cursor)
                if ticket_facts:
                    base += f"\n\n[工单事实（直接告知用户，不得捏造其他状态）：\n{ticket_facts}]"

            # 订单事实注入（含充值/支付/订单关键词时注入真实订单记录）
            _ORDER_KW = frozenset(('充值', '支付', '订单', '到账', '扣费', '没收到', '付款', '买了', '购买记录'))
            if v2_uid and any(kw in t for kw in _ORDER_KW):
                order_facts = _get_order_facts(v2_uid, get_cursor)
                if order_facts:
                    base += f"\n\n[订单事实（严格按此回答，不得捏造金额或状态）：\n{order_facts}]"

    return base


def _get_order_facts(v2_user_id: int, get_cursor) -> str:
    """查询 v2_order 最近3条订单，格式化为事实注入文本。

    Schema（生产实测）：status 2=待支付 3=已支付 4=已取消；period monthly/quarterly/yearly/onetime 等。
    """
    # 生产确认映射
    _STATUS_CN = {2: "待支付", 3: "已支付", 4: "已取消"}
    _PERIOD_CN = {
        "monthly": "月付", "quarterly": "季付",
        "half_yearly": "半年付", "yearly": "年付",
        "onetime": "一次性", "reset_traffic": "流量重置",
    }
    try:
        import datetime as _dt
        with get_cursor(dictionary=True) as cur:
            cur.execute(
                """SELECT o.id, o.trade_no, o.period, o.total_amount,
                          o.balance_amount, o.status, o.paid_at, o.created_at,
                          p.name AS gateway_name
                   FROM v2_order o
                   LEFT JOIN v2_payment p ON o.payment_id = p.id
                   WHERE o.user_id = %s ORDER BY o.id DESC LIMIT 3""",
                (v2_user_id,),
            )
            rows = cur.fetchall() or []
        if not rows:
            return (
                "DB 中查无该用户订单记录。"
                "如用户称已支付，让其提供支付截图和大致支付时间，你帮记录下来会有人核实。"
                "严禁猜测或告知虚假订单状态。"
            )
        lines = ["该用户最近订单（生产 DB 实时查询）："]
        for r in rows:
            st = int(r.get("status") or 0)
            amt = round(float(r.get("total_amount") or 0) / 100, 2)
            period = _PERIOD_CN.get((r.get("period") or "").strip(), r.get("period") or "—")
            # 已支付用 paid_at，否则用 created_at
            ts_raw = r.get("paid_at") if st == 3 else r.get("created_at")
            ts_str = ""
            try:
                if ts_raw:
                    ts_str = _dt.datetime.utcfromtimestamp(int(ts_raw)).strftime("%Y-%m-%d %H:%M")
            except Exception:
                pass
            tn = (r.get("trade_no") or "")[-8:]
            gw = r.get("gateway_name") or ""
            line = (
                f"  · 订单#{r['id']} {period} ¥{amt:.2f} "
                f"状态：{_STATUS_CN.get(st, f'未知({st})')}"
                + (f"  时间：{ts_str}" if ts_str else "")
                + (f"  渠道：{gw}" if gw else "")
                + (f"  单号尾：...{tn}" if tn else "")
            )
            lines.append(line)
        lines.append("（以上为 DB 实际记录，严格按此回答，不得编造）")
        return "\n".join(lines)
    except Exception:
        return ""


def _build_messages_list(system: str, history: list, text: str) -> list:
    msgs = [{"role": "system", "content": system}]
    for m in (history or [])[-20:]:
        if isinstance(m, dict) and m.get("role") in ("user", "assistant"):
            msgs.append({"role": m["role"], "content": str(m.get("content", ""))[:300]})
    msgs.append({"role": "user", "content": text})
    return msgs


# ── 成本估算 ──
# 统一委托给 ai_gateway.model_router.estimate_cost，避免重复维护价格表

def _estimate_cost(model: str, tokens: int) -> float:
    """按模型单价估算成本（USD），委托给 model_router 统一价格表。"""
    if tokens <= 0:
        return 0.0
    from ai_gateway.model_router import estimate_cost as _mr_est
    return _mr_est(model, tokens)


def _call_llm_sync(messages: list, max_tokens: int = 150,
                   temperature: float = 0.75) -> tuple[Optional[str], int]:
    """调用 OpenRouter，返回 (response_text, total_tokens)。

    total_tokens 优先取 usage.total_tokens；
    usage 缺失时按字符数保守估算（约 3 字/token），保证不再写死 0。
    """
    try:
        payload = _json.dumps({
            "model": OPENROUTER_MODEL, "messages": messages,
            "max_tokens": max_tokens, "temperature": temperature,
        }).encode()
        req = urllib.request.Request(OPENROUTER_URL, data=payload, headers={
            "Authorization": f"Bearer {OPENROUTER_KEY}",
            "Content-Type": "application/json",
        })
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = _json.loads(resp.read())
        content = data["choices"][0]["message"]["content"]
        if "</think>" in content:
            content = content.split("</think>")[-1].strip()
        text = content.strip() or None
        # 优先读 usage 字段；fallback 按字符估算（min=1 避免除零场景）
        usage = data.get("usage") or {}
        tokens = int(usage.get("total_tokens") or 0)
        if tokens <= 0 and text:
            tokens = max(len(text) // 3, 1)
        return text, tokens
    except Exception as e:
        logger.warning("web_gateway LLM失败: %s", e)
        return None, 0


# ── 响应质检 ──
_SLIP = [
    re.compile(r'作为(一个)?(AI|人工智能|语言模型)(助手|客服)?[，,]?\s*'),
    re.compile(r'我(只)?是(一个)?(AI|人工智能|虚拟|语言模型)(助手)?[，,。]?\s*'),
    re.compile(r'(很高兴|非常高兴)(能够)?为[你您](服务|解答)[！!。]?\s*'),
    re.compile(r'如果[你您](还有|有)(其他|任何)(问题|疑问)[，,]?(随时|欢迎)?(问我|提问|咨询|联系)[。！!]?\s*'),
]


def _clean(text: str) -> str:
    for p in _SLIP:
        text = p.sub('', text)
    text = re.sub(r'^#{1,3}\s+', '', text, flags=re.MULTILINE)
    text = re.sub(r'\*\*(.+?)\*\*', r'\1', text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()


# ── 成本追踪 ──

def _track(session_id: str, channel: str, intent: str,
           model: str, tokens: int, cost: float, day: str, get_cursor,
           usage_estimated: bool = False, model_tier: str = "", router_reason: str = ""):
    """写入 ai_interactions + ai_cost_daily。

    usage_estimated=True 表示 token 数来自字符估算（SSE 流式）。
    model_tier/router_reason 来自 model_router（migration 028）。
    """
    try:
        with get_cursor() as cur:
            cur.execute(
                """INSERT INTO ai_interactions
                   (user_id, channel, intent, model, tokens, cost_usd, created_at, usage_estimated,
                    model_tier, router_reason)
                   VALUES (%s, %s, %s, %s, %s, %s, NOW(), %s, %s, %s)""",
                (session_id, channel, intent, model, tokens, cost, usage_estimated,
                 model_tier or None, router_reason or None),
            )
            cur.execute(
                """INSERT INTO ai_cost_daily (date, channel, calls, tokens, cost_usd)
                   VALUES (%s, %s, 1, %s, %s)
                   ON CONFLICT (date, channel) DO UPDATE SET
                     calls    = ai_cost_daily.calls + 1,
                     tokens   = ai_cost_daily.tokens + EXCLUDED.tokens,
                     cost_usd = ai_cost_daily.cost_usd + EXCLUDED.cost_usd""",
                (day, channel, tokens, cost),
            )
    except Exception as e:
        logger.debug("web_gateway tracker写入失败: %s", e)
