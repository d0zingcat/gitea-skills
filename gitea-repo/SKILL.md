---
name: gitea-repo
version: 1.0.0
description: "Gitea 仓库操作：仓库创建/Fork/列表、分支管理、Commit 查询、文件读写、Tag 与 Release、目录树。涵盖 repos/branches/commits/contents/releases/tags/git/trees 系列 REST endpoint。当用户需要在 Gitea 上 list/create repo、fork、新建/删除 branch、读取或编辑文件、查 commit、打 tag、发 release、看仓库目录结构时使用。"
---

# Gitea 仓库 (repo)

**开始前必读 [`../gitea-shared/SKILL.md`](../gitea-shared/SKILL.md)**：`GITEA_HOST` / `GITEA_ACCESS_TOKEN`、curl 模板、错误码、安全规则。

下文所有命令省略了：

```bash
-H "Authorization: token ${GITEA_ACCESS_TOKEN}"
-H "Accept: application/json"
```

请补齐到每条 curl。

## 资源关系

```
Repo (owner/repo)
├── Branch          (refs/heads/<branch>)
│   └── Commit      (sha)
│       └── File    (path@ref)
├── Tag             (tag_name)
└── Release         (id, 关联 tag_name)
```

## Repository

### 列出当前用户仓库

```bash
curl -fsSL "${GITEA_HOST}/api/v1/user/repos?page=1&limit=50" \
  | jq '[.[] | {full_name, private, default_branch, description}]'
```

### 列出组织仓库

```bash
curl -fsSL "${GITEA_HOST}/api/v1/orgs/${ORG}/repos?page=1&limit=100" \
  | jq '[.[] | {full_name, private, default_branch}]'
```

### 创建仓库

个人下：`POST /user/repos`；组织下：`POST /orgs/{org}/repos`。

```bash
# 个人仓库
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

# 组织仓库
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"name":"my-repo","auto_init":true}' \
  "${GITEA_HOST}/api/v1/orgs/${ORG}/repos"
```

可选 body 字段：`description`、`private`、`issue_labels`（label 集合名）、`auto_init`、`template`、`gitignores`、`license`、`readme`、`default_branch`、`trust_model`（`default`/`collaborator`/`committer`/`collaboratorcommitter`）、`object_format_name`（`sha1`/`sha256`）。

### Fork 仓库

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"organization":"my-org","name":"forked-name"}' \
  "${GITEA_HOST}/api/v1/repos/${USER}/${REPO}/forks"
```

`organization` 不传则 fork 到当前用户名下；`name` 不传则同名。

## Branch

### 列出分支

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/branches?page=1&limit=50" \
  | jq '[.[] | {name, commit_sha: .commit.id, protected}]'
```

### 创建分支

`CreateBranchRepoOption` body：

| 字段 | 必填 | 说明 |
|------|------|------|
| `new_branch_name` | 是 | 新分支名 |
| `old_ref_name` | 否 | source ref，可以是 **branch / tag / commit SHA**。不传则用仓库默认分支。 |
| `old_branch_name` | 否 | **已 deprecated**，仅作老版本兼容；新代码用 `old_ref_name` |

```bash
# 从 main 分支建新分支
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"new_branch_name":"feature/x","old_ref_name":"main"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/branches"

# 从某个 tag 建分支
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"new_branch_name":"hotfix/v1.0","old_ref_name":"v1.0.0"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/branches"

# 从某个 commit 建分支
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"new_branch_name":"backport","old_ref_name":"abc123def"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/branches"
```

### 删除分支

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/branches/${BRANCH}"
```

## Commit

### 列出仓库提交

可选 `sha`（起点 SHA 或分支名）、`path`（只看影响该路径的提交）。

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/commits?sha=main&page=1&limit=20" \
  | jq '[.[] | {sha, msg: .commit.message, author: .commit.author.name, date: .commit.author.date}]'
```

### 单个提交详情

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/commits/${SHA}" \
  | jq '{sha, message: .commit.message, files: [.files[].filename]}'
```

## File（文件读写）

`path` 在 URL 中**不要 URL-encode 斜杠**，直接拼。

### 读取文件内容

`ref` 可以是分支名、tag、SHA。

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/contents/${PATH}?ref=${REF}" \
  | jq -r '.content' | base64 -d
```

如果想保留 base64 元信息：

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/contents/${PATH}?ref=${REF}" \
  | jq '{name, sha, size, encoding, html_url}'
```

### 列目录条目

`path` 给目录路径，响应是数组：

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/contents/${DIR}?ref=${REF}" \
  | jq '[.[] | {name, type, size, sha}]'
```

