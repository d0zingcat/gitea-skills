---
name: gitea-package
version: 0.0.2
description: "Gitea Packages registry: list packages (one entry per version), list versions, get version details, get latest, list files, delete versions, and link/unlink packages to repositories (for permission inheritance). Covers /packages/{owner} endpoints; supports alpine/cargo/chef/composer/conan/conda/container/cran/debian/generic/go/helm/maven/npm/nuget/pub/pypi/rpm/rubygems/swift/vagrant and other types. Use when you need to browse packages published by an owner on Gitea Packages, clean up old image versions, inspect package metadata, or associate a package with a repository."
---

# Gitea Packages

**Read first:** [`../gitea-shared/SKILL.md`](../gitea-shared/SKILL.md) — auth, curl template, error handling.

The curls below omit `-H "Authorization: token ${GITEA_ACCESS_TOKEN}" -H "Accept: application/json"`. This document follows the **Gitea 1.26.4** OpenAPI.

## Key concepts

- Packages belong to an **owner** (user or org).
- Packages have a **type** (from the swagger enum): `alpine` / `cargo` / `chef` / `composer` / `conan` / `conda` / `container` / `cran` / `debian` / `generic` / `go` / `helm` / `maven` / `npm` / `nuget` / `pub` / `pypi` / `rpm` / `rubygems` / `swift` / `vagrant`.
- Package names may contain slashes (e.g. container `repo/image`); URL-encode them in URLs (`/` → `%2F`). Examples below use `${NAME_ENC}` for the encoded name.
- `Package` object fields: `id`, `name`, `version`, `type`, `owner`, `repository` (linked repo; may be null), `creator`, `created_at`, `html_url`. **There is no `size` field** — file sizes are on the `/files` endpoint.

## List all packages (one entry per version)

```bash
curl -fsSL "${GITEA_HOST}/api/v1/packages/${OWNER}?type=container&page=1&limit=50" \
  | jq '[.[] | {name, version, type, repo: .repository.full_name, html_url, created_at}]'
```

Optional query parameters:

| Parameter | Meaning |
|-----------|---------|
| `type` | filter by package type |
| `q` | filter by **name (substring)** |
| `page` / `limit` | pagination |

## List all versions of a package

```bash
NAME_ENC=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$NAME")
curl -fsSL "${GITEA_HOST}/api/v1/packages/${OWNER}/${TYPE}/${NAME_ENC}?page=1&limit=50" \
  | jq '[.[] | {version, created_at, html_url}]'
```

## Get latest version

```bash
curl -fsSL "${GITEA_HOST}/api/v1/packages/${OWNER}/${TYPE}/${NAME_ENC}/-/latest" \
  | jq '{name, version, type, created_at}'
```

Note the `-/latest` in the URL (hyphen + slash + latest).

## Get version details

```bash
curl -fsSL "${GITEA_HOST}/api/v1/packages/${OWNER}/${TYPE}/${NAME_ENC}/${VERSION}" \
  | jq '{name, version, type, created_at, repo: .repository.full_name, creator: .creator.login}'
```

## List files in a version

```bash
curl -fsSL "${GITEA_HOST}/api/v1/packages/${OWNER}/${TYPE}/${NAME_ENC}/${VERSION}/files" \
  | jq '[.[] | {id, name, size, sha256}]'
```

`PackageFile` fields: `id`, `name`, `size`, `md5`, `sha1`, `sha256`, `sha512`. Downloading individual files is handled by each package protocol's own client (npm/maven/container each have their own tooling).

## Delete version

**Irreversible. Download links stop working immediately; clients depending on this version will fail.**

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/packages/${OWNER}/${TYPE}/${NAME_ENC}/${VERSION}"
```

## Link package to repository

After linking a package to a repository, repository collaborator permissions are inherited by the package. Commonly used after GitHub Actions / Gitea Actions auto-publish to grant the CI repository read access:

```bash
curl -fsSL -X POST \
  "${GITEA_HOST}/api/v1/packages/${OWNER}/${TYPE}/${NAME_ENC}/-/link/${REPO_NAME}"
```

## Unlink

```bash
curl -fsSL -X POST \
  "${GITEA_HOST}/api/v1/packages/${OWNER}/${TYPE}/${NAME_ENC}/-/unlink"
```

## Common workflows

### Clean up all but the latest 5 versions of an npm package

```bash
NAME_ENC=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "@scope/pkg")
TO_DELETE=$(curl -fsSL "${GITEA_HOST}/api/v1/packages/${OWNER}/npm/${NAME_ENC}?limit=50" \
  | jq -r 'sort_by(.created_at) | reverse | .[5:] | .[].version')
for V in $TO_DELETE; do
  echo "Will delete ${V}"
  # Uncomment and confirm with the user before actually deleting
  # curl -fsSL -X DELETE "${GITEA_HOST}/api/v1/packages/${OWNER}/npm/${NAME_ENC}/${V}"
done
```

### List all container images grouped by name

```bash
curl -fsSL "${GITEA_HOST}/api/v1/packages/${OWNER}?type=container&limit=100" \
  | jq 'group_by(.name) | map({name: .[0].name, versions: [.[].version]})'
```

### Link a newly published image to its repository

```bash
NAME_ENC=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "my-app")
# get latest and confirm it was published
curl -fsSL "${GITEA_HOST}/api/v1/packages/${OWNER}/container/${NAME_ENC}/-/latest" | jq '.version'
# link
curl -fsSL -X POST \
  "${GITEA_HOST}/api/v1/packages/${OWNER}/container/${NAME_ENC}/-/link/my-app"
```

## Permission notes

| Operation | scope |
|-----------|-------|
| read public packages | none |
| read private packages | `read:package` |
| delete package version | `write:package` or owner identity |
| link/unlink package to repository | `write:package` + `write:repository` |
