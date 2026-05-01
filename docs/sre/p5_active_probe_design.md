# P5 Active Probe Runner Design

Status: design-ready, not a replacement for client RUM.

## Runner

- Runs outside normal client telemetry ingest.
- At least two regions in v0: `us-west` and `asia-east`; add EU after rate and cost are known.
- Schedule: every 5 minutes with jitter per region.
- Targets: `transport`, `google`, `youtube`, `netflix`, `github`, `claude`, `chatgpt`.
- Uses the same sanitized node identity contract as `node_probe_result_v1`: `node_fp`, protocol `transport`, coarse exit metadata only.

## API

`POST /api/sre/active-probe/v1/results`

Authentication:

- Dedicated bearer token, not BasicAuth and not client telemetry.
- Dedicated rate limit bucket per region/runner token.
- Idempotency key: `region + round_id + node_fp + target`.

Payload item:

```json
{
  "round_id": "2026-05-01T12:00:00Z/us-west",
  "region": "us-west",
  "node_fp": "16hex",
  "target": "github",
  "status_code": 200,
  "error_class": "ok",
  "latency_ms": 312,
  "transport": "vless",
  "sampled_at": "2026-05-01T12:00:03Z"
}
```

## Tables

`active_probe_runs`

- `id`
- `round_id`
- `region`
- `started_at`
- `finished_at`
- `runner_version`
- `node_count`
- `target_count`
- `status`

`active_probe_results`

- `id`
- `round_id`
- `region`
- `node_fp`
- `target`
- `transport`
- `status_code`
- `error_class`
- `latency_ms`
- `sampled_at`
- unique `(round_id, region, node_fp, target)`

`active_probe_dead_letter`

- raw sanitized payload
- failure reason
- retry count
- next_retry_at

## 429 Handling

- Do not reuse `/api/client/telemetry`; blackbox batch upload already hit 429.
- Runner API has token-specific rate limit sized for `regions × nodes × targets`.
- Client-side runner uses bounded retries with exponential backoff and jitter.
- Failed batches go to dead-letter; never retry forever in-process.

## Dashboard

Show RUM and active probe side by side:

- RUM failed, active probe healthy: user path / ISP / local network suspected.
- Active probe failed, RUM healthy: region-specific probe path or low-user node.
- Both failed: node/service candidate.
- AI failed only: AI exit pool issue, not node quarantine.

