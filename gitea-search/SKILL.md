---
name: gitea-search
version: 1.0.0
description: "Gitea 搜索：跨仓库搜索 issue/PR、搜索仓库、用户、组织团队。涵盖 /repos/issues/search、/repos/search、/users/search、/orgs/{org}/teams/search endpoint。当用户需要在 Gitea 上跨多个仓库找 issue、按关键字找仓库或用户、找组织内某团队时使用。"
---

# Gitea Search

**开始前必读 [`../gitea-shared/SKILL.md`](../gitea-shared/SKILL.md)**：认证、curl 模板、错误处理。

下面 curl 都省略 `-H "Authorization: token ${GITEA_ACCESS_TOKEN}" -H "Accept: application/json"`。

## 跨仓库搜索 issue / PR

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/issues/search?q=memory+leak&state=open&type=issues&page=1&limit=50" \
  | jq '[.[] | {repo: .repository.full_name, number, title, state, user: .user.login}]'
```

可选 query：

| 参数 | 含义 |
|------|------|
| `q` | 关键字（标题/正文模糊匹配） |
| `state` | `open` / `closed` / `all`（默认 `open`） |
| `type` | `issues` / `pulls`（不传两者都返回） |
| `labels` | 逗号分隔 label 名 |
| `priority_repo_id` | 提升某个 repo 的结果排序 |
| `owner` | 限定 owner |
| `team` | owner 是组织时，限定团队名 |
| `since` / `before` | ISO 8601 |
| `assigned` | `true` 仅 assigned to me |
| `created` | `true` 仅 created by me |
| `mentioned` | `true` 仅 mentioned me |
| `review_requested` | `true` 仅 review requested from me |
| `reviewed` | `true` 仅我 review 过的 PR |
| `page` / `limit` | 分页 |

## 搜索仓库

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/search?q=mcp&limit=20" \
  | jq '.data | [.[] | {full_name, description, stars: .stars_count, fork: .fork}]'
```

注意响应是 `{ data: [...], ok: true }`，要先 `.data`。

可选 query：

| 参数 | 含义 |
|------|------|
| `q` | 关键字（仓库名） |
| `topic` | 按 topic 标签搜索 |
| `includeDesc` | `true` 时同时匹配 description |
| `uid` | owner user ID |
| `priority_owner_id` | 提升某 owner 的结果 |
| `team_id` | 限定团队 |
| `starredBy` | 被某用户 star |
| `private` | `true` 包含私有 |
| `is_private` | `true` 仅私有 |
| `template` | `true` 仅 template repo |
| `archived` | `true` 包含已归档 |
| `mode` | `fork` / `source` / `mirror` / `collaborative` |
| `exclusive` | `true` 与 owner 严格匹配 |
| `sort` | `alpha` / `created` / `updated` / `size` / `git_size` / `lfs_size` / `stars` / `forks` / `id`（默认 `alpha`） |
| `order` | `asc` / `desc` |
| `page` / `limit` | 分页 |

## 搜索用户

```bash
curl -fsSL "${GITEA_HOST}/api/v1/users/search?q=alice&limit=20" \
  | jq '.data | [.[] | {login, full_name, email, active}]'
```

参数：`q`、`uid`、`page`、`limit`。响应同样在 `.data`。

## 搜索组织团队

```bash
curl -fsSL "${GITEA_HOST}/api/v1/orgs/${ORG}/teams/search?q=frontend&limit=20" \
  | jq '.data | [.[] | {id, name, description, permission}]'
```

可选：`include_desc`（搜索匹配范围是否包含 team description，**默认 true**）、`page`、`limit`。

## 常见组合

### 找 owner 跨多个仓库的 open PR

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/issues/search?type=pulls&owner=${OWNER}&state=open&limit=50" \
  | jq '[.[] | {repo: .repository.full_name, number, title, head: .head.ref}]'
```

### 找当前用户负责评审的 PR

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/issues/search?type=pulls&review_requested=true&state=open" \
  | jq '[.[] | {repo: .repository.full_name, number, title}]'
```

### 找最近 7 天创建的 popular 仓库

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/search?sort=newest&limit=20" \
  | jq '.data | [.[] | {full_name, created_at, stars: .stars_count}]'
```

## 权限提示

| 操作 | scope |
|------|-------|
| 搜索公开仓库/用户/issue | 无 |
| 搜索私有仓库 | `read:repository`（且 token 有访问权） |
| 搜索组织团队 | `read:organization` |
