# 03 — Merge a PR with safety checks

**Skill triggered**: `gitea-pull` (with `gitea-shared`)

## User prompt

> Merge PR #42 in `team-a/web`, squash style, and delete the branch after.

## Why this needs care

- Merging is **irreversible at the API level**. The skill's safety rules require
  showing the user what will be merged before doing it.
- Merge body uses unusual capitalization (`Do`, `MergeTitleField`,
  `MergeMessageField`) — agent must not "fix" them to snake_case.

## Expected flow

### 1. Preview the PR

```bash
curl -fsSL \
  -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
  "${GITEA_HOST}/api/v1/repos/team-a/web/pulls/42" \
  | jq '{number, title, state, mergeable, head: .head.ref, base: .base.ref, head_sha: .head.sha[0:8], commits: .commits, additions, deletions, user: .user.login}'
```

Show the user. If `mergeable` is false, stop and explain (conflicts, CI failed, etc.).

### 2. Check CI status on head commit

```bash
HEAD_SHA=$(curl -fsSL -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
  "${GITEA_HOST}/api/v1/repos/team-a/web/pulls/42" | jq -r '.head.sha')

curl -fsSL -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
  "${GITEA_HOST}/api/v1/repos/team-a/web/commits/${HEAD_SHA}/status" \
  | jq '{state, statuses: [.statuses[] | {context, state}]}'
```

If `state` is not `success`, ask the user whether to use `force_merge: true`.

### 3. Confirm with user, then merge

After explicit user confirmation:

```bash
jq -n --arg Do "squash" --arg MergeTitleField "Add login flow (#42)" \
     --arg MergeMessageField "Closes #41" --arg head_commit_id "$HEAD_SHA" '{
  Do: $Do,
  MergeTitleField: $MergeTitleField,
  MergeMessageField: $MergeMessageField,
  delete_branch_after_merge: true,
  head_commit_id: $head_commit_id
}' | curl -fsSL -X POST \
  -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d @- \
  "${GITEA_HOST}/api/v1/repos/team-a/web/pulls/42/merge"
```

`head_commit_id` makes the merge fail-closed if someone pushed new commits after the agent showed the preview — defense against TOCTOU on a busy PR.

### 4. Verify

```bash
# 204 = merged, 404 = not merged
curl -sSL -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
  "${GITEA_HOST}/api/v1/repos/team-a/web/pulls/42/merge"
```

Should print `204`.

## Variations

- "Schedule auto-merge once CI passes" -> add `merge_when_checks_succeed: true`,
  remove `head_commit_id` (since head may change before checks succeed).
- "Cancel a scheduled auto-merge" -> `DELETE /pulls/42/merge`.
- "fast-forward only because base must stay linear" -> `Do: "fast-forward-only"`.
