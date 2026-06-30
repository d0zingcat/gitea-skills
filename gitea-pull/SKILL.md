---
name: gitea-pull
version: 0.0.2
description: "Gitea Pull Request management: create/edit/merge/close PRs, read diff and file lists, review workflow (create review, submit pending review, approve/reject/dismiss, add inline comments), add/remove reviewers, update PR branch from base. Covers /repos/{owner}/{repo}/pulls REST endpoints. Use when the user needs to open PRs, merge PRs, run code review workflows, revert reviews, or inspect PR changed files or diffs on Gitea."
---

# Gitea Pull Request

**Read [`../gitea-shared/SKILL.md`](../gitea-shared/SKILL.md) first:** authentication, curl templates, error handling, security rules.

All curl commands below omit `-H "Authorization: token ${GITEA_ACCESS_TOKEN}" -H "Accept: application/json"`.

## Key Concepts

- **PR number** shares a per-repository sequence with issues.
- PRs have two endpoint groups:
  - Issue perspective: `/repos/{owner}/{repo}/issues/{n}` (comments, labels, state changes, assignees)
  - PR perspective: `/repos/{owner}/{repo}/pulls/{n}` (diff, files, reviews, merge, reviewers, update branch)
- **Draft PR:** implemented by prefixing the title with `WIP:` (the `draft` parameter exposed by gitea-mcp essentially changes the title).

## List Pull Requests

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls?state=open&sort=recentupdate&page=1&limit=50" \
  | jq '[.[] | {number, title, state, head: .head.ref, base: .base.ref, user: .user.login, mergeable, merged}]'
```

Optional query parameters:

| Parameter | Meaning |
|------|------|
| `state` | `open` (default) / `closed` / `all` |
| `sort` | `oldest` / `recentupdate` (default) / `recentclose` / `leastupdate` / `mostcomment` / `leastcomment` / `priority` |
| `milestone` | Milestone ID |
| `labels` | Comma-separated label IDs |
| `poster` | Creator username |
| `base_branch` | Filter by target branch name |
| `page` / `limit` | Pagination |

## PR Details

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}"
```

Condensed:

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}" \
  | jq '{number, title, state, body, mergeable, merged, head: {ref:.head.ref,sha:.head.sha}, base: .base.ref, user: .user.login}'
```

## Create Pull Request

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{
    "title": "Add feature X",
    "body": "## Summary\n...",
    "head": "feat/x",
    "base": "main",
    "labels": [3],
    "milestone": 1,
    "reviewers": ["alice"],
    "team_reviewers": ["frontend"]
  }' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls"
```

Field reference (from swagger `CreatePullRequestOption`):

| Field | Required | Description |
|------|------|------|
| `title` | Yes | For draft PRs, manually prefix with `WIP: ` |
| `body` | No | Markdown |
| `head` | Yes | Source branch; cross-repo format: `username:branch` |
| `base` | Yes | Target branch |
| `assignee` | No | Single username |
| `assignees` | No | Array of usernames |
| `labels` | No | Array of label IDs |
| `milestone` | No | Milestone ID |
| `reviewers` | No | Array of usernames (request review at creation time; avoids a separate `requested_reviewers` call) |
| `team_reviewers` | No | Array of team slugs |
| `due_date` | No | ISO 8601 |

Cross-repo PR `head` format: `fork-owner:branch-name`.

## Edit Pull Request

```bash
curl -fsSL -X PATCH -H "Content-Type: application/json" \
  -d '{"title":"Add feature X (rev2)","body":"updated","base":"develop"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}"
```

Editable fields: `title`, `body`, `base`, `assignees`, `milestone`, `labels`, `state` (`open` to reopen / `closed` to close), `due_date`, `unset_due_date`, `allow_maintainer_edit`.

Toggle draft status: add or remove the `WIP: ` prefix in `title`.

## Close / Reopen Pull Request

```bash
# Close
curl -fsSL -X PATCH -H "Content-Type: application/json" \
  -d '{"state":"closed"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}"
# Reopen
curl -fsSL -X PATCH -H "Content-Type: application/json" \
  -d '{"state":"open"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}"
```

## Diff and File List

### Fetch Diff (Text)

```bash
curl -fsSL -H "Accept: text/plain" \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}.diff"
```

The `.patch` suffix returns mbox format.

### Changed Files List

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/files?page=1&limit=50" \
  | jq '[.[] | {filename, status, additions, deletions, changes}]'
```

Optional query:

| Parameter | Meaning |
|------|------|
| `whitespace` | `ignore-all` / `ignore-change` / `ignore-eol` / `show-all` (how whitespace is handled when computing line diffs) |
| `skip-to` | Start returning files after the given file path (batch large PRs) |
| `page` / `limit` | Pagination |

### PR Commits List

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/commits?page=1&limit=50" \
  | jq '[.[] | {sha: .sha[0:8], msg: (.commit.message | split("\n")[0]), author: .commit.author.name}]'
```

Optional query:

| Parameter | Meaning |
|------|------|
| `verification` | `true` includes GPG signature info per commit |
| `files` | `true` includes changed files per commit |
| `page` / `limit` | Pagination |

## Merge Pull Request

**High-risk operation — confirm user intent before merging.**

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{
    "Do": "merge",
    "MergeTitleField": "Add feature X (#42)",
    "MergeMessageField": "Closes #41",
    "delete_branch_after_merge": true
  }' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/merge"
