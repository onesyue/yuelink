# XBoard subscription rule templates + container patches

These files generate every subscription handed out to clients
(yuelink, third-party clash, sing-box, Surge, Surfboard, …).

The hosts they live on:

```
66.55.76.208:/home/xboard/yue-to/rules/      ←  bind-mounted into yue-to-web-1:/www/resources/rules
66.55.76.208:/home/xboard/yue-to/patch-*     ←  hand-replay scripts, run after each XBoard upgrade
```

## File inventory

| Repo | Server | What it generates |
|---|---|---|
| `app.clash.yaml` | `/home/xboard/yue-to/rules/app.clash.yaml` | yuelink-client subscription template (Clash Meta / mihomo dialect with `xb_server_id` injection) |
| `default.clash.yaml` | `/home/xboard/yue-to/rules/default.clash.yaml` | third-party Clash / Stash / clash-verge fallback template |
| `default.sing-box.json` | `/home/xboard/yue-to/rules/default.sing-box.json` | sing-box client subscription |
| `default.surge.conf` | `/home/xboard/yue-to/rules/default.surge.conf` | Surge client |
| `default.surfboard.conf` | `/home/xboard/yue-to/rules/default.surfboard.conf` | Surfboard client |
| `patch-loon-upload-bandwidth.sh` | `/home/xboard/yue-to/patch-loon-upload-bandwidth.sh` | Replay script — re-applies `upload-bandwidth` patch to `Loon.php` after a container pull |
| `patch-loon-upload-bandwidth.php` | `/home/xboard/yue-to/patch-loon-upload-bandwidth.php` | The php-side patcher invoked by the .sh wrapper (idempotent — `already patched` short-circuits) |

## Why the YAML is here

The two `*.clash.yaml` files are bind-mounted, so a container image
pull doesn't lose them. But three other failure modes will:

1. Fresh host install — host directory is empty.
2. Manual edit gone wrong — restore-from-source.
3. Synced from a stale backup — diff against this version.

After **2026-05-06** the templates contain three production fixes
that you do not want to lose:

1. `sniffer.skip-domain` includes `cloudflare-ech.com` so the ECH
   outer-SNI doesn't override fake-ip routing.
2. `rules:` is prepended with five DOMAIN-SUFFIX → AI rules
   (`cloudflare-dns.com`, `chrome.cloudflare-dns.com`,
   `mozilla.cloudflare-dns.com`, `dns.google`, `cloudflare-ech.com`)
   so browser Secure DNS / ECH probes share the AI exit with
   chatgpt.com / claude.ai etc.
3. `parse-pure-ip: true` + `force-dns-mapping: true` are stripped —
   they cost ~30% throughput on Stash / clash-verge / clash-party
   third-party clients (yuelink already strips them client-side
   since v1.0.21 P1-4, but third-party clients don't run our
   ConfigTemplate).

## Loon `upload-bandwidth` replay

`yue-to-web-1:/www/app/Protocols/Loon.php` is **not** bind-mounted.
After every `docker compose pull && up -d` for XBoard, the
`upload-bandwidth` injection (line 356) gets reset. Replay:

```bash
ssh root@66.55.76.208
bash /home/xboard/yue-to/patch-loon-upload-bandwidth.sh
```

`patch-loon-upload-bandwidth.php` does an `already patched` check at
the top, so the wrapper is idempotent — running it twice is fine.

## Updating templates from repo to host

The host versions are the "live" copy used to generate subscriptions.
Whenever you commit a change to `app.clash.yaml` or `default.clash.yaml`
in this repo, scp it back:

```bash
sshpass -e scp server/xboard-rules/app.clash.yaml \
    root@66.55.76.208:/home/xboard/yue-to/rules/app.clash.yaml
sshpass -e scp server/xboard-rules/default.clash.yaml \
    root@66.55.76.208:/home/xboard/yue-to/rules/default.clash.yaml
sshpass -e ssh root@66.55.76.208 \
    "docker exec yue-to-web-1 php /www/artisan cache:clear"
```

XBoard reads the YAML on every subscription request (no compile step),
so a fresh subscription includes the change immediately. Existing
clients catch up at their next subscription refresh interval.

## Updating templates from host to repo

If you edit the host file directly during an incident, scp it back
to the repo and commit:

```bash
sshpass -e scp \
    root@66.55.76.208:/home/xboard/yue-to/rules/app.clash.yaml \
    server/xboard-rules/app.clash.yaml
git add server/xboard-rules/app.clash.yaml
git commit -m "ops: app.clash.yaml — <reason>"
```

The host always wins as source of truth because it's what clients
actually receive — but this repo is the audit log so changes are
not invisible to git history.
