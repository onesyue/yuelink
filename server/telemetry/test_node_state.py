"""Tests for the P7 node state machine.

Pure-Python — verifies the classifier without touching the DB. The
DB-bound endpoints (recompute / list / review) are left to integration
tests once Postgres is available in CI.

Run:
    python3 -m pytest server/telemetry/test_node_state.py -v
"""
from __future__ import annotations

import os
import sys
import unittest

# Same import shim as test_stats_nodes_aggregation.py — stub psycopg2 so
# importing telemetry.py doesn't try to open a pool.
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

os.environ.setdefault("TELEMETRY_DATABASE_DSN", "host=stub")

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
    fa.status = type("S", (), {
        "HTTP_503_SERVICE_UNAVAILABLE": 503,
        "HTTP_401_UNAUTHORIZED": 401,
        "HTTP_429_TOO_MANY_REQUESTS": 429,
    })
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


def _target(attempts, ok, *, status_buckets=None, error_buckets=None,
            success_rate=None, timeout_rate=None):
    """Shape a single per_target record like _shape_node would."""
    return {
        "attempts": attempts,
        "ok": ok,
        "success_rate": success_rate
            if success_rate is not None
            else ((ok / attempts) if attempts else None),
        "timeout_rate": timeout_rate,
        "p50_ms": None, "p95_ms": None, "p99_ms": None,
        "top_error_class": None,
        "status_buckets": status_buckets,
        "error_buckets": error_buckets,
    }


class ClassifierStateTransitionsTest(unittest.TestCase):
    """The state machine MUST satisfy these invariants — these are the
    guard rails that prevent a future code change from quarantining
    nodes automatically or treating AI 403 as a node failure."""

    # Healthy ──────────────────────────────────────────────────────────────
    def test_healthy_when_transport_high_no_ai_failures(self):
        rum = {"transport": _target(10, 9, success_rate=0.9)}
        state, reason, _ = T._classify_node_state(rum, None, "vless", None)
        self.assertEqual(state, "healthy")

    def test_recovered_label_when_previous_was_suspect(self):
        rum = {"transport": _target(10, 9, success_rate=0.9)}
        state, _, _ = T._classify_node_state(rum, None, "vless", "suspect")
        self.assertEqual(state, "recovered")

    # Suspect ──────────────────────────────────────────────────────────────
    def test_suspect_when_transport_below_50pct(self):
        rum = {"transport": _target(10, 3, success_rate=0.3)}
        state, _, _ = T._classify_node_state(rum, None, "vless", None)
        self.assertEqual(state, "suspect")

    def test_insufficient_data_holds_previous_state(self):
        rum = {"transport": _target(1, 1, success_rate=1.0)}
        state, reason, _ = T._classify_node_state(rum, None, "vless", "healthy")
        self.assertEqual(state, "healthy")
        self.assertIn("insufficient", reason.lower())

    def test_no_previous_state_defaults_suspect(self):
        rum = {"transport": _target(1, 1, success_rate=1.0)}
        state, _, _ = T._classify_node_state(rum, None, "vless", None)
        self.assertEqual(state, "suspect")

    # AI-blocked ──────────────────────────────────────────────────────────
    def test_ai_403_does_not_quarantine_node(self):
        rum = {
            "transport": _target(10, 9, success_rate=0.9),
            "claude": _target(5, 0, status_buckets={"403": 5},
                              error_buckets={"ai_blocked": 5}),
        }
        state, _, _ = T._classify_node_state(rum, None, "vless", None)
        self.assertEqual(state, "ai_blocked")

    def test_ai_1020_classed_as_ai_blocked(self):
        rum = {"transport": _target(10, 9, success_rate=0.9),
               "chatgpt": _target(3, 0, status_buckets={"1020": 3})}
        state, _, _ = T._classify_node_state(rum, None, "vless", None)
        self.assertEqual(state, "ai_blocked")

    def test_ai_timeout_classed_as_ai_suspect(self):
        rum = {"transport": _target(10, 9, success_rate=0.9),
               "claude": _target(3, 0, error_buckets={"timeout": 3})}
        state, _, _ = T._classify_node_state(rum, None, "vless", None)
        self.assertEqual(state, "ai_suspect")

    # Reality auth ────────────────────────────────────────────────────────
    def test_reality_auth_repeated_yields_quarantine_candidate(self):
        rum = {"transport": _target(5, 0,
                                    error_buckets={"reality_auth_failed": 5})}
        state, reason, _ = T._classify_node_state(rum, None, "vless", None)
        self.assertEqual(state, "quarantine_candidate")
        self.assertIn("Reality", reason)

    def test_reality_auth_only_for_vless(self):
        rum = {"transport": _target(5, 0,
                                    error_buckets={"reality_auth_failed": 5})}
        state, _, _ = T._classify_node_state(rum, None, "trojan", None)
        self.assertNotEqual(state, "quarantine_candidate")

    def test_single_reality_failure_does_not_trigger_candidate(self):
        rum = {"transport": _target(5, 4,
                                    error_buckets={"reality_auth_failed": 1})}
        state, _, _ = T._classify_node_state(rum, None, "vless", None)
        self.assertNotEqual(state, "quarantine_candidate")

    # Cross-source agreement ─────────────────────────────────────────────
    def test_rum_bad_but_probe_ok_does_not_escalate_to_candidate(self):
        rum = {"transport": _target(10, 0, success_rate=0.0)}
        probe = {"transport": _target(10, 9, success_rate=0.9)}
        state, _, _ = T._classify_node_state(rum, probe, "vless", None)
        self.assertNotEqual(state, "quarantine_candidate")
        self.assertEqual(state, "suspect")

    def test_rum_and_probe_both_fail_produce_candidate(self):
        rum = {"transport": _target(10, 1, success_rate=0.1)}
        probe = {"transport": _target(10, 1, success_rate=0.1)}
        state, _, _ = T._classify_node_state(rum, probe, "trojan", None)
        self.assertEqual(state, "quarantine_candidate")


