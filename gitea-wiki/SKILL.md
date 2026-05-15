---
name: gitea-wiki
version: 0.0.1
description: "Gitea Wiki：列出/读取/创建/更新/删除 Wiki 页面、查页面修订历史。涵盖 /repos/{owner}/{repo}/wiki 系列 endpoint。当用户需要在 Gitea Wiki 上写文档、看 wiki 历史、批量整理 wiki 页面时使用。"
---

# Gitea Wiki

**开始前必读 [`../gitea-shared/SKILL.md`](../gitea-shared/SKILL.md)**：认证、curl 模板、错误处理。

下面 curl 都省略 `-H "Authorization: token ${GITEA_ACCESS_TOKEN}" -H "Accept: application/json"`。

## 关键概念

- 一个仓库的 Wiki 是一个独立的 git repo（同 owner，名字 `<repo>.wiki`），但通过 API 操作时把它当成主仓库的子资源。
- **页面名（`pageName`）使用空格分隔**，URL 中需要 URL-encode。比如「Getting Started」对应 `Getting%20Started`。
- 页面内容在 API 中是 **base64 编码**（写入和读取都是）。

## 列出 wiki 页面

`WikiPageMetaData` 字段：`title`、`sub_url`、`html_url`、`last_commit`（含 `sha`、`author`、`commiter`、`message`）。**没有 `updated_at` 字段**，时间在 `last_commit.author.date`。

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/wiki/pages?page=1&limit=50" \
  | jq '[.[] | {title, sub_url, last_commit_sha: .last_commit.sha, updated: .last_commit.author.date}]'
```

## 获取页面内容

```bash
PAGE="Getting%20Started"
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/wiki/page/${PAGE}" \
  | jq -r '.content_base64' | base64 -d
```

含元数据：

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/wiki/page/${PAGE}" \
  | jq '{title, sub_url, last_commit_sha: .last_commit.sha, updated: .last_commit.author.date, content: (.content_base64 | @base64d)}'
```

## 页面修订历史

`WikiCommit` 字段：`sha`、`author`（`{name, email, date}`）、`commiter`（注意 swagger 里这个字段拼成 `commiter` 一个 m）、`message`。**没有 `timestamp` 字段**。

```bash
PAGE="Getting%20Started"
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/wiki/revisions/${PAGE}?page=1" \
  | jq '.commits | [.[] | {sha, message, author: .author.name, date: .author.date}]'
```

## 创建页面

`CreateWikiPageOptions` body：
- `title` (string, 必填)：页面标题
- `content_base64` (string, **必填且必须 base64 编码**)：明文 → base64
- `message` (string, 可选)：commit message

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d "$(jq -n --arg c "$(printf '# Getting Started\n\nWelcome.\n' | base64)" '{
    title: "Getting Started",
    content_base64: $c,
    message: "init wiki"
  }')" \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/wiki/new"
```

## 更新页面

`pageName` 走 URL 路径。`title` 给非空时同时改名。`content_base64` 必须 base64。

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

## 删除页面

```bash
PAGE="Getting%20Started"
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/wiki/page/${PAGE}"
```

## 常见组合

### 批量导出 wiki 到本地

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

## 权限提示

| 操作 | scope |
|------|-------|
| 读 wiki | `read:repository` |
| 创建/更新/删除 wiki | `write:repository`（且仓库 wiki 已启用） |
