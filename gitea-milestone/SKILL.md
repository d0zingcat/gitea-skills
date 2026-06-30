---
name: gitea-milestone
version: 0.0.2
description: "Gitea Milestone: list, get, create, update, and delete repository-level milestones. Covers /repos/{owner}/{repo}/milestones endpoints. Use when you need to manage milestones on Gitea, associate issues/PRs with a milestone, set due dates, or close milestones."
---

# Gitea Milestone

**Read first:** [`../gitea-shared/SKILL.md`](../gitea-shared/SKILL.md) — auth, curl template, error handling.

The curls below omit `-H "Authorization: token ${GITEA_ACCESS_TOKEN}" -H "Accept: application/json"`.

## Key concepts

- Milestones are **repository-level**; there is **no organization-level** milestone.
- Issues / PRs are linked via milestone **numeric ID** (not title).

## List

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/milestones?state=open&page=1&limit=50" \
  | jq '[.[] | {id, title, state, due_on, open_issues, closed_issues}]'
```

Optional query parameters:

| Parameter | Meaning |
|-----------|---------|
| `state` | `open` / `closed` / `all` (default `open`) |
| `name` | fuzzy match on title |
| `page` / `limit` | pagination |

## Get one

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/milestones/${ID}"
```

## Create

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{
    "title": "v1.0.0",
    "description": "First stable release",
    "due_on": "2026-12-31T23:59:59Z"
  }' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/milestones"
```

Field reference:

| Field | Required | Description |
|-------|----------|-------------|
| `title` | yes | |
| `description` | no | |
| `due_on` | no | ISO 8601 timestamp, UTC (with Z or timezone) |
| `state` | no | `open` / `closed` |

## Update

```bash
curl -fsSL -X PATCH -H "Content-Type: application/json" \
  -d '{"state":"closed"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/milestones/${ID}"
```

Updatable fields: `title`, `description`, `state`, `due_on`.

## Delete

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/milestones/${ID}"
```

Deleting a milestone does not delete associated issues / PRs; it only detaches them.

## Common workflows

### List all issues linked to a milestone

```bash
# get milestone title
TITLE=$(curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/milestones/${ID}" | jq -r '.title')
# issue list query uses milestone name (comma-separated for multiple)
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues?milestones=${TITLE}&state=all" \
  | jq '[.[] | {number, title, state}]'
```

## Permission notes

| Operation | scope |
|-----------|-------|
| read milestone | `read:repository` |
| write milestone | `write:repository` |
