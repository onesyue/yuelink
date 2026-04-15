# XBoard server plugins

Persistent XBoard plugins required by the YueLink client. They live in
`/home/xboard/yue-to/plugins/<Name>/` on the XBoard host (`66.55.76.208`),
mounted into the `yue-to-web-1` container at `/www/plugins/<Name>/`.

## YueOnlineCount

**Why it exists**: XBoard's `App\Http\Controllers\V1\User\UserController@getSubscribe`
uses an explicit `select([...])` that does NOT include `online_count` or
`last_online_at`. The columns exist on `v2_user` and are kept up-to-date
by `App\Services\DeviceStateService` (Redis-backed, dedup by IP, 600s TTL)
but they are never returned by the API. Without this plugin, `account_card`
in YueLink can only show "1 / N" (the local-fallback) instead of the real
multi-device count.

The plugin hooks `user.subscribe.response` (a filter, not a listener) and
re-queries the two missing columns for the authed user, then merges them
into the response.

## Install / enable

The plugin directory is bind-mounted, so just `scp -r YueOnlineCount/`
into `/home/xboard/yue-to/plugins/`. Then enable it in the DB:

```bash
docker exec yue-to-web-1 php /www/artisan tinker --execute='
  $p = \App\Models\Plugin::firstOrCreate(
    ["code"=>"yue_online_count"],
    ["name"=>"YueLink Online Count","version"=>"1.0.0","is_enabled"=>true,"config"=>"[]"]
  );
  $p->is_enabled = true; $p->save();
'
docker exec yue-to-web-1 php /www/artisan cache:clear
```

Verify with a logged-in user token:

```bash
TOKEN="Bearer ..."
curl -s "http://66.55.76.208:8001/api/v1/user/getSubscribe" \
  -H "Authorization: $TOKEN" | jq '.data | {online_count, last_online_at, device_limit}'
# Expect online_count to be a non-null integer.
```
