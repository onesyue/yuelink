"""Unit tests for the per-node aggregation helpers in telemetry.py.

Pure Python — no Postgres needed. We bypass `_get_pool` by importing
only the aggregation helpers, which were intentionally extracted as
free functions so this file can run in isolation.

Run:
    python3 -m pytest server/telemetry/test_stats_nodes_aggregation.py -v
or:
    python3 server/telemetry/test_stats_nodes_aggregation.py
"""
from __future__ import annotations

import os
import sys
import unittest

# Stub psycopg2 so importing telemetry.py doesn't try to open a pool.
# The aggregation helpers don't touch the DB; we just need the import
# to succeed.
sys.modules.setdefault("psycopg2", type(sys)("psycopg2"))
sys.modules.setdefault("psycopg2.pool", type(sys)("psycopg2.pool"))
sys.modules.setdefault("psycopg2.extras", type(sys)("psycopg2.extras"))


class _StubPool:
    def __init__(self, *a, **kw):
        pass


sys.modules["psycopg2"].pool = sys.modules["psycopg2.pool"]
sys.modules["psycopg2"].extras = sys.modules["psycopg2.extras"]
sys.modules["psycopg2.pool"].ThreadedConnectionPool = _StubPool


def _stub_connect(*a, **kw):
    raise RuntimeError("DB call attempted in unit test — not allowed")


sys.modules["psycopg2"].connect = _stub_connect

# Quiet the schema-init warning the module prints at import time.
os.environ.setdefault("TELEMETRY_DATABASE_DSN", "host=stub")

# fastapi may not be installed in CI's lightest harness; stub if missing.
try:
    import fastapi  # noqa: F401
    import fastapi.security  # noqa: F401
except ImportError:
    fa = type(sys)("fastapi")
    fa.APIRouter = lambda **kw: type("R", (), {
        "get": lambda *a, **kw: lambda f: f,
        "post": lambda *a, **kw: lambda f: f,
    })()
    fa.Depends = lambda *a, **kw: None
    fa.HTTPException = type("HE", (Exception,), {})
    fa.Request = object
    fa.status = type("S", (), {"HTTP_503_SERVICE_UNAVAILABLE": 503,
                                  "HTTP_401_UNAUTHORIZED": 401})
    fa.responses = type(sys)("fastapi.responses")
    fa.responses.HTMLResponse = object
    fa.responses.JSONResponse = object
    fa.security = type(sys)("fastapi.security")
    fa.security.HTTPBasic = lambda: None
    fa.security.HTTPBasicCredentials = object
    sys.modules["fastapi"] = fa
    sys.modules["fastapi.responses"] = fa.responses
    sys.modules["fastapi.security"] = fa.security

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import telemetry as T  # noqa: E402


def _v1_row(fp, target, ok, latency=None, status=None, err=None,
            cid="client-1", typ="vless", xb_server_id=None,
            path_class=None, client_asn=None, client_cc=None,
            client_region_coarse=None):
    """Shape one synthetic v1 event row as the SQL would return it."""
    return {
        "fp": fp,
        "type": typ,
        "target": target,
        "ok": ok,
        "latency_ms": latency,
        "status_code": status,
        "error_class": err,
        "client_id": cid,
        "xb_server_id": xb_server_id,
        "path_class": path_class,
        "client_asn": client_asn,
        "client_cc": client_cc,
        "client_region_coarse": client_region_coarse,
    }


def _legacy_row(fp, ok, delay=None, reason=None, cid="client-1", typ="vless"):
    return {
        "fp": fp,
        "type": typ,
        "ok": 1 if ok else 0,
        "delay_ms": delay,
        "reason": reason,
        "client_id": cid,
    }


