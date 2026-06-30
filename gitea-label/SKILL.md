---
name: gitea-label
version: 0.0.2
description: "Gitea Label management: list, create, edit, and delete repository-level and organization-level labels. Covers /repos/{owner}/{repo}/labels and /orgs/{org}/labels endpoints. Use when you need to manage issue/PR labels in a Gitea repo or org, batch-create labels, change label colors, or archive labels."
---

# Gitea Label

**Read first:** [`../gitea-shared/SKILL.md`](../gitea-shared/SKILL.md) — auth, curl template, error handling.

The curls below omit `-H "Authorization: token ${GITEA_ACCESS_TOKEN}" -H "Accept: application/json"`.

## Key concepts

- Gitea has two kinds of labels:
  - **Repository labels**: belong to a single repo
  - **Organization labels**: belong to an org; all repos under the org can share them
- Labels are linked on issues / PRs by **numeric ID** (not name). If you don't have the ID when labeling an issue, list labels first.
- The color field is 6-digit hex; **with or without `#` is accepted** (swagger example is `#00aabb`, but both forms work in practice).

## Repository-level labels

### List

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/labels?page=1&limit=50" \
  | jq '[.[] | {id, name, color, description, is_archived}]'
```

### Get one

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/labels/${LABEL_ID}"
```

### Create

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{
    "name": "bug",
    "color": "#e11d21",
    "description": "Something is broken",
    "exclusive": false,
    "is_archived": false
  }' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/labels"
```

`exclusive` applies only to scoped labels (only one label per prefix can be selected).

### Edit

`PATCH` updates only the fields you provide.

```bash
curl -fsSL -X PATCH -H "Content-Type: application/json" \
  -d '{"color":"#d73a4a","description":"Bug confirmed"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/labels/${LABEL_ID}"
```

Updatable fields: `name`, `color`, `description`, `exclusive`, `is_archived`.

### Delete

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/labels/${LABEL_ID}"
```

## Organization-level labels

Replace `repos/{owner}/{repo}` with `orgs/{org}`:

```bash
# list
curl -fsSL "${GITEA_HOST}/api/v1/orgs/${ORG}/labels?page=1&limit=50"
# create
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"name":"good first issue","color":"7057ff","description":"For new contributors"}' \
  "${GITEA_HOST}/api/v1/orgs/${ORG}/labels"
# edit
curl -fsSL -X PATCH -H "Content-Type: application/json" \
  -d '{"description":"Beginner-friendly"}' \
  "${GITEA_HOST}/api/v1/orgs/${ORG}/labels/${LABEL_ID}"
# delete
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/orgs/${ORG}/labels/${LABEL_ID}"
```

## Batch initialize common labels

```bash
declare -A LABELS=(
  [bug]="#d73a4a"
  [enhancement]="#a2eeef"
  ["good first issue"]="#7057ff"
  [documentation]="#0075ca"
  [question]="#d876e3"
)
for NAME in "${!LABELS[@]}"; do
  curl -fsSL -X POST -H "Content-Type: application/json" \
    -d "$(jq -n --arg n "$NAME" --arg c "${LABELS[$NAME]}" '{name:$n,color:$c}')" \
    "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/labels"
done
```

## Permission notes

| Operation | scope |
|-----------|-------|
| read repository labels | `read:repository` |
| write repository labels | `write:repository` |
| read/write organization labels | `read:organization` / `write:organization` (and must be org owner/admin) |
