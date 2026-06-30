---
name: gitea-issue
version: 0.0.1
description: "Gitea Issue management: create/list/update issues, add/edit comments, read/write label associations. Covers /repos/{owner}/{repo}/issues endpoints. Use when you need to file issues on Gitea, view issue lists, add comments, change status, or add/remove labels on issues. Issues and PRs share the same number namespace; use the gitea-pull skill for PR-specific operations."
---

# Gitea Issue

**Read first:** [`../gitea-shared/SKILL.md`](../gitea-shared/SKILL.md) — auth, curl template, pagination, error handling.

All curls below omit `-H "Authorization: token ${GITEA_ACCESS_TOKEN}" -H "Accept: application/json"`; add them yourself.

## Key concepts

- **Issue number**: auto-incrementing integer within a repository, sharing the same sequence as Pull Requests. `#5` may be an issue or a PR.
- The `/issues` endpoint returns both issues and pull requests in issue view (with a `pull_request` field), but PR-specific data (diff, reviewers) requires `/pulls/{n}`.

## List issues

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues?state=open&page=1&limit=50" \
  | jq '[.[] | {number, title, state, user: .user.login, labels: [.labels[].name], updated_at}]'
```

Optional query parameters:

| Parameter | Meaning |
|-----------|---------|
| `state` | `open` / `closed` / `all` (default `open`) |
| `labels` | comma-separated label names |
| `type` | `issues` / `pulls` (omit to return both) |
| `q` | keyword fuzzy match (title/body) |
| `created_by` | filter by creator username |
| `assigned_by` | filter by assignee |
| `mentioned_by` | filter by mentioned username |
| `since` | ISO 8601 timestamp; updated after this time |
| `before` | ISO 8601 timestamp; updated before this time |
| `milestones` | comma-separated milestone names |
| `page` / `limit` | pagination |

## Issue details

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}"
```

Compact output:

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}" \
  | jq '{number, title, state, body, user: .user.login, labels: [.labels[].name], assignees: [.assignees[]?.login], milestone: .milestone.title}'
```

## Create issue

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

Field reference:

| Field | Type | Description |
|-------|------|-------------|
| `title` | string | required |
| `body` | string | body (markdown) |
| `assignees` | string[] | array of usernames |
| `labels` | number[] | array of label **IDs** (not names) |
| `milestone` | number | milestone ID |
| `ref` | string | linked branch/commit |
| `due_date` | ISO 8601 | due date |
| `closed` | bool | create as closed (uncommon) |

To get label/milestone IDs first, see the `gitea-label` and `gitea-milestone` skills.

## Update issue

`PATCH` updates only the fields you provide.

```bash
curl -fsSL -X PATCH -H "Content-Type: application/json" \
  -d '{
    "title": "Bug: foo crashes (root cause: race)",
    "state": "closed",
    "assignees": ["alice","bob"]
  }' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}"
```

Updatable fields: `title`, `body`, `assignees`, `milestone`, `state` (`open`/`closed`), `ref`, `due_date`, `unset_due_date` (set to `true` to clear the due date).

## Comments

### List comments

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/comments" \
  | jq '[.[] | {id, user: .user.login, body, created_at}]'
```

### Add comment

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"body":"Looking into this now."}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/comments"
```

### Edit comment

Note: the endpoint uses the comment ID (not the issue number), under the repository path:

```bash
curl -fsSL -X PATCH -H "Content-Type: application/json" \
  -d '{"body":"Updated comment text"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/comments/${COMMENT_ID}"
```

### Delete comment

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/comments/${COMMENT_ID}"
```

## Label associations

`labels` is an array of repository- or organization-level label **IDs**. List labels with the `gitea-label` skill to get IDs first.

### View issue labels

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/labels"
```

### Add labels

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"labels":[3,7]}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/labels"
```

### Replace all labels

```bash
curl -fsSL -X PUT -H "Content-Type: application/json" \
  -d '{"labels":[3,7]}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/labels"
```

### Remove one label

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/labels/${LABEL_ID}"
```

### Clear all labels

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/labels"
```

## Cross-repository issue search

For cross-repository full-text search, use `search_issues` from the `gitea-search` skill (`/repos/issues/search` path).

## Reactions

Issues and issue comments both support reactions. Common `content` values: `+1`, `-1`, `laugh`, `hooray`, `confused`, `heart`, `rocket`, `eyes`.

### Issue reactions

```bash
# list
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/reactions" \
  | jq '[.[] | {user: .user.login, content, created_at}]'

# add (repeated POST with same content by the same user is idempotent)
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"content":"+1"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/reactions"

# delete (your own)
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

## All comments in a repository

Fetch all issue+PR comments in a repository within a time window (no need to query issue by issue):

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/comments?since=2026-01-01T00:00:00Z&page=1&limit=50" \
  | jq '[.[] | {id, issue_url, user: .user.login, body: (.body | .[0:80]), created_at}]'
```

Optional `since` / `before` time filters.

## Common workflows

### Create issue and add labels immediately

```bash
# 1. create
NUM=$(curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"title":"Bug: x","body":"..."}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues" | jq -r '.number')
# 2. add labels
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"labels":[3]}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${NUM}/labels"
```

### Close and comment

```bash
# comment
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"body":"Closing as fixed in #42"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/comments"
# close
curl -fsSL -X PATCH -H "Content-Type: application/json" \
  -d '{"state":"closed"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}"
```

## Permission notes

| Operation | scope |
|-----------|-------|
| read issue | `read:issue` (not required for public repos) |
| create/edit issue, comments | `write:issue` |
| change issue labels | `write:issue` |
