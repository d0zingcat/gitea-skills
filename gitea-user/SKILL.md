---
name: gitea-user
version: 0.0.3
description: "Gitea users and organizations: get the current user, list organizations for the current user, inspect the current token's scopes, and get the Gitea instance version. Covers /user, /user/orgs, /token, and /version endpoints. Use when you need to confirm Gitea login identity, see which user a token belongs to, list orgs you belong to, check which scopes the current token has, or confirm the Gitea version."
---

# Gitea User & Version

**Read first:** [`../gitea-shared/SKILL.md`](../gitea-shared/SKILL.md) — auth, curl template, error handling.

The curls below omit `-H "Authorization: token ${GITEA_ACCESS_TOKEN}" -H "Accept: application/json"`.

## Current user

```bash
curl -fsSL "${GITEA_HOST}/api/v1/user" \
  | jq '{id, login, full_name, email, is_admin, created}'
```

Also the fastest way to verify that `GITEA_ACCESS_TOKEN` is valid. 401 means the token is invalid.

## List organizations for the current user

```bash
curl -fsSL "${GITEA_HOST}/api/v1/user/orgs?page=1&limit=50" \
  | jq '[.[] | {id, username, full_name, visibility}]'
```

## View any user

```bash
curl -fsSL "${GITEA_HOST}/api/v1/users/${USERNAME}" \
  | jq '{id, login, full_name, created}'
```

## View any organization

```bash
curl -fsSL "${GITEA_HOST}/api/v1/orgs/${ORG}" \
  | jq '{id, username, full_name, description, visibility, website}'
```

## Gitea instance version

```bash
curl -fsSL "${GITEA_HOST}/api/v1/version" \
  | jq '.version'
```

Since 28.0 the version has no `1.` prefix: `28.2.0` follows `1.27.x`. Compare major/minor as integers (see gitea-shared "Version compatibility"), never as strings or by assuming a `1.` major.

No token required — the cheapest connectivity test endpoint.

## Current token (1.27+)

Check which scopes the token in use has, before an operation that might 403:

```bash
curl -fsSL "${GITEA_HOST}/api/v1/token" \
  | jq '{name, scopes, last_used_at, user: .user.login}'
```

Never print `sha1` or `token_last_eight`. `DELETE /api/v1/token` revokes the token in use: only on explicit user request, and the profile must then be updated with a new PAT.

## Permission notes

| Operation | scope |
|-----------|-------|
| `/user`, `/user/orgs` | any token |
| `/users/{u}`, `/orgs/{o}` public info | none (public instance) |
| `/users/{u}/email` and other sensitive fields | `read:user` or the user's own token |
