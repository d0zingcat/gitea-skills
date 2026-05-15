---
name: gitea-notification
version: 0.0.1
description: "Gitea 通知：列出未读/已读通知（用户级或仓库级）、获取单个 thread 详情、标记已读、批量标记。涵盖 /notifications 与 /repos/{owner}/{repo}/notifications endpoint。当用户需要查 Gitea 收件箱、批量清掉未读、看某条通知详情时使用。"
---

# Gitea Notification

**开始前必读 [`../gitea-shared/SKILL.md`](../gitea-shared/SKILL.md)**：认证、curl 模板、错误处理。

下面 curl 都省略 `-H "Authorization: token ${GITEA_ACCESS_TOKEN}" -H "Accept: application/json"`。

## 关键概念

- 通知是**当前用户**视角的（认证 token 决定主体）。
- 一个 **thread** 对应一个 issue / PR / commit / repo 的更新链，不是单条评论。
- 状态：`unread` / `read` / `pinned`。

## 列出

### 全部（当前用户）

```bash
curl -fsSL "${GITEA_HOST}/api/v1/notifications?status-types=unread&page=1&limit=50" \
  | jq '[.[] | {id, subject: .subject.title, type: .subject.type, state: .subject.state, repo: .repository.full_name, updated_at}]'
```

### 仓库范围

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/notifications?status-types=unread"
```

### 可选过滤

| 参数 | 含义 |
|------|------|
| `status-types` | 重复传，`unread` / `read` / `pinned`（如 `?status-types=unread&status-types=pinned`） |
| `subject-type` | `issue` / `pull` / `commit` / `repository`（**全小写**；响应里 `.subject.type` 反而是 TitleCase 如 `Issue`） |
| `since` | ISO 8601，更新时间晚于此 |
| `before` | ISO 8601，更新时间早于此 |
| `all` | `true` 时**额外包含已读**通知（默认只返回未读+pinned） |
| `page` / `limit` | 分页 |

## 单个 thread

```bash
curl -fsSL "${GITEA_HOST}/api/v1/notifications/threads/${ID}"
```

## 标记已读

### 单个 thread

```bash
curl -fsSL -X PATCH \
  "${GITEA_HOST}/api/v1/notifications/threads/${ID}"
```

可加 `?to-status=read|pinned|unread` 切换状态。

### 批量（用户级）

```bash
curl -fsSL -X PUT \
  "${GITEA_HOST}/api/v1/notifications?last_read_at=$(date -u +%FT%TZ)"
```

`last_read_at` 不传则用当前时间。早于该时间的通知都标已读。

可加额外 query 限定要标记的范围：
- `?to-status=read`（默认）/ `pinned` / `unread`
- `?status-types=unread`（重复传）限定只标某状态
- `?all=true` 包含已读

```bash
# 只把 PR 类未读标已读
curl -fsSL -X PUT \
  "${GITEA_HOST}/api/v1/notifications?status-types=unread&subject-type=pull"
```

### 批量（仓库级）

```bash
curl -fsSL -X PUT \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/notifications"
```

## 常见组合

### 列出未读 PR review 通知

```bash
curl -fsSL "${GITEA_HOST}/api/v1/notifications?status-types=unread&subject-type=Pull&limit=50" \
  | jq '[.[] | {id, title: .subject.title, repo: .repository.full_name, url: .subject.html_url}]'
```

### 一键清空所有未读

```bash
curl -fsSL -X PUT "${GITEA_HOST}/api/v1/notifications"
```

**这是不可逆操作**（标已读后无法批量恢复未读）。执行前确认用户意图。

## 权限提示

`/notifications` 走当前用户 token，无需额外 scope。`/repos/{owner}/{repo}/notifications` 需要至少 `read:repository`。
