---
name: gitea-search
version: 0.0.1
description: "Gitea search: cross-repository issue/PR search, repository search, user search, and organization team search. Covers /repos/issues/search, /repos/search, /users/search, and /orgs/{org}/teams/search endpoints. Use when you need to find issues across multiple Gitea repositories, search repositories or users by keyword, or find a team within an organization."
---

# Gitea Search

**Read first:** [`../gitea-shared/SKILL.md`](../gitea-shared/SKILL.md) — auth, curl template, error handling.

The curls below omit `-H "Authorization: token ${GITEA_ACCESS_TOKEN}" -H "Accept: application/json"`.

## Cross-repository issue / PR search

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/issues/search?q=memory+leak&state=open&type=issues&page=1&limit=50" \
  | jq '[.[] | {repo: .repository.full_name, number, title, state, user: .user.login}]'
```

Optional query parameters:

| Parameter | Meaning |
|-----------|---------|
| `q` | keyword (fuzzy match on title/body) |
| `state` | `open` / `closed` / `all` (default `open`) |
| `type` | `issues` / `pulls` (omit to return both) |
| `labels` | comma-separated label names |
| `priority_repo_id` | boost results from a specific repo |
| `owner` | limit to owner |
| `team` | when owner is an org, limit to team name |
| `since` / `before` | ISO 8601 |
| `assigned` | `true` — only assigned to me |
| `created` | `true` — only created by me |
| `mentioned` | `true` — only mentioned me |
| `review_requested` | `true` — only review requested from me |
| `reviewed` | `true` — only PRs I reviewed |
| `page` / `limit` | pagination |

## Search repositories

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/search?q=mcp&limit=20" \
  | jq '.data | [.[] | {full_name, description, stars: .stars_count, fork: .fork}]'
```

Note: the response is `{ data: [...], ok: true }`; use `.data` first.

Optional query parameters:

| Parameter | Meaning |
|-----------|---------|
| `q` | keyword (repository name) |
| `topic` | search by topic tag |
| `includeDesc` | when `true`, also match description |
| `uid` | owner user ID |
| `priority_owner_id` | boost results from a specific owner |
| `team_id` | limit to team |
| `starredBy` | starred by a user |
| `private` | `true` — include private repos |
| `is_private` | `true` — private repos only |
| `template` | `true` — template repos only |
| `archived` | `true` — include archived |
| `mode` | `fork` / `source` / `mirror` / `collaborative` |
| `exclusive` | `true` — strict match on owner |
| `sort` | `alpha` / `created` / `updated` / `size` / `git_size` / `lfs_size` / `stars` / `forks` / `id` (default `alpha`) |
| `order` | `asc` / `desc` |
| `page` / `limit` | pagination |

## Search users

```bash
curl -fsSL "${GITEA_HOST}/api/v1/users/search?q=alice&limit=20" \
  | jq '.data | [.[] | {login, full_name, email, active}]'
```

Parameters: `q`, `uid`, `page`, `limit`. Response is also under `.data`.

## Search organization teams

```bash
curl -fsSL "${GITEA_HOST}/api/v1/orgs/${ORG}/teams/search?q=frontend&limit=20" \
  | jq '.data | [.[] | {id, name, description, permission}]'
```

Optional: `include_desc` (whether search matches team description; **default true**), `page`, `limit`.

## Common workflows

### Find open PRs across an owner's repositories

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/issues/search?type=pulls&owner=${OWNER}&state=open&limit=50" \
  | jq '[.[] | {repo: .repository.full_name, number, title, head: .head.ref}]'
```

### Find PRs awaiting my review

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/issues/search?type=pulls&review_requested=true&state=open" \
  | jq '[.[] | {repo: .repository.full_name, number, title}]'
```

### Find popular repositories created in the last 7 days

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/search?sort=newest&limit=20" \
  | jq '.data | [.[] | {full_name, created_at, stars: .stars_count}]'
```

## Permission notes

| Operation | scope |
|-----------|-------|
| search public repos/users/issues | none |
| search private repos | `read:repository` (and token must have access) |
| search organization teams | `read:organization` |
