---
name: gitea-wiki
version: 0.0.1
description: "Gitea Wiki: list, read, create, update, and delete wiki pages; view page revision history. Covers /repos/{owner}/{repo}/wiki endpoints. Use when you need to write docs on Gitea Wiki, view wiki history, or batch-organize wiki pages."
---

# Gitea Wiki

**Read first:** [`../gitea-shared/SKILL.md`](../gitea-shared/SKILL.md) — auth, curl template, error handling.

The curls below omit `-H "Authorization: token ${GITEA_ACCESS_TOKEN}" -H "Accept: application/json"`.

## Key concepts

- A repo's wiki is a separate git repo (same owner, name `<repo>.wiki`), but the API treats it as a sub-resource of the main repo.
- **Page names (`pageName`) use spaces** and must be URL-encoded in paths. For example, "Getting Started" becomes `Getting%20Started`.
- Page content in the API is **base64-encoded** (both reads and writes).

## List wiki pages

`WikiPageMetaData` fields: `title`, `sub_url`, `html_url`, `last_commit` (includes `sha`, `author`, `commiter`, `message`). **There is no `updated_at` field**; the timestamp is in `last_commit.author.date`.

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/wiki/pages?page=1&limit=50" \
  | jq '[.[] | {title, sub_url, last_commit_sha: .last_commit.sha, updated: .last_commit.author.date}]'
```

## Get page content

```bash
PAGE="Getting%20Started"
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/wiki/page/${PAGE}" \
  | jq -r '.content_base64' | base64 -d
```

With metadata:

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/wiki/page/${PAGE}" \
  | jq '{title, sub_url, last_commit_sha: .last_commit.sha, updated: .last_commit.author.date, content: (.content_base64 | @base64d)}'
```

## Page revision history

`WikiCommit` fields: `sha`, `author` (`{name, email, date}`), `commiter` (note swagger spells this field `commiter` with one m), `message`. **There is no `timestamp` field**.

```bash
PAGE="Getting%20Started"
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/wiki/revisions/${PAGE}?page=1" \
  | jq '.commits | [.[] | {sha, message, author: .author.name, date: .author.date}]'
```

## Create page

`CreateWikiPageOptions` body:
- `title` (string, required): page title
- `content_base64` (string, **required and must be base64-encoded**): plain text → base64
- `message` (string, optional): commit message

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d "$(jq -n --arg c "$(printf '# Getting Started\n\nWelcome.\n' | base64)" '{
    title: "Getting Started",
    content_base64: $c,
    message: "init wiki"
  }')" \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/wiki/new"
```

## Update page

`pageName` goes in the URL path. A non-empty `title` renames the page. `content_base64` must be base64.

```bash
PAGE="Getting%20Started"
curl -fsSL -X PATCH -H "Content-Type: application/json" \
  -d "$(jq -n --arg c "$(printf '# Getting Started v2\n' | base64)" '{
    title: "Getting Started",
    content_base64: $c,
    message: "update intro"
  }')" \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/wiki/page/${PAGE}"
```

## Delete page

```bash
PAGE="Getting%20Started"
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/wiki/page/${PAGE}"
```

## Common workflows

### Batch export wiki to local files

```bash
mkdir -p wiki_dump
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/wiki/pages?limit=100" \
  | jq -r '.[].title' \
  | while read TITLE; do
      ENC=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$TITLE")
      curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/wiki/page/${ENC}" \
        | jq -r '.content_base64' | base64 -d > "wiki_dump/${TITLE}.md"
    done
```

## Permission notes

| Operation | scope |
|-----------|-------|
| read wiki | `read:repository` |
| create/update/delete wiki | `write:repository` (and wiki must be enabled on the repo) |
