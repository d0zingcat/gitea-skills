---
name: gitea-issue
version: 1.0.0
description: "Gitea Issue 管理：创建/列出/更新 issue、添加/编辑评论、读写标签关联。涵盖 /repos/{owner}/{repo}/issues 系列 endpoint。当用户需要在 Gitea 上提 issue、看 issue 列表、加评论、改状态、给 issue 打/取消标签时使用。Issue 与 PR 共享 number 命名空间，但 PR 专用操作请用 gitea-pull skill。"
---

# Gitea Issue

**开始前必读 [`../gitea-shared/SKILL.md`](../gitea-shared/SKILL.md)**：认证、curl 模板、分页、错误处理。

下面所有 curl 都省略了 `-H "Authorization: token ${GITEA_ACCESS_TOKEN}" -H "Accept: application/json"`，请自行补齐。

## 关键概念

- **Issue number**：仓库内自增整数，与 Pull Request 共享同一序列。`#5` 既可能是 issue 也可能是 PR。
- 通过 `/issues` endpoint 可以读到 issue 也能读到 pull request 的 issue 视图（带 `pull_request` 字段），但要拿 PR 专属信息（diff、reviewers）必须走 `/pulls/{n}`。

## 列出 issue

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues?state=open&page=1&limit=50" \
  | jq '[.[] | {number, title, state, user: .user.login, labels: [.labels[].name], updated_at}]'
```

可选 query 参数：

| 参数 | 含义 |
|------|------|
| `state` | `open` / `closed` / `all`（默认 open） |
| `labels` | 逗号分隔的 label 名 |
| `type` | `issues` / `pulls`（不传两者都返回） |
| `q` | 关键字模糊匹配（标题/正文） |
| `created_by` | 按创建者 username 过滤 |
| `assigned_by` | 按 assignee 过滤 |
| `mentioned_by` | 按被提及 username 过滤 |
| `since` | ISO 8601 时间戳，更新时间晚于此 |
| `before` | ISO 8601 时间戳，更新时间早于此 |
| `milestones` | 逗号分隔的 milestone 名 |
| `page` / `limit` | 分页 |

## Issue 详情

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}"
```

精简输出：

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}" \
  | jq '{number, title, state, body, user: .user.login, labels: [.labels[].name], assignees: [.assignees[]?.login], milestone: .milestone.title}'
```

## 创建 issue

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{
    "title": "Bug: foo crashes",
    "body": "Steps to reproduce ...",
    "assignees": ["alice"],
    "labels": [3, 7],
    "milestone": 1,
    "ref": "main"
  }' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues"
```

字段说明：

| 字段 | 类型 | 说明 |
|------|------|------|
| `title` | string | 必填 |
| `body` | string | 正文（markdown） |
| `assignees` | string[] | 用户名数组 |
| `labels` | number[] | label **ID** 数组（不是 name） |
| `milestone` | number | milestone ID |
| `ref` | string | 关联分支/commit |
| `due_date` | ISO 8601 | 截止时间 |
| `closed` | bool | 创建为已关闭状态（少见） |

要先拿 label/milestone ID 见 `gitea-label` 和 `gitea-milestone` skill。

## 更新 issue

`PATCH` 只更新提供的字段。

```bash
curl -fsSL -X PATCH -H "Content-Type: application/json" \
  -d '{
    "title": "Bug: foo crashes (root cause: race)",
    "state": "closed",
    "assignees": ["alice","bob"]
  }' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}"
```

可改字段：`title`、`body`、`assignees`、`milestone`、`state`（`open`/`closed`）、`ref`、`due_date`、`unset_due_date`（true 时清除截止时间）。

## 评论

### 列出评论

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/comments" \
  | jq '[.[] | {id, user: .user.login, body, created_at}]'
```

### 添加评论

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"body":"Looking into this now."}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/comments"
```

### 编辑评论

注意 endpoint 用的是 comment ID（不是 issue number），路径在仓库下：

```bash
curl -fsSL -X PATCH -H "Content-Type: application/json" \
  -d '{"body":"Updated comment text"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/comments/${COMMENT_ID}"
```

### 删除评论

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/comments/${COMMENT_ID}"
```

## 标签关联

`labels` 是仓库或组织级 label 的 **ID 数组**。先用 `gitea-label` skill 列 label 拿 ID。

### 查看 issue 的标签

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/labels"
```

### 追加标签

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"labels":[3,7]}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/labels"
```

### 替换全部标签

```bash
curl -fsSL -X PUT -H "Content-Type: application/json" \
  -d '{"labels":[3,7]}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/labels"
```

### 删除单个标签

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/labels/${LABEL_ID}"
```

### 清空标签

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/labels"
```

## 跨仓库搜索 issue

跨仓库的全文搜索请走 `gitea-search` skill 的 `search_issues`（路径 `/repos/issues/search`）。

## Reactions（表情回应）

Issue 和 issue comment 都支持表情回应。常用 content：`+1`、`-1`、`laugh`、`hooray`、`confused`、`heart`、`rocket`、`eyes`。

### Issue reactions

```bash
# 列出
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/reactions" \
  | jq '[.[] | {user: .user.login, content, created_at}]'

# 添加（同一用户对同一 content 重复 POST 是幂等的）
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"content":"+1"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/reactions"

# 删除（自己的）
curl -fsSL -X DELETE -H "Content-Type: application/json" \
  -d '{"content":"+1"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/reactions"
```

### Comment reactions

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/comments/${COMMENT_ID}/reactions"

curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"content":"heart"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/comments/${COMMENT_ID}/reactions"
```

## 仓库级所有评论

按时间窗拉仓库范围内所有 issue+PR 评论（不必逐 issue 查）：

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/comments?since=2026-01-01T00:00:00Z&page=1&limit=50" \
  | jq '[.[] | {id, issue_url, user: .user.login, body: (.body | .[0:80]), created_at}]'
```

可选 `since` / `before` 时间过滤。

## 常见组合

### 创建 issue 并立刻打标签

```bash
# 1. 创建
NUM=$(curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"title":"Bug: x","body":"..."}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues" | jq -r '.number')
# 2. 加标签
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"labels":[3]}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${NUM}/labels"
```

### 关闭并评论

```bash
# 评论
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"body":"Closing as fixed in #42"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/comments"
# 关闭
curl -fsSL -X PATCH -H "Content-Type: application/json" \
  -d '{"state":"closed"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}"
```

## 权限提示

| 操作 | scope |
|------|-------|
| 读 issue | `read:issue`（公开仓库无需） |
| 创建/编辑 issue、评论 | `write:issue` |
| 改 issue 标签 | `write:issue` |
