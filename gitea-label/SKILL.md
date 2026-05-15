---
name: gitea-label
version: 0.0.1
description: "Gitea Label 管理：仓库级和组织级 label 的列出/创建/编辑/删除。涵盖 /repos/{owner}/{repo}/labels 与 /orgs/{org}/labels endpoint。当用户需要在 Gitea 仓库或组织里管理 issue/PR 标签、批量创建 label、给标签改色或归档时使用。"
---

# Gitea Label

**开始前必读 [`../gitea-shared/SKILL.md`](../gitea-shared/SKILL.md)**：认证、curl 模板、错误处理。

下面 curl 都省略 `-H "Authorization: token ${GITEA_ACCESS_TOKEN}" -H "Accept: application/json"`。

## 关键概念

- Gitea 有两类 label：
  - **仓库 label**：归属单个 repo
  - **组织 label**：归属一个 org，组织下所有仓库可共用
- Label 用 **数字 ID** 在 issue / PR 中关联（不是 name）。给 issue 打标签时拿不到 ID 就先 list。
- 颜色字段是 6 位 hex，**带或不带 `#` 都接受**（swagger example 是 `#00aabb`，但实测两种都能进）。

## 仓库级 Label

### 列出

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/labels?page=1&limit=50" \
  | jq '[.[] | {id, name, color, description, is_archived}]'
```

### 获取单个

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/labels/${LABEL_ID}"
```

### 创建

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

`exclusive` 仅对 scoped label 生效（同一前缀只能选一个）。

### 编辑

`PATCH` 只更新提供的字段。

```bash
curl -fsSL -X PATCH -H "Content-Type: application/json" \
  -d '{"color":"#d73a4a","description":"Bug confirmed"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/labels/${LABEL_ID}"
```

可改：`name`、`color`、`description`、`exclusive`、`is_archived`。

### 删除

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/labels/${LABEL_ID}"
```

## 组织级 Label

把 `repos/{owner}/{repo}` 换成 `orgs/{org}`：

```bash
# 列出
curl -fsSL "${GITEA_HOST}/api/v1/orgs/${ORG}/labels?page=1&limit=50"
# 创建
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"name":"good first issue","color":"7057ff","description":"For new contributors"}' \
  "${GITEA_HOST}/api/v1/orgs/${ORG}/labels"
# 编辑
curl -fsSL -X PATCH -H "Content-Type: application/json" \
  -d '{"description":"Beginner-friendly"}' \
  "${GITEA_HOST}/api/v1/orgs/${ORG}/labels/${LABEL_ID}"
# 删除
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/orgs/${ORG}/labels/${LABEL_ID}"
```

## 批量初始化常用 label

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

## 权限提示

| 操作 | scope |
|------|-------|
| 读仓库 label | `read:repository` |
| 写仓库 label | `write:repository` |
| 读/写组织 label | `read:organization` / `write:organization`（且为 org owner/admin） |
