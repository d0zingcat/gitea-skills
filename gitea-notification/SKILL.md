---
name: gitea-notification
version: 0.0.2
description: "Gitea notifications: list unread/read notifications (user-level or repo-level), get a single thread, mark as read, and batch mark. Covers /notifications and /repos/{owner}/{repo}/notifications endpoints. Use when you need to check your Gitea inbox, bulk-clear unread items, or view notification details."
---

# Gitea Notification

**Read first:** [`../gitea-shared/SKILL.md`](../gitea-shared/SKILL.md) — auth, curl template, error handling.

The curls below omit `-H "Authorization: token ${GITEA_ACCESS_TOKEN}" -H "Accept: application/json"`.

## Key concepts

- Notifications are from the **current user's** perspective (the authenticated token determines the subject).
- A **thread** corresponds to an update chain for an issue / PR / commit / repo — not a single comment.
- States: `unread` / `read` / `pinned`.

## List

### All (current user)

```bash
curl -fsSL "${GITEA_HOST}/api/v1/notifications?status-types=unread&page=1&limit=50" \
  | jq '[.[] | {id, subject: .subject.title, type: .subject.type, state: .subject.state, repo: .repository.full_name, updated_at}]'
```

### Repository scope

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/notifications?status-types=unread"
```

### Optional filters

| Parameter | Meaning |
|-----------|---------|
| `status-types` | repeat for multiple values: `unread` / `read` / `pinned` (e.g. `?status-types=unread&status-types=pinned`) |
| `subject-type` | `issue` / `pull` / `commit` / `repository` (**all lowercase**; response `.subject.type` is TitleCase such as `Issue`) |
| `since` | ISO 8601; updated after this time |
| `before` | ISO 8601; updated before this time |
| `all` | `true` to **also include read** notifications (default returns only unread + pinned) |
| `page` / `limit` | pagination |

## Single thread

```bash
curl -fsSL "${GITEA_HOST}/api/v1/notifications/threads/${ID}"
```

## Mark as read

### Single thread

```bash
curl -fsSL -X PATCH \
  "${GITEA_HOST}/api/v1/notifications/threads/${ID}"
```

Optional `?to-status=read|pinned|unread` to change state.

### Batch (user-level)

```bash
curl -fsSL -X PUT \
  "${GITEA_HOST}/api/v1/notifications?last_read_at=$(date -u +%FT%TZ)"
```

If `last_read_at` is omitted, the current time is used. Notifications older than that time are marked read.

Additional query parameters to limit what gets marked:
- `?to-status=read` (default) / `pinned` / `unread`
- `?status-types=unread` (repeat) to mark only certain states
- `?all=true` to include read notifications

```bash
# mark only unread PR notifications as read
curl -fsSL -X PUT \
  "${GITEA_HOST}/api/v1/notifications?status-types=unread&subject-type=pull"
```

### Batch (repo-level)

```bash
curl -fsSL -X PUT \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/notifications"
```

## Common workflows

### List unread PR review notifications

```bash
curl -fsSL "${GITEA_HOST}/api/v1/notifications?status-types=unread&subject-type=Pull&limit=50" \
  | jq '[.[] | {id, title: .subject.title, repo: .repository.full_name, url: .subject.html_url}]'
```

### Mark all unread as read in one step

```bash
curl -fsSL -X PUT "${GITEA_HOST}/api/v1/notifications"
```

**This is irreversible** (you cannot bulk-restore unread after marking read). Confirm user intent before running.

## Permission notes

`/notifications` uses the current user's token; no extra scope required. `/repos/{owner}/{repo}/notifications` requires at least `read:repository`.
