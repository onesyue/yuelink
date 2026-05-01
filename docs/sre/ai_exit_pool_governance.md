# AI Exit Pool Governance

AI availability is a separate dimension from node transport health.

## Classification

- Normal sites OK + Claude/ChatGPT 403, 1020 or 429: `ai_blocked`.
- Normal sites OK + Claude/ChatGPT timeout or TLS EOF: `ai_suspect`.
- Normal sites fail too: `node_down`, `transport_failed` or protocol-specific error such as `reality_auth_failed`.
- Reality authentication failures never count as AI blocking.

Normal sites:

- transport (`gstatic generate_204`)
- Google
- GitHub
- YouTube
- Netflix

AI sites:

- Claude
- ChatGPT

## Pool Rules

- `ai_blocked`: exclude from AI default group immediately; keep in normal group if normal targets pass.
- `ai_suspect`: degrade AI weight by 80% for 30 minutes; promote to `ai_blocked` if 403/1020/429 appears.
- `node_down`: remove from all automatic groups only through P7 candidate flow.
- Nodes must pass both Claude and ChatGPT for 24h before returning to AI default.

## Dashboard

Show per node over last 24h:

- Claude success rate
- ChatGPT success rate
- `403 / 1020 / 429 / timeout / tls_eof` buckets
- exit_country
- exit_isp
- node_fp
- AI state
- normal-site state

## Release Wording

Allowed:

- "改善 AI 访问失败归因"
- "AI 出口池治理中，受限出口会被识别并降权"

Forbidden:

- "AI 已全面可用"
- "所有 Claude / ChatGPT 问题已解决"

