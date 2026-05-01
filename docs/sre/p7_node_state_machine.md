# P7 Node State Machine

Automation can mark evidence states. Human approval is required before real
quarantine/removal from production default groups.

| from_state | condition | to_state | action | requires_human |
|---|---|---|---|---|
| healthy | RUM timeout rate crosses threshold, active probe still healthy | suspect | observe, annotate ISP/path bucket | false |
| healthy | context deadline exceeded repeats across one region | suspect | lower score temporarily | false |
| healthy | Reality auth failure repeats in RUM and active probe | quarantine_candidate | open ops review with node_fp evidence | false |
| healthy | Google/GitHub/Youtube OK, Claude/ChatGPT 403/1020/429 | ai_blocked | remove from AI pool / keep normal pool | false |
| suspect | failures clear for 30 minutes | healthy | restore score | false |
| suspect | multi-region active probe fails same transport target | quarantine_candidate | freeze promotion, notify ops | false |
| suspect | only RUM fails, active probe healthy | suspect | classify as user path / ISP / local network | false |
| quarantine_candidate | ops confirms server/route/config fault | quarantined | remove from default group | true |
| quarantine_candidate | ops rejects evidence or node recovers | suspect | keep observation | true |
| quarantined | fix deployed and 2 regions pass 3 rounds | healthy | reintroduce gradually | true |
| ai_blocked | Claude/ChatGPT clean for 24h | healthy | rejoin AI pool with low initial weight | false |
| ai_blocked | normal targets fail too | suspect | reclassify as node health issue | false |

State fields:

- `node_fp`
- `state`
- `reason`
- `last_transition_at`
- `rum_window`
- `active_probe_window`
- `requires_human`
- `operator`
- `decision_note`

