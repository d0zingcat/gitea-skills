---
name: gitea-user
version: 1.0.0
description: "Gitea 用户与组织：获取当前用户信息、列出当前用户所属组织、获取 Gitea 实例版本。涵盖 /user、/user/orgs、/version endpoint。当用户需要确认 Gitea 登录身份、查 token 对应哪个用户、列出我加入的 org 或确认 Gitea 版本时使用。"
---

# Gitea User & Version

**开始前必读 [`../gitea-shared/SKILL.md`](../gitea-shared/SKILL.md)**：认证、curl 模板、错误处理。

下面 curl 都省略 `-H "Authorization: token ${GITEA_ACCESS_TOKEN}" -H "Accept: application/json"`。

## 当前用户

```bash
curl -fsSL "${GITEA_HOST}/api/v1/user" \
  | jq '{id, login, full_name, email, is_admin, created}'
```

也是验证 `GITEA_ACCESS_TOKEN` 是否有效的最快方式。401 即 token 失效。

## 列出当前用户所属组织

```bash
curl -fsSL "${GITEA_HOST}/api/v1/user/orgs?page=1&limit=50" \
  | jq '[.[] | {id, username, full_name, visibility}]'
```

## 看任意用户

```bash
curl -fsSL "${GITEA_HOST}/api/v1/users/${USERNAME}" \
  | jq '{id, login, full_name, created}'
```

## 看任意组织

```bash
curl -fsSL "${GITEA_HOST}/api/v1/orgs/${ORG}" \
  | jq '{id, username, full_name, description, visibility, website}'
```

## Gitea 实例版本

```bash
curl -fsSL "${GITEA_HOST}/api/v1/version" \
  | jq '.version'
```

无需 token，最便宜的连通性测试 endpoint。

## 权限提示

| 操作 | scope |
|------|-------|
| `/user`、`/user/orgs` | 任意 token |
| `/users/{u}`、`/orgs/{o}` 公开信息 | 无（公开实例） |
| `/users/{u}/email` 等敏感字段 | `read:user` 或本人 token |