class EvaluateNodeStateTest(unittest.TestCase):
    """`_evaluate_node_state` is the wrapper persisted into node_state.
    requires_human MUST be true for both candidate and quarantined,
    false otherwise."""

    def test_quarantine_candidate_requires_human(self):
        rum = {"transport": _target(10, 0,
                                    error_buckets={"reality_auth_failed": 10})}
        out = T._evaluate_node_state(rum, None, "vless", None)
        self.assertEqual(out["state"], "quarantine_candidate")
        self.assertTrue(out["requires_human"])

    def test_ai_blocked_does_not_require_human(self):
        rum = {"transport": _target(10, 9, success_rate=0.9),
               "claude": _target(3, 0, status_buckets={"403": 3})}
        out = T._evaluate_node_state(rum, None, "vless", None)
        self.assertFalse(out["requires_human"])

    def test_evidence_dict_carries_target_breakdown(self):
        rum = {"transport": _target(10, 9, success_rate=0.9)}
        out = T._evaluate_node_state(rum, None, "vless", None)
        self.assertIn("rum", out["evidence"])
        self.assertIn("transport", out["evidence"]["rum"])
        # Ensure no raw secrets leaked into evidence (we only carry
        # numeric/string aggregates, never client_id / props).
        self.assertNotIn("server", str(out["evidence"]))
        self.assertNotIn("password", str(out["evidence"]))

    def test_confidence_grows_with_attempt_count(self):
        rum_small = {"transport": _target(3, 3, success_rate=1.0)}
        rum_large = {"transport": _target(50, 50, success_rate=1.0)}
        c_small = T._evaluate_node_state(rum_small, None, "vless", None)["confidence"]
        c_large = T._evaluate_node_state(rum_large, None, "vless", None)["confidence"]
        self.assertGreater(c_large, c_small)
        self.assertLessEqual(c_large, 1.0)

    def test_state_machine_never_returns_quarantined(self):
        """Critical guard rail. Nothing the classifier sees should
        produce `quarantined` — only POST .../review can."""
        cases = [
            {"transport": _target(10, 0, success_rate=0.0)},
            {"transport": _target(10, 0,
                                  error_buckets={"reality_auth_failed": 10})},
            {"transport": _target(10, 9, success_rate=0.9),
             "claude": _target(3, 0, status_buckets={"403": 3})},
        ]
        for rum in cases:
            out = T._evaluate_node_state(rum, None, "vless", None)
            self.assertNotEqual(out["state"], "quarantined")


class ProbeValidationTest(unittest.TestCase):
    """Validation of incoming probe results — release-gate sends a
    synthetic batch to assert these checks fire."""

    def test_valid_minimal_result(self):
        ok, _ = T._validate_probe_result({
            "node_fp": "abc", "target": "transport", "status": "ok",
        })
        self.assertTrue(ok)

    def test_unknown_target_rejected(self):
        ok, why = T._validate_probe_result({
            "node_fp": "abc", "target": "yahoo", "status": "ok",
        })
        self.assertFalse(ok)
        self.assertIn("target", why)

    def test_unknown_status_rejected(self):
        ok, why = T._validate_probe_result({
            "node_fp": "abc", "target": "claude", "status": "weird",
        })
        self.assertFalse(ok)
        self.assertIn("status", why)

    def test_missing_node_fp_rejected(self):
        ok, _ = T._validate_probe_result({
            "target": "transport", "status": "ok",
        })
        self.assertFalse(ok)

    def test_oversized_node_fp_rejected(self):
        ok, _ = T._validate_probe_result({
            "node_fp": "x" * 200,
            "target": "transport", "status": "ok",
        })
        self.assertFalse(ok)

    def test_targets_match_PROBE_TARGETS(self):
        for tgt in T.PROBE_TARGETS:
            ok, _ = T._validate_probe_result({
                "node_fp": "abc", "target": tgt, "status": "ok",
            })
            self.assertTrue(ok, msg=f"target {tgt!r} should be allowed")


class StateConstantsTest(unittest.TestCase):
    """The constants are public-ish — break with care. Locking them in
    so a typo can't accidentally remove `quarantined` from the human
    set and let automation skip the gate."""

    def test_human_set_contains_only_quarantined(self):
        self.assertEqual(T.NODE_STATES_HUMAN, {"quarantined"})

    def test_all_states_includes_recovered(self):
        self.assertIn("recovered", T.ALL_NODE_STATES)
        self.assertIn("ai_suspect", T.ALL_NODE_STATES)


if __name__ == "__main__":
    unittest.main()
