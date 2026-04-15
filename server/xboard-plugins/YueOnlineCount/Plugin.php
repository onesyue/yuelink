<?php

namespace Plugin\YueOnlineCount;

use App\Models\User;
use App\Services\Plugin\AbstractPlugin;

/**
 * Inject online_count and last_online_at into the user.subscribe.response
 * payload. XBoard's UserController@getSubscribe explicitly select()s a
 * fixed column list that omits these fields, so the YueLink mobile/desktop
 * client can never see the per-user online device count without this hook.
 */
class Plugin extends AbstractPlugin
{
    public function boot(): void
    {
        $this->filter('user.subscribe.response', function ($user) {
            $id = request()->user()?->id;
            if (!$id) {
                return $user;
            }
            $row = User::query()
                ->whereKey($id)
                ->select(['online_count', 'last_online_at'])
                ->first();
            if ($row) {
                $user['online_count'] = (int) ($row->online_count ?? 0);
                if ($row->last_online_at) {
                    $user['last_online_at'] = $row->last_online_at;
                }
            }
            return $user;
        });
    }
}