class V1AggregationTest(unittest.TestCase):
    """Behaviours we lock in:
        - users counted as distinct client_ids
        - status_buckets keyed by stringified int
        - error_buckets gets timeout / ssleof etc.
        - latencies feed accurate p50/p95/p99 via _percentile
        - target whitelist falls unknown values into 'other'
        - empty error_buckets / status_buckets serialize as None
    """

    def test_basic_per_target_split_for_one_node(self):
        rows = [
            _v1_row("A", "transport", True, 100),
            _v1_row("A", "transport", True, 110, cid="c2"),
            _v1_row("A", "transport", True, 105),
            _v1_row("A", "claude", True, 800, status=200),
            _v1_row("A", "claude", False, status=403),
            _v1_row("A", "claude", False, err="timeout"),
        ]
        agg = T._aggregate_v1_node_probe_rows(rows)
        self.assertIn("A", agg)
        a = agg["A"]
        self.assertEqual(a["samples"], 6)
        self.assertEqual(a["users"], {"client-1", "c2"})
        self.assertEqual(a["per_target"]["transport"]["attempts"], 3)
        self.assertEqual(a["per_target"]["transport"]["ok"], 3)
        self.assertEqual(
            sorted(a["per_target"]["transport"]["latencies"]),
            [100, 105, 110],
        )
        self.assertEqual(
            a["per_target"]["claude"]["status_buckets"], {"200": 1, "403": 1},
        )
        self.assertEqual(
            a["per_target"]["claude"]["error_buckets"],
            {"ai_blocked": 1, "timeout": 1},
        )

    def test_ai_403_derives_ai_blocked_when_error_missing(self):
        rows = [_v1_row("A", "chatgpt", False, status=403)]
        agg = T._aggregate_v1_node_probe_rows(rows)
        self.assertEqual(
            agg["A"]["per_target"]["chatgpt"]["error_buckets"],
            {"ai_blocked": 1},
        )

    def test_reality_auth_failure_normalizes_to_candidate_signal(self):
        rows = [
            _v1_row("A", "transport", False, err="REALITY authentication failed"),
            _v1_row("A", "transport", False, err="REALITY authentication failed"),
        ]
        agg = T._aggregate_v1_node_probe_rows(rows)
        node = T._shape_node("A", agg["A"], region=None, min_samples=1)
        self.assertEqual(node["state"], "quarantine_candidate")
        self.assertTrue(node["requires_human"])

    def test_unknown_target_collapses_into_other(self):
        rows = [_v1_row("A", "weird-bucket", True, 100)]
        agg = T._aggregate_v1_node_probe_rows(rows)
        self.assertIn("other", agg["A"]["per_target"])
        self.assertNotIn("weird-bucket", agg["A"]["per_target"])

    def test_missing_fp_dropped(self):
        rows = [
            _v1_row(None, "transport", True, 100),
            _v1_row("", "transport", True, 100),
            _v1_row("A", "transport", True, 100),
        ]
        agg = T._aggregate_v1_node_probe_rows(rows)
        self.assertEqual(set(agg.keys()), {"A"})

    def test_non_positive_latency_excluded_from_percentiles(self):
        rows = [
            _v1_row("A", "transport", False, latency=0),     # treat as no data
            _v1_row("A", "transport", False, latency=-1),    # same
            _v1_row("A", "transport", True, latency=200),
        ]
        agg = T._aggregate_v1_node_probe_rows(rows)
        self.assertEqual(agg["A"]["per_target"]["transport"]["latencies"], [200])

    def test_enrichment_dimensions_are_counted(self):
        rows = [
            _v1_row(
                "A", "transport", True, latency=100, xb_server_id=111,
                path_class="via_v4_relay", client_asn=4134,
                client_cc="CN", client_region_coarse="CN",
            ),
            _v1_row(
                "A", "transport", True, latency=110, xb_server_id="111",
                path_class="via_v4_relay", client_asn="4134",
                client_cc="CN", client_region_coarse="CN",
            ),
            _v1_row(
                "A", "transport", True, latency=120, xb_server_id=112,
                path_class="via_v4_relay", client_asn=4837,
                client_cc="CN", client_region_coarse="CN",
            ),
        ]
        agg = T._aggregate_v1_node_probe_rows(rows)
        node = T._shape_node("A", agg["A"], region=None, min_samples=1)
        self.assertEqual(node["top_xb_server_id"], 111)
        self.assertEqual(node["xb_server_ids"], {"111": 2, "112": 1})
        self.assertEqual(node["top_path_class"], "via_v4_relay")
        self.assertEqual(node["path_classes"], {"via_v4_relay": 3})
        self.assertEqual(node["top_client_asn"], 4134)
        self.assertEqual(node["client_asns"], {"4134": 2, "4837": 1})
        self.assertEqual(node["client_countries"], {"CN": 3})


class LegacyAggregationTest(unittest.TestCase):
    """Legacy node_urltest rows must adapt cleanly into the v1 shape so
    the dashboard sees one schema regardless of which event type it
    originated from."""

    def test_urltest_maps_to_transport_target(self):
        rows = [
            _legacy_row("A", True, delay=120),
            _legacy_row("A", True, delay=130, cid="c2"),
            _legacy_row("A", False, delay=-1, reason="timeout"),
        ]
        agg = T._aggregate_legacy_urltest_rows(rows)
        a = agg["A"]
        self.assertEqual(a["samples"], 3)
        self.assertEqual(a["users"], {"client-1", "c2"})
        t = a["per_target"]["transport"]
        self.assertEqual(t["attempts"], 3)
        self.assertEqual(t["ok"], 2)
        self.assertEqual(sorted(t["latencies"]), [120, 130])
        self.assertEqual(t["error_buckets"], {"timeout": 1})

    def test_no_status_buckets_in_legacy(self):
        # legacy events never carry status_code — bucket should stay empty
        agg = T._aggregate_legacy_urltest_rows([_legacy_row("A", True, 100)])
        self.assertEqual(agg["A"]["per_target"]["transport"]["status_buckets"], {})


