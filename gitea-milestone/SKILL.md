---
name: gitea-milestone
version: 0.0.1
description: "Gitea Milestone：仓库级里程碑的列出/获取/创建/更新/删除。涵盖 /repos/{owner}/{repo}/milestones endpoint。当用户需要在 Gitea 上管理 milestone、给 issue/PR 关联里程碑、设截止日期或关闭里程碑时使用。"
---

# Gitea Milestone

**开始前必读 [`../gitea-shared/SKILL.md`](../gitea-shared/SKILL.md)**：认证、curl 模板、错误处理。

下面 curl 都省略 `-H "Authorization: token ${GITEA_ACCESS_TOKEN}" -H "Accept: application/json"`。

## 关键概念

- Milestone 是仓库级，**没有组织级**。
- Issue / PR 通过 milestone **数字 ID** 关联（不是 title）。

## 列出

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/milestones?state=open&page=1&limit=50" \
  | jq '[.[] | {id, title, state, due_on, open_issues, closed_issues}]'
```

可选 query：

| 参数 | 含义 |
|------|------|
| `state` | `open` / `closed` / `all`（默认 `open`） |
| `name` | 模糊匹配 title |
| `page` / `limit` | 分页 |

## 获取单个

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/milestones/${ID}"
```

## 创建

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{
    "title": "v1.0.0",
    "description": "First stable release",
    "due_on": "2026-12-31T23:59:59Z"
  }' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/milestones"
```

字段说明：

| 字段 | 必填 | 说明 |
|------|------|------|
| `title` | 是 | |
| `description` | 否 | |
| `due_on` | 否 | ISO 8601 时间戳，UTC（带 Z 或时区） |
| `state` | 否 | `open` / `closed` |

## 更新

```bash
curl -fsSL -X PATCH -H "Content-Type: application/json" \
  -d '{"state":"closed"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/milestones/${ID}"
```

可改：`title`、`description`、`state`、`due_on`。

## 删除

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/milestones/${ID}"
```

删除 milestone 不会删除关联的 issue / PR，只会让它们脱离。

## 常见组合

### 查关联到某 milestone 的所有 issue

```bash
# 拿 milestone title
TITLE=$(curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/milestones/${ID}" | jq -r '.title')
# issue 列表查询用 milestone 名（comma-separated 多个）
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues?milestones=${TITLE}&state=all" \
  | jq '[.[] | {number, title, state}]'
```

## 权限提示

| 操作 | scope |
|------|-------|
| 读 milestone | `read:repository` |
| 写 milestone | `write:repository` |
