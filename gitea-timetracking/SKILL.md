---
name: gitea-timetracking
version: 0.0.1
description: "Gitea time tracking: issue stopwatch (start/stop/cancel), manually add and delete time entries, list time by issue/repo/current user. Covers /repos/{owner}/{repo}/issues/{n}/stopwatch and /times endpoints. Use when you need to track time on Gitea issues, summarize repo time, or view your own time entries."
---

# Gitea Time Tracking

**Read first:** [`../gitea-shared/SKILL.md`](../gitea-shared/SKILL.md) — auth, curl template, error handling.

The curls below omit `-H "Authorization: token ${GITEA_ACCESS_TOKEN}" -H "Accept: application/json"`.

## Key concepts

- **Stopwatch**: each user can have **at most one** running stopwatch per issue. Stopping automatically writes a time entry.
- **Time entry**: a single time record with user, time (seconds), and created.
- The repo must have **Time Tracker** enabled in settings.

## Stopwatch

### Start

```bash
curl -fsSL -X POST \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/stopwatch/start"
```

Returns 409 if this user already has a running stopwatch. Check `/user/stopwatches` first.

### Stop (writes time entry automatically)

```bash
curl -fsSL -X POST \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/stopwatch/stop"
```

### Cancel (does not write time)

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/stopwatch/delete"
```

### Active stopwatches for the current user

```bash
curl -fsSL "${GITEA_HOST}/api/v1/user/stopwatches" \
  | jq '[.[] | {issue: .issue.number, repo: .issue.repo.full_name, seconds, created}]'
```

## Time entries

`TrackedTime` fields (from swagger): `id`, `time` (seconds), `user_id` (**deprecated**), `user_name`, `issue_id`, `issue`, `created`. Use `user_name` in jq output.

### List time for an issue

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/times?page=1&limit=50" \
  | jq '[.[] | {id, user: .user_name, time, created}]'
```

Optional query: `user` (filter by username; visible only to issue managers), `since`, `before`, `page`, `limit`.

### List time for a repository

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/times?page=1&limit=50" \
  | jq '[.[] | {user: .user_name, issue: .issue_id, time, created}]'
```

Optional query: `user`, `since`, `before`, `page`, `limit`.

### List all time for the current user

```bash
curl -fsSL "${GITEA_HOST}/api/v1/user/times?page=1&limit=50" \
  | jq '[.[] | {issue: .issue_id, time, created}]'
```

### Manually add time

`AddTimeOption` body:

| Field | Required | Description |
|-------|----------|-------------|
| `time` | yes | seconds |
| `created` | no | ISO 8601; overrides record timestamp (default now) |
| `user_name` | no | issue managers only: record time on behalf of another user |

```bash
# add 30 minutes
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"time": 1800}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/times"

# backfill for yesterday
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"time": 3600, "created": "2026-05-14T15:00:00Z"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/times"
```

### Delete a single time entry

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/times/${TIME_ID}"
```

## Common workflows

### Add 1 hour to an issue and view the total

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"time": 3600}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/times"

# view total time on the issue
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/issues/${N}/times" \
  | jq 'map(.time) | add / 3600 | "\(.) hours"'
```

### Summarize per-user hours this month for a repo

```bash
SINCE="$(date -u +%Y-%m-01T00:00:00Z)"
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/times?since=${SINCE}&limit=100" \
  | jq 'group_by(.user_name) | map({user: .[0].user_name, total_hours: (map(.time) | add / 3600)})'
```

## Permission notes

| Operation | scope |
|-----------|-------|
| read issue/repo time | `read:repository` (and Time Tracker enabled on repo) |
| write your own time | `read:repository` (and must be a collaborator) |
| delete others' time | repo admin |
