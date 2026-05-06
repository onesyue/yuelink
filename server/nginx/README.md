# nginx config — YueLink edge

Single nginx instance on `66.55.76.208` running in a docker container
(`nginx:1.27-alpine`). Routes traffic for several yue.to-family
domains to the right upstream (XBoard, checkin-api, sso, etc.).

The nginx host directory layout:

```
/home/nginx/conf.d/      → /etc/nginx/conf.d/      (bind-mounted)
/home/nginx/conf/        → /etc/nginx/             (main nginx.conf bind-mount)
/home/nginx/certs/       → /etc/nginx/certs/       (Let's Encrypt material)
/home/nginx/html/        → /usr/share/nginx/html/  (web root, favicon.ico lives here)
/home/nginx/logs/        → /var/log/nginx/         (access + error log)
```

All five paths are bind-mounts: container image upgrades do **not**
wipe these. The container can be `docker rm -f` and re-created
without losing config.

## File inventory

| Path in repo | Path on host | Purpose |
|---|---|---|
| `server/nginx/default.conf` | `/home/nginx/conf.d/default.conf` | Main config: yue.to, my.yue.to (XBoard panel), sso.yuetoto.com, IP-literal hosts. Owns the `/api/client/*` proxy to `127.0.0.1:8011` (checkin-api), the `/favicon.ico` route, the `is_not_cf` 444 origin guard, and the "block_bot" UA blocking. |
| `server/nginx/i-yue-to.conf` | `/home/nginx/conf.d/i-yue-to.conf` | i.yue.to invite-alias short-link routing. |
| `server/nginx/node-api.conf` | `/home/nginx/conf.d/node-api.conf` | XBoard node-api endpoint (relays / sing-box config push). |
| `server/nginx/favicon.ico` | `/home/nginx/html/favicon.ico` | Multi-resolution ICO (16/32/48/64/128 px) generated 2026-05-06 from `assets/icon_desktop.png` via Pillow. **Replaces the old `empty_gif` directive** that used to make the tab icon look empty. |
| `server/nginx/icon.png` | `/home/nginx/html/icon.png` | Source PNG (kept around in case the favicon ever needs to be regenerated). |

## Deploy / restore on a fresh host

```bash
# On 66.55.76.208 (or replacement host)

# 1. Run the nginx container (assumes docker is already up)
docker run -d --name nginx --restart=always \
    -p 80:80 -p 443:443 \
    -v /home/nginx/conf.d:/etc/nginx/conf.d \
    -v /home/nginx/conf/nginx.conf:/etc/nginx/nginx.conf \
    -v /home/nginx/certs:/etc/nginx/certs \
    -v /home/nginx/html:/usr/share/nginx/html \
    -v /home/nginx/logs:/var/log/nginx \
    nginx:1.27-alpine

# 2. Copy the union of repo files (assuming yuelink-repo on the host)
sudo mkdir -p /home/nginx/conf.d /home/nginx/html
sudo cp yuelink-repo/server/nginx/*.conf /home/nginx/conf.d/
sudo cp yuelink-repo/server/nginx/favicon.ico /home/nginx/html/
sudo cp yuelink-repo/server/nginx/icon.png    /home/nginx/html/
sudo cp yuelink-repo/server/nginx/nginx.conf  /home/nginx/conf/nginx.conf  # if you keep one in repo

# 3. Reload
docker exec nginx nginx -t   # syntax check
docker exec nginx nginx -s reload
```

## Cloudflare front

`yue.to` and `my.yue.to` are behind Cloudflare. The origin
`server { ... if ($is_not_cf) { return 444; } ... }` rejects any
non-CF source so direct-to-origin scanning gets a connection close.

After changing any config that affects a cached path (favicon,
robots.txt, static asset), purge that path's CF edge cache. The
yue.to zone ID is `4fe43e0a247729e98a1f2ff139429886`. Credentials
live in the yueops Postgres `settings` table:

```sql
SELECT key, value FROM settings WHERE key IN ('cf_dns_email','cf_dns_api_key','cf_dns_zone_id');
```

(Yes, those are the same credentials the dns-scheduler uses for
DNSPod-style record edits — Cloudflare Global API Key is multi-zone
and can purge across zones.)

Quick purge:

```bash
curl -X POST "https://api.cloudflare.com/client/v4/zones/<zone>/purge_cache" \
  -H "X-Auth-Email: <email>" \
  -H "X-Auth-Key: <key>" \
  -H "Content-Type: application/json" \
  --data '{"files":["https://my.yue.to/favicon.ico"]}'
```

## Marker / idempotency

The favicon location used to ship with `empty_gif` (1×1 transparent
gif anti-fingerprint). 2026-05-06 it switched to:

```nginx
location = /favicon.ico {
    log_not_found off;
    access_log off;
    alias /usr/share/nginx/html/favicon.ico;
    expires 30d;
}
```

If you ever see the old `empty_gif;` come back (template reset,
manual edit), the tab logo will silently disappear again — replace
with the alias form above.