class ShapeTest(unittest.TestCase):
    """The output schema is the contract dashboards depend on. Any
    rename / removal here is a breaking change for /stats/nodes
    consumers."""

    def test_shape_contains_full_target_record(self):
        agg = {
            "type": "vless",
            "users": {"c1", "c2"},
            "samples": 6,
            "per_target": {
                "transport": {
                    "attempts": 3, "ok": 3, "latencies": [100, 110, 105],
                    "status_buckets": {}, "error_buckets": {},
                },
                "claude": {
                    "attempts": 3, "ok": 1, "latencies": [800],
                    "status_buckets": {"200": 1, "403": 1},
                    "error_buckets": {"timeout": 1},
                },
            },
        }
        node = T._shape_node("A", agg, region="HK", min_samples=3)
        self.assertEqual(node["fp"], "A")
        self.assertEqual(node["region"], "HK")
        self.assertIsNone(node["top_path_class"])
        self.assertIsNone(node["path_classes"])
        self.assertIn(node["state"], T.NODE_HEALTH_STATES)
        self.assertEqual(node["state"], "ai_blocked")
        self.assertFalse(node["requires_human"])
        self.assertEqual(node["users"], 2)
        self.assertEqual(node["samples"], 6)
        self.assertFalse(node["insufficient_data"])
        # transport
        tr = node["per_target"]["transport"]
        self.assertEqual(tr["success_rate"], 1.0)
        self.assertEqual(tr["timeout_rate"], 0.0)
        self.assertEqual(tr["p50_ms"], 105)
        self.assertEqual(tr["p95_ms"], 110)
        self.assertEqual(tr["top_error_class"], None)
        self.assertIsNone(tr["status_buckets"])  # empty → None
        self.assertIsNone(tr["error_buckets"])
        # claude
        cl = node["per_target"]["claude"]
        self.assertAlmostEqual(cl["success_rate"], 1 / 3)
        self.assertAlmostEqual(cl["timeout_rate"], 1 / 3)
        self.assertEqual(cl["status_buckets"], {"200": 1, "403": 1})
        self.assertEqual(cl["error_buckets"], {"timeout": 1})
        self.assertEqual(cl["top_error_class"], "timeout")

    def test_insufficient_data_flag(self):
        agg = {
            "type": "trojan",
            "users": {"c1"},
            "samples": 2,
            "per_target": {
                "transport": {
                    "attempts": 2, "ok": 2, "latencies": [100, 110],
                    "status_buckets": {}, "error_buckets": {},
                },
            },
        }
        node = T._shape_node("B", agg, region=None, min_samples=3)
        self.assertTrue(node["insufficient_data"])
        self.assertEqual(node["state"], "suspect")

    def test_rollup_sums_per_target(self):
        node_a = {"per_target": {
            "transport": {"attempts": 3, "ok": 3},
            "claude": {"attempts": 2, "ok": 1},
        }}
        node_b = {"per_target": {
            "transport": {"attempts": 5, "ok": 4},
            "claude": {"attempts": 3, "ok": 0},
        }}
        rollup = T._node_rollup([node_a, node_b])
        self.assertEqual(rollup["total_nodes"], 2)
        self.assertEqual(
            rollup["by_target_overall"]["transport"],
            {"attempts": 8, "ok": 7, "success_rate": 7 / 8},
        )
        self.assertEqual(
            rollup["by_target_overall"]["claude"],
            {"attempts": 5, "ok": 1, "success_rate": 1 / 5},
        )
        self.assertEqual(rollup["by_path_class"], {})
        self.assertEqual(rollup["by_client_asn"], {})


class PercentileTest(unittest.TestCase):
    def test_empty_returns_none(self):
        self.assertIsNone(T._percentile([], 0.5))

    def test_single_value(self):
        self.assertEqual(T._percentile([42], 0.5), 42)
        self.assertEqual(T._percentile([42], 0.99), 42)

    def test_p50_on_odd_count(self):
        self.assertEqual(T._percentile([1, 2, 3, 4, 5], 0.5), 3)

    def test_p95_picks_near_top(self):
        # Nearest-rank: idx = round(0.95 * 99) = 94 → sorted_lats[94] = 95.
        # Same formula as scripts/sre/probe_nodes.py — kept identical so
        # the dashboard reads matching numbers regardless of source.
        self.assertEqual(T._percentile(list(range(1, 101)), 0.95), 95)

    def test_p99_picks_top(self):
        self.assertEqual(T._percentile(list(range(1, 101)), 0.99), 99)


if __name__ == "__main__":
    unittest.main()