`type` 为 `file` / `dir` / `symlink` / `submodule`。

### 创建文件

`CreateFileOptions` body：

| 字段 | 必填 | 说明 |
|------|------|------|
| `content` | 是 | **必须 base64 编码** |
| `branch` | 否 | 目标分支，不传用仓库默认分支 |
| `new_branch` | 否 | 给值时会先从 `branch` 建出这个新分支再提交 |
| `message` | 否 | commit message，不传给个默认值 |
| `author` / `committer` | 否 | `Identity` 类型 `{name, email}`，覆盖提交者身份 |
| `signoff` | 否 | `true` 时自动加 `Signed-off-by` 行 |
| `dates` | 否 | `CommitDateOptions`，自定义 commit 时间 |

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

边写边建分支：

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

### 更新文件

`UpdateFileOptions` 字段：`sha`（必填）+ `content`（必填，base64）+ `branch`、`new_branch`、`message`、`author`、`committer`、`signoff`、`dates`、**`from_path`**（移动/重命名旧路径到 URL 中的新路径）。

更新必须带原文件 `sha`，先 `GET` 拿，再 `PUT`：

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

**重命名/移动文件**：URL 是新路径，body 里 `from_path` 是旧路径：

```bash
# 把 hello.txt 移到 docs/hello.txt
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

### 删除文件

```bash
SHA=$(curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/contents/hello.txt?ref=main" | jq -r '.sha')
curl -fsSL -X DELETE -H "Content-Type: application/json" \
  -d "$(jq -n --arg s "$SHA" '{branch:"main",message:"rm hello.txt",sha:$s}')" \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/contents/hello.txt"
```

## Tag

### 列出 tag

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/tags?page=1&limit=20" \
  | jq '[.[] | {name, commit_sha: .commit.sha, message}]'
```

### 获取单个 tag

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/tags/${TAG}"
```

### 创建 tag

`target` 是 commit SHA 或分支名。`message` 给非空则创建 annotated tag。

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"tag_name":"v1.0.0","target":"main","message":"release 1.0.0"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/tags"
```

### 删除 tag

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/tags/${TAG}"
```

## Release

Release 与 Tag 是不同资源，但通过 `tag_name` 关联。删除 release 默认不删 tag。

### 列出 release

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/releases?page=1&limit=20" \
  | jq '[.[] | {id, tag_name, name, draft, prerelease, published_at}]'
```

可选过滤：`draft=true|false`、`pre-release=true|false`（注意是连字符）。

### 最新 release

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/releases/latest"
```

### 单个 release

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/releases/${ID}"
```

### 创建 release

`target_commitish` 通常给分支名（如 `main`）或 commit SHA。`tag_name` 不存在会自动创建 tag。

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

### 删除 release

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/releases/${ID}"
```

## Tree（仓库目录树）

按 `tree_sha` 拉取目录树。`tree_sha` 可以是 commit SHA、tag 或分支名。`recursive=true` 返回整个子树。

**注意**：`git/trees` 是 Gitea API 里少数**用 `per_page` 而不是 `limit`** 的 endpoint。传 `limit` 会被忽略，返回完整一页。

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/git/trees/${REF}?recursive=true&page=1&per_page=50" \
  | jq '{truncated, sha, count: (.tree | length), tree: [.tree[] | {path, type, sha, size}]}'
```

`type` 为 `blob`（文件）或 `tree`（目录）。`truncated=true` 表示数量被服务端截断，需要分页或缩小子树。

## 常见组合操作

### 在新分支提交一个文件并发起 PR

```bash
# 1. 拿默认分支
DEF=$(curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}" | jq -r '.default_branch')
# 2. 建分支
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d "$(jq -n --arg b "feat/x" --arg o "$DEF" '{new_branch_name:$b, old_branch_name:$o}')" \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/branches"
# 3. 创建文件
CONTENT=$(printf 'hi\n' | base64)
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d "$(jq -n --arg c "$CONTENT" '{branch:"feat/x", message:"add hi", content:$c}')" \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/contents/hi.txt"
# 4. 用 gitea-pull skill 发起 PR
```

### 比较两个分支变化

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/compare/main...feat/x"
```

## 权限/scope 提示

| 操作 | 至少需要的 PAT scope |
|------|----------------------|
| 读公开仓库 | 无（甚至匿名也行） |
| 读私有仓库、分支、文件 | `read:repository` |
| 写文件、创建分支、删除分支 | `write:repository` |
| 创建仓库（个人/组织） | `write:repository` 或 `write:organization` |
| 删除仓库 | `delete:repository` |
| 创建/删除 release、tag | `write:repository` |
