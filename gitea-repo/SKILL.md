---
name: gitea-repo
version: 0.0.1
description: "Gitea repository operations: list/create/fork repos, branch management, commit queries, file read/write, tags and releases, directory trees. Covers repos/branches/commits/contents/releases/tags/git/trees REST endpoints. Use when the user needs to list/create repos, fork, create/delete branches, read or edit files, query commits, create tags, publish releases, or browse repository directory structure on Gitea."
---

# Gitea Repository (repo)

**Read [`../gitea-shared/SKILL.md`](../gitea-shared/SKILL.md) first:** `GITEA_HOST` / `GITEA_ACCESS_TOKEN`, curl templates, error codes, security rules.

All commands below omit:

```bash
-H "Authorization: token ${GITEA_ACCESS_TOKEN}"
-H "Accept: application/json"
```

Add these headers to every curl.

## Resource Relationships

```
Repo (owner/repo)
├── Branch          (refs/heads/<branch>)
│   └── Commit      (sha)
│       └── File    (path@ref)
├── Tag             (tag_name)
└── Release         (id, linked to tag_name)
```

## Repository

### List Current User Repositories

```bash
curl -fsSL "${GITEA_HOST}/api/v1/user/repos?page=1&limit=50" \
  | jq '[.[] | {full_name, private, default_branch, description}]'
```

### List Organization Repositories

```bash
curl -fsSL "${GITEA_HOST}/api/v1/orgs/${ORG}/repos?page=1&limit=100" \
  | jq '[.[] | {full_name, private, default_branch}]'
```

### Create Repository

Personal: `POST /user/repos`; organization: `POST /orgs/{org}/repos`.

```bash
# Personal repository
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{
    "name": "my-repo",
    "description": "demo",
    "private": false,
    "auto_init": true,
    "default_branch": "main",
    "license": "MIT",
    "gitignores": "Go",
    "readme": "Default"
  }' \
  "${GITEA_HOST}/api/v1/user/repos"

# Organization repository
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"name":"my-repo","auto_init":true}' \
  "${GITEA_HOST}/api/v1/orgs/${ORG}/repos"
```

Optional body fields: `description`, `private`, `issue_labels` (label set name), `auto_init`, `template`, `gitignores`, `license`, `readme`, `default_branch`, `trust_model` (`default`/`collaborator`/`committer`/`collaboratorcommitter`), `object_format_name` (`sha1`/`sha256`).

### Fork Repository

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"organization":"my-org","name":"forked-name"}' \
  "${GITEA_HOST}/api/v1/repos/${USER}/${REPO}/forks"
```

If `organization` is omitted, the fork goes under the current user; if `name` is omitted, the same name is used.

## Branch

### List Branches

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/branches?page=1&limit=50" \
  | jq '[.[] | {name, commit_sha: .commit.id, protected}]'
```

### Create Branch

`CreateBranchRepoOption` body:

| Field | Required | Description |
|------|------|------|
| `new_branch_name` | Yes | New branch name |
| `old_ref_name` | No | Source ref; can be a **branch / tag / commit SHA**. Defaults to the repository default branch if omitted. |
| `old_branch_name` | No | **Deprecated**; kept for backward compatibility only. Use `old_ref_name` in new code. |

```bash
# Create branch from main
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"new_branch_name":"feature/x","old_ref_name":"main"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/branches"

# Create branch from a tag
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"new_branch_name":"hotfix/v1.0","old_ref_name":"v1.0.0"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/branches"

# Create branch from a commit
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"new_branch_name":"backport","old_ref_name":"abc123def"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/branches"
```

### Delete Branch

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/branches/${BRANCH}"
```

## Commit

### List Repository Commits

Optional `sha` (starting SHA or branch name), `path` (only commits affecting that path).

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/commits?sha=main&page=1&limit=20" \
  | jq '[.[] | {sha, msg: .commit.message, author: .commit.author.name, date: .commit.author.date}]'
```

### Single Commit Details

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/commits/${SHA}" \
  | jq '{sha, message: .commit.message, files: [.files[].filename]}'
```

## File (Read/Write)

Do **not URL-encode slashes** in `path`; concatenate directly in the URL.

### Read File Content

`ref` can be a branch name, tag, or SHA.

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/contents/${PATH}?ref=${REF}" \
  | jq -r '.content' | base64 -d
```

To keep base64 metadata:

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/contents/${PATH}?ref=${REF}" \
  | jq '{name, sha, size, encoding, html_url}'
```

### List Directory Entries

Provide a directory path for `path`; the response is an array:

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/contents/${DIR}?ref=${REF}" \
  | jq '[.[] | {name, type, size, sha}]'
```

`type` is `file` / `dir` / `symlink` / `submodule`.

### Create File

`CreateFileOptions` body:

| Field | Required | Description |
|------|------|------|
| `content` | Yes | **Must be base64-encoded** |
| `branch` | No | Target branch; defaults to repository default branch if omitted |
| `new_branch` | No | If set, creates this branch from `branch` first, then commits |
| `message` | No | Commit message; a default is used if omitted |
| `author` / `committer` | No | `Identity` type `{name, email}`; overrides committer identity |
| `signoff` | No | When `true`, automatically adds a `Signed-off-by` line |
| `dates` | No | `CommitDateOptions`; custom commit timestamps |

