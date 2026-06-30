---
name: gitea-user
version: 0.0.1
description: "Gitea users and organizations: get the current user, list organizations for the current user, and get the Gitea instance version. Covers /user, /user/orgs, and /version endpoints. Use when you need to confirm Gitea login identity, see which user a token belongs to, list orgs you belong to, or confirm the Gitea version."
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

No token required — the cheapest connectivity test endpoint.

## Permission notes

| Operation | scope |
|-----------|-------|
| `/user`, `/user/orgs` | any token |
| `/users/{u}`, `/orgs/{o}` public info | none (public instance) |
| `/users/{u}/email` and other sensitive fields | `read:user` or the user's own token |
