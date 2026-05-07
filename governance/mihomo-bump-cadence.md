# mihomo 月度跟版 cadence — D-② P4-3

最后更新：2026-05-07
适用：yuelink fork on `MetaCubeX/mihomo` Meta 分支 + 三个 yuelink 自有 commit

---

## 0. 一句话

每月**第一个周一**手动 rebase yuelink 的 mihomo fork 到 upstream Meta HEAD，跑两个 smoke，必要时 force-push fork main + 在 yuelink 主仓提交新 submodule SHA。**Alpha 永远不进主线**。

---

## 1. 为什么要 cadence

* 上游 `MetaCubeX/mihomo` Meta 分支每周都有 commit；不跟版会越漂越远，rebase 时冲突变难。
* yuelink 自带的三个 commit 是 host-stability 修复（buildAndroidRules 非致命 / MMDB 非致命 / Shutdown 清理 listeners），**不会消失** —— 如果哪天上游同主题的修复合并进 Meta，我们才删除对应 commit。
* release b.P2-3 sniffer benchmark 需要可复现的 mihomo 基线 SHA；没有 cadence，每次 benchmark 都对着不同的 mihomo 跑，结果不可比。

---

## 2. 操作流程（每月一次，手动）

```bash
# 0. 确认在 yuelink 主仓干净状态
cd ~/Downloads/yuelink
git status                      # 应为 clean
git pull origin master          # 同步 master
git submodule update --init --recursive

# 1. 进 mihomo submodule
cd core/mihomo
git fetch upstream              # upstream = MetaCubeX/mihomo
git log --oneline -1 upstream/Meta   # 记录新 SHA（写进本月 cadence note）
git log --oneline main..upstream/Meta | wc -l   # 看上游领先多少 commit

# 2. rebase（三个 yuelink commit 自动 replay）
git checkout main
git rebase upstream/Meta main
# 若有冲突：手动解，resolve → git rebase --continue
# 关键 invariant：rebase 后必须仍然恰好有 3 个 yuelink-自有 commit 在 HEAD

# 3. smoke 1：Go 编译
go build ./...
# 失败 → abort: git rebase --abort（保留旧 main）→ 写故障 note 到 governance

# 4. smoke 2：yuelink 测试套
cd ../..
flutter test                    # 应全过（dns_transformer / tun_transformer 等是单测，不依赖 mihomo SHA）
flutter analyze --no-fatal-infos --no-fatal-warnings

# 5. 推 fork main（rebase 必须 force）
cd core/mihomo
git push origin main --force-with-lease
cd ../..

# 6. 在 yuelink 主仓记录新 SHA
git add core/mihomo
git commit -m "build(core): bump mihomo submodule to upstream Meta YYYY-MM-DD

Upstream Meta SHA: <abbrev>
Yuelink-local commits: 3 (replayed clean / had conflicts <list>)

Smoke:
- go build ./... : ok
- flutter test   : ok
- flutter analyze: ok"

# 7. 写 cadence note
mkdir -p governance/mihomo-cadence
cat > governance/mihomo-cadence/$(date -u +%Y-%m).md << 'EOF'
（用第 4 节模板）
EOF

# 8. 不立即推到 release tag。下次 release 走正常流程。
git push origin master
```

---

## 3. release b.P2-3 sniffer benchmark 的 cadence 关联

P2-3 是「重测 sniffer parse-pure-ip + force-dns-mapping 是否仍然 30% 性能回归」。**测试结果的 mihomo 基线 SHA 是 cadence 输出**：

```
benchmark filename:
governance/sniffer-pure-ip-benchmark-<YYYY-MM-DD>-<mihomo-abbrev-sha>.md
```

* benchmark 必须在 cadence rebase **完成之后**跑，否则结果对应「上次 cadence 之后的旧 mihomo」，没意义。
* benchmark 决策（启用 / 维持 false）连同 mihomo SHA 一起记录，下次 cadence 后如果决策不同，能定位到哪些 mihomo 提交改了 sniffer 热路径。

---

## 4. 月度 cadence note 模板

每次 cadence 跑完都在 `governance/mihomo-cadence/<YYYY-MM>.md` 写一份，永久存档：

```markdown
# mihomo cadence YYYY-MM

执行人：<name>
执行日期：YYYY-MM-DD
yuelink master commit before：<sha>
yuelink master commit after：<sha>

## upstream Meta

- 旧 SHA：<abbrev>
- 新 SHA：<abbrev>
- 上游领先 commit 数：N
- 涉及面（看 commit 标题）：<DNS / TUN / sniffer / proto / build / etc.>

## yuelink-local commits replay

| commit | replay 结果 |
|--------|------------|
| non-fatal buildAndroidRules     | clean / conflict (resolved by …) |
| non-fatal MMDB load + iptables  | clean / conflict (resolved by …) |
| cleanup listeners on Shutdown   | clean / conflict (resolved by …) |

## smoke

- `go build ./...`：ok / failure (<日志路径>)
- `flutter test`：1012/1012 / failure (<日志路径>)
- `flutter analyze`：clean / N issues

## 决策

- [ ] 推 fork main（force-with-lease）
- [ ] yuelink master 提交新 submodule SHA
- [ ] 触发 release b.P2-3 sniffer benchmark（如本月排了）
- [ ] 异常 → 回滚（abort rebase，保留旧 main，下个月再跟）

## 异常 / 注释

<空 / 写故障原因 / 写 yuelink-local 某 commit 是否可以删除（上游已合并同主题修复）>
```

---

## 5. 锁定的 invariant

* **Alpha 不进主线**：memory `feedback_no_mihomo_alpha` 已锁。OpenClash 跑 alpha 不是参考。如果上游切到 alpha-only 维护，cadence 暂停，governance 重新评估通道选择。
* **三个 yuelink-自有 commit 不主动删除**：只在确认上游同主题修复合并后才删。删之前必须在 cadence note 里说明（"<commit X> 删除原因：upstream <SHA> 合并了 <PR>"）。
* **rebase 失败不强行**：smoke 不通过就 abort；下个月再来。yuelink master 暂停在旧 SHA。
* **never automatic**：CLAUDE.md 已明文。本 cadence 只是月度提醒 + checklist，不是 cron job。

---

## 6. 与其他 release 的关系

| Release | 与 cadence 关系 |
|---------|----------------|
| **a**（DNS 治理，已发）| 不依赖 mihomo SHA — DNS transformer 是 Dart 端 |
| **b**（TUN / 系统代理）| `b.P2-3` sniffer benchmark **强依赖** cadence 输出的基线 SHA |
| **c**（移动端 LAN）| `c.P3-2` iOS excludedRoutes 不依赖 mihomo；`c.P3-1` Android Private DNS 不依赖 |
| **D**（诊断 / 文档 / UX）| `D-③ P4-1` 一键诊断报告中"核心版本"板块直接 dump 当前 mihomo SHA |

---

## 7. 查看当前线上 mihomo SHA

```bash
# yuelink 主仓里的 submodule 指针
git submodule status core/mihomo
# 或：
cd core/mihomo && git rev-parse --short HEAD
```

released 的 yuelink 版本对应的 mihomo SHA 通过 git 历史查：

```bash
git log --all --pretty="%h %s" core/mihomo | head -20
```
