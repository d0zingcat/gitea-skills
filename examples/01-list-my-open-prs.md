# 01 — List my open pull requests across all repos

**Skill triggered**: `gitea-search` (with `gitea-shared` as base)

## User prompt

> What PRs do I have open across all repos? I just want a quick view.

## Expected agent reasoning

- "across all repos" + "PRs I created" -> cross-repo search, not per-repo listing
- Use `/repos/issues/search?type=pulls&created=true&state=open`
- Add `limit=50` and jq down to essentials (no full user/repo blobs)

## Resulting command

```bash
curl -fsSL \
  -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
  "${GITEA_HOST}/api/v1/repos/issues/search?type=pulls&created=true&state=open&limit=50" \
  | jq '[.[] | {repo: .repository.full_name, number, title, head: .head_branch, age_days: ((now - (.created_at | fromdateiso8601)) / 86400 | floor)}]'
```

## Sample output

```json
[
  {"repo": "team-a/web", "number": 142, "title": "Add login flow", "head": "feat/login", "age_days": 2},
  {"repo": "team-a/web", "number": 138, "title": "Fix CSP header", "head": "fix/csp", "age_days": 7},
  {"repo": "infra/deploy", "number": 17, "title": "Bump runner image", "head": "ops/runner-1.24", "age_days": 1}
]
```

## Variations the agent might offer

- "PRs assigned to me to review" -> swap `created=true` for `review_requested=true`
- "Only in productivity org" -> add `&owner=productivity`
- "Including closed but not merged" -> add `&state=all` then jq filter `select(.state=="closed" and (.pull_request.merged // false) | not)`