```bash
CONTENT=$(printf 'hello\n' | base64)
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d "$(jq -n --arg c "$CONTENT" '{
    branch: "main",
    message: "add hello.txt",
    content: $c
  }')" \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/contents/hello.txt"
```

Create branch while writing:

```bash
CONTENT=$(printf 'hello\n' | base64)
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d "$(jq -n --arg c "$CONTENT" '{
    branch: "main",
    new_branch: "feat/hello",
    message: "add hello.txt on new branch",
    content: $c
  }')" \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/contents/hello.txt"
```

### Update File

`UpdateFileOptions` fields: `sha` (required) + `content` (required, base64) + `branch`, `new_branch`, `message`, `author`, `committer`, `signoff`, `dates`, **`from_path`** (move/rename from old path to new path in URL).

Updates require the original file `sha`; `GET` first, then `PUT`:

```bash
SHA=$(curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/contents/hello.txt?ref=main" | jq -r '.sha')
CONTENT=$(printf 'hello v2\n' | base64)
curl -fsSL -X PUT -H "Content-Type: application/json" \
  -d "$(jq -n --arg c "$CONTENT" --arg s "$SHA" '{
    branch: "main",
    message: "update hello.txt",
    content: $c,
    sha: $s
  }')" \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/contents/hello.txt"
```

**Rename/move file:** URL is the new path; `from_path` in the body is the old path:

```bash
# Move hello.txt to docs/hello.txt
SHA=$(curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/contents/hello.txt?ref=main" | jq -r '.sha')
CONTENT=$(curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/contents/hello.txt?ref=main" | jq -r '.content')
curl -fsSL -X PUT -H "Content-Type: application/json" \
  -d "$(jq -n --arg c "$CONTENT" --arg s "$SHA" '{
    branch: "main",
    message: "move to docs/",
    content: $c,
    sha: $s,
    from_path: "hello.txt"
  }')" \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/contents/docs/hello.txt"
```

### Delete File

```bash
SHA=$(curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/contents/hello.txt?ref=main" | jq -r '.sha')
curl -fsSL -X DELETE -H "Content-Type: application/json" \
  -d "$(jq -n --arg s "$SHA" '{branch:"main",message:"rm hello.txt",sha:$s}')" \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/contents/hello.txt"
```

## Tag

### List Tags

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/tags?page=1&limit=20" \
  | jq '[.[] | {name, commit_sha: .commit.sha, message}]'
```

### Get Single Tag

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/tags/${TAG}"
```

### Create Tag

`target` is a commit SHA or branch name. A non-empty `message` creates an annotated tag.

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"tag_name":"v1.0.0","target":"main","message":"release 1.0.0"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/tags"
```

### Delete Tag

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/tags/${TAG}"
```

## Release

Release and Tag are different resources, linked via `tag_name`. Deleting a release does not delete the tag by default.

### List Releases

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/releases?page=1&limit=20" \
  | jq '[.[] | {id, tag_name, name, draft, prerelease, published_at}]'
```

Optional filters: `draft=true|false`, `pre-release=true|false` (note the hyphen).

### Latest Release

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/releases/latest"
```

### Single Release

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/releases/${ID}"
```

### Create Release

`target_commitish` is usually a branch name (e.g. `main`) or commit SHA. If `tag_name` does not exist, a tag is created automatically.

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{
    "tag_name": "v1.0.0",
    "target_commitish": "main",
    "name": "v1.0.0",
    "body": "First stable release",
    "draft": false,
    "prerelease": false
  }' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/releases"
```

### Delete Release

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/releases/${ID}"
```

## Tree (Repository Directory Tree)

Fetch directory tree by `tree_sha`. `tree_sha` can be a commit SHA, tag, or branch name. `recursive=true` returns the entire subtree.

**Note:** `git/trees` is one of the few Gitea API endpoints that uses **`per_page` instead of `limit`**. Passing `limit` is ignored; the full page is returned.

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/git/trees/${REF}?recursive=true&page=1&per_page=50" \
  | jq '{truncated, sha, count: (.tree | length), tree: [.tree[] | {path, type, sha, size}]}'
```

`type` is `blob` (file) or `tree` (directory). `truncated=true` means the result was truncated server-side; paginate or narrow the subtree.

## Common Combined Operations

### Commit a File on a New Branch and Open a PR

```bash
# 1. Get default branch
DEF=$(curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}" | jq -r '.default_branch')
# 2. Create branch
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d "$(jq -n --arg b "feat/x" --arg o "$DEF" '{new_branch_name:$b, old_branch_name:$o}')" \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/branches"
# 3. Create file
CONTENT=$(printf 'hi\n' | base64)
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d "$(jq -n --arg c "$CONTENT" '{branch:"feat/x", message:"add hi", content:$c}')" \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/contents/hi.txt"
# 4. Open PR using gitea-pull skill
```

### Compare Changes Between Two Branches

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/compare/main...feat/x"
```

## Permissions / Scope Notes

| Operation | Minimum PAT scope required |
|------|----------------------|
| Read public repository | None (anonymous access works) |
| Read private repo, branches, files | `read:repository` |
| Write files, create/delete branches | `write:repository` |
| Create repository (personal/org) | `write:repository` or `write:organization` |
| Delete repository | `delete:repository` |
| Create/delete release, tag | `write:repository` |
