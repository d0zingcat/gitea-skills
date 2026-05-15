---
name: gitea-timetracking
version: 1.0.0
description: "Gitea 工时跟踪：issue 秒表（开始/停止/取消）、手动追加和删除工时记录、按 issue/仓库/当前用户列工时。涵盖 /repos/{owner}/{repo}/issues/{n}/stopwatch 与 /times endpoint。当用户需要在 Gitea 上对 issue 计时、统计某仓库工时、查看自己的工时记录时使用。"
---

# Gitea Time Tracking

**开始前必读 [`../gitea-shared/SKILL.md`](../gitea-shared/SKILL.md)**：认证、curl 模板、错误处理。

下面 curl 都省略 `-H "Authorization: token ${GITEA_ACCESS_TOKEN}" -H "Accept: application/json"`。

## 关键概念

- **Stopwatch**：每个用户在每个 issue 上**最多一个**正在运行的秒表。停止后会自动写入一条工时记录。
- **Time entry**：单条工时记录，包含 user、time（秒）、created。
- 仓库需要在设置里启用 **Time Tracker** 才能用。

## Stopwatch（秒表）

### 启动

```bash
curl -fsSL -X POST \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/stopwatch/start"
```

如果该用户已有运行中的秒表，会 409。先 `/user/stopwatches` 看再决定。

### 停止（自动写入工时）

```bash
curl -fsSL -X POST \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/stopwatch/stop"
```

### 取消（不写工时）

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/stopwatch/delete"
```

### 当前用户活跃秒表

```bash
curl -fsSL "${GITEA_HOST}/api/v1/user/stopwatches" \
  | jq '[.[] | {issue: .issue.number, repo: .issue.repo.full_name, seconds, created}]'
```

## Time Entry（工时记录）

`TrackedTime` 字段（来自 swagger）：`id`、`time`（秒）、`user_id`（**deprecated**）、`user_name`、`issue_id`、`issue`、`created`。jq 显示用 `user_name`。

### 列出 issue 工时

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/times?page=1&limit=50" \
  | jq '[.[] | {id, user: .user_name, time, created}]'
```

可选 query：`user`（按 username 过滤，仅 issue manager 可见）、`since`、`before`、`page`、`limit`。

### 列出仓库工时

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/times?page=1&limit=50" \
  | jq '[.[] | {user: .user_name, issue: .issue_id, time, created}]'
```

可选 query：`user`、`since`、`before`、`page`、`limit`。

### 列出当前用户全部工时

```bash
curl -fsSL "${GITEA_HOST}/api/v1/user/times?page=1&limit=50" \
  | jq '[.[] | {issue: .issue_id, time, created}]'
```

### 手动追加工时

`AddTimeOption` body：

| 字段 | 必填 | 说明 |
|------|------|------|
| `time` | 是 | 秒数 |
| `created` | 否 | ISO 8601，覆盖记录时间戳（默认 now） |
| `user_name` | 否 | 仅 issue manager 可代他人记录工时 |

```bash
# 加 30 分钟
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"time": 1800}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/times"

# 给昨天补一笔
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"time": 3600, "created": "2026-05-14T15:00:00Z"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/times"
```

### 删除单条工时

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/times/${TIME_ID}"
```

## 常见组合

### 给 issue 加 1 小时工时并查看汇总

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"time": 3600}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/times"

# 看 issue 总时长
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/times" \
  | jq 'map(.time) | add / 3600 | "\(.) hours"'
```

### 统计本月每人在某仓库的工时

```bash
SINCE="$(date -u +%Y-%m-01T00:00:00Z)"
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/times?since=${SINCE}&limit=100" \
  | jq 'group_by(.user_name) | map({user: .[0].user_name, total_hours: (map(.time) | add / 3600)})'
```

## 权限提示

| 操作 | scope |
|------|-------|
| 读 issue/仓库工时 | `read:repository`（且仓库启用 Time Tracker） |
| 写自己的工时 | `read:repository`（且为协作者） |
| 删除他人工时 | 仓库 admin |