```

**Note casing:** in the merge body, `Do`, `MergeTitleField`, `MergeMessageField`, `MergeCommitID` are PascalCase (legacy); `delete_branch_after_merge`, `force_merge`, `head_commit_id`, `merge_when_checks_succeed` are snake_case. This matches the swagger definition — copy as-is.

`Do` values (from swagger `MergePullRequestForm.Do.enum`):

| Value | Meaning |
|------|------|
| `merge` | Standard merge commit |
| `rebase` | Rebase then fast-forward |
| `rebase-merge` | Rebase then create a merge commit |
| `squash` | Squash into a single commit |
| `fast-forward-only` | Fast-forward only; succeeds only when base is behind head, otherwise 422 |
| `manually-merged` | Mark as manually merged (requires `MergeCommitID`) |

Other fields:

| Field | Description |
|------|------|
| `MergeCommitID` | Used with `manually-merged`; tells Gitea which commit was manually merged |
| `delete_branch_after_merge` | Delete head branch after merge |
| `force_merge` | Merge even if checks have not passed |
| `head_commit_id` | Expected head SHA; returns 409 if actual head does not match |
| `merge_when_checks_succeed` | Auto-merge when CI passes |

### Check Whether PR Is Merged

```bash
# 204 = merged, 404 = not merged
curl -sSL -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/merge"
```

### Cancel Scheduled Auto-Merge

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/merge"
```

## update_branch (Sync PR Branch with Base)

```bash
curl -fsSL -X POST \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/update"
```

Optional `?style=merge` or `?style=rebase`. Default is merge.

## Reviewers

### Add Reviewers

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"reviewers":["alice","bob"],"team_reviewers":["frontend"]}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/requested_reviewers"
```

### Remove Reviewers

```bash
curl -fsSL -X DELETE -H "Content-Type: application/json" \
  -d '{"reviewers":["alice"]}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/requested_reviewers"
```

## Review

A review is a container for review actions and can include inline comments. A review has four states: `PENDING`, `APPROVED`, `REQUEST_CHANGES`, `COMMENT`.

### List Reviews

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/reviews?page=1&limit=50" \
  | jq '[.[] | {id, user: .user.login, state, submitted_at, body}]'
```

### Single Review

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/reviews/${REVIEW_ID}"
```

### Inline Comments on a Review

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/reviews/${REVIEW_ID}/comments" \
  | jq '[.[] | {id, path, position, body, user: .user.login}]'
```

### Create Review

Can include all inline comments in one request. `event` determines the state:

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{
    "commit_id": "abc123...",
    "body": "Overall LGTM, two small nits.",
    "event": "APPROVED",
    "comments": [
      {"path":"src/foo.go","old_position":12,"body":"typo here"},
      {"path":"src/foo.go","new_position":34,"body":"can be simpler"}
    ]
  }' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/reviews"
```

Field reference:

- `commit_id`: head SHA being reviewed (defaults to current head if omitted)
- `event`: `APPROVED` / `REQUEST_CHANGES` / `COMMENT` / omit or `PENDING` (saved as pending)
- `comments[]`:
  - `path`: file path relative to repository root
  - `old_position`: line number on the old file (deleted/unchanged lines)
  - `new_position`: line number on the new file (added/unchanged lines)
  - `body`: comment text

Either `old_position` or `new_position` is sufficient; line numbers come from patch hunks in the `pulls/{n}/files` response.

### Submit Pending Review

If a PENDING review was created first (`event` omitted), submit later:

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"event":"APPROVED","body":"Final approval"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/reviews/${REVIEW_ID}"
```

### Delete Review

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/reviews/${REVIEW_ID}"
```

### Dismiss Review

Dismiss another user's review (invalidates APPROVED / REQUEST_CHANGES; often used with branch protection):

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"message":"Outdated due to new commits","priors":false}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/reviews/${REVIEW_ID}/dismissals"
```

### Undo Dismiss

```bash
curl -fsSL -X POST \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/reviews/${REVIEW_ID}/undismissals"
```

Restores the effect of a dismissed review.

## PR Status (CI / Merge Checks)

Check status for the PR head commit uses the commit statuses endpoint:

```bash
HEAD_SHA=$(curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}" | jq -r '.head.sha')
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/commits/${HEAD_SHA}/statuses?page=1&limit=50" \
  | jq '[.[] | {context, state, description, target_url}]'
```

Or combined status:

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/commits/${HEAD_SHA}/status"
```

## Common Workflows

### Full Open + Review + Merge

```bash
# 1. Create PR
PR_NUM=$(curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"title":"feat: x","body":"...","head":"feat/x","base":"main"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls" | jq -r '.number')

# 2. Request review
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"reviewers":["alice"]}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${PR_NUM}/requested_reviewers"

# 3. (Reviewer) Approve
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"event":"APPROVED","body":"LGTM"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${PR_NUM}/reviews"

# 4. Merge + delete branch
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"Do":"squash","delete_branch_after_merge":true}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${PR_NUM}/merge"
```

### Sync PR Branch with Base

```bash
curl -fsSL -X POST \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/update?style=rebase"
```

## Permission Notes

| Operation | Scope |
|------|-------|
| Read PR, diff, files | `read:repository` |
| Create/edit PR | `write:repository` |
| Create/submit review | `write:repository` (and must be a collaborator) |
| Merge PR | `write:repository` (and branch merge permission) |
