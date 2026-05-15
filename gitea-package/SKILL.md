---
name: gitea-package
version: 0.0.1
description: "Gitea Packages 注册中心：列出包（每个版本一条）、列版本、看版本详情、看 latest、列文件、删除版本、把包绑定/解绑到仓库（用于权限继承）。涵盖 /packages/{owner} 系列 endpoint，支持 alpine/cargo/chef/composer/conan/conda/container/cran/debian/generic/go/helm/maven/npm/nuget/pub/pypi/rpm/rubygems/swift/vagrant 等类型。当用户需要在 Gitea Packages 上看某 owner 发布的包、清理旧版本镜像、查包元数据、把包关联到某个仓库时使用。"
---

# Gitea Packages

**开始前必读 [`../gitea-shared/SKILL.md`](../gitea-shared/SKILL.md)**：认证、curl 模板、错误处理。

下面 curl 都省略 `-H "Authorization: token ${GITEA_ACCESS_TOKEN}" -H "Accept: application/json"`。本文以 **Gitea 1.24.6** 的 OpenAPI 为准。

## 关键概念

- 包绑定到一个 **owner**（user 或 org）。
- 包有 **type**（来自 swagger 真实 enum）：`alpine` / `cargo` / `chef` / `composer` / `conan` / `conda` / `container` / `cran` / `debian` / `generic` / `go` / `helm` / `maven` / `npm` / `nuget` / `pub` / `pypi` / `rpm` / `rubygems` / `swift` / `vagrant`。
- 包名可能包含斜杠（如 container `repo/image`），URL 中需 URL-encode（`/` → `%2F`）。下文示例用 `${NAME_ENC}` 代表已 encode 后的名字。
- `Package` 对象字段：`id`、`name`、`version`、`type`、`owner`、`repository`（关联仓库；可能为 null）、`creator`、`created_at`、`html_url`。**没有 `size` 字段**——文件大小要去 `/files` endpoint 看。

## 列出所有包（每个版本一条）

```bash
curl -fsSL "${GITEA_HOST}/api/v1/packages/${OWNER}?type=container&page=1&limit=50" \
  | jq '[.[] | {name, version, type, repo: .repository.full_name, html_url, created_at}]'
```

可选 query：

| 参数 | 含义 |
|------|------|
| `type` | 过滤包类型 |
| `q` | 按 **name 过滤（substring）** |
| `page` / `limit` | 分页 |

## 列出某个包的所有版本

```bash
NAME_ENC=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$NAME")
curl -fsSL "${GITEA_HOST}/api/v1/packages/${OWNER}/${TYPE}/${NAME_ENC}?page=1&limit=50" \
  | jq '[.[] | {version, created_at, html_url}]'
```

## 看 latest 版本

```bash
curl -fsSL "${GITEA_HOST}/api/v1/packages/${OWNER}/${TYPE}/${NAME_ENC}/-/latest" \
  | jq '{name, version, type, created_at}'
```

注意 URL 里的 `-/latest`（连字符 + 斜杠 + latest）。

## 看版本详情

```bash
curl -fsSL "${GITEA_HOST}/api/v1/packages/${OWNER}/${TYPE}/${NAME_ENC}/${VERSION}" \
  | jq '{name, version, type, created_at, repo: .repository.full_name, creator: .creator.login}'
```

## 列出版本下的文件

```bash
curl -fsSL "${GITEA_HOST}/api/v1/packages/${OWNER}/${TYPE}/${NAME_ENC}/${VERSION}/files" \
  | jq '[.[] | {id, name, size, sha256}]'
```

`PackageFile` 字段：`id`、`name`、`size`、`md5`、`sha1`、`sha256`、`sha512`。下载具体文件由各 package 协议自己决定（npm/maven/容器都有自己的 client）。

## 删除版本

**不可逆操作。删除后下载链接立刻失效，依赖此版本的 client 会失败。**

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/packages/${OWNER}/${TYPE}/${NAME_ENC}/${VERSION}"
```

## 把包绑定到仓库

把包关联到一个仓库后，仓库的协作者权限会继承到包上。常用于 GitHub Actions / Gitea Actions 自动 publish 后给 CI 仓库读权限：

```bash
curl -fsSL -X POST \
  "${GITEA_HOST}/api/v1/packages/${OWNER}/${TYPE}/${NAME_ENC}/-/link/${REPO_NAME}"
```

## 解绑

```bash
curl -fsSL -X POST \
  "${GITEA_HOST}/api/v1/packages/${OWNER}/${TYPE}/${NAME_ENC}/-/unlink"
```

## 常见组合

### 清理一个 npm 包除最新 5 个之外的所有版本

```bash
NAME_ENC=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "@scope/pkg")
TO_DELETE=$(curl -fsSL "${GITEA_HOST}/api/v1/packages/${OWNER}/npm/${NAME_ENC}?limit=50" \
  | jq -r 'sort_by(.created_at) | reverse | .[5:] | .[].version')
for V in $TO_DELETE; do
  echo "Will delete ${V}"
  # 实际删除前请取消注释并和用户确认
  # curl -fsSL -X DELETE "${GITEA_HOST}/api/v1/packages/${OWNER}/npm/${NAME_ENC}/${V}"
done
```

### 列出所有 container 镜像并按 name 分组

```bash
curl -fsSL "${GITEA_HOST}/api/v1/packages/${OWNER}?type=container&limit=100" \
  | jq 'group_by(.name) | map({name: .[0].name, versions: [.[].version]})'
```

### 把新发布的镜像绑到对应仓库

```bash
NAME_ENC=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "my-app")
# 拿 latest，确认已发布
curl -fsSL "${GITEA_HOST}/api/v1/packages/${OWNER}/container/${NAME_ENC}/-/latest" | jq '.version'
# 绑定
curl -fsSL -X POST \
  "${GITEA_HOST}/api/v1/packages/${OWNER}/container/${NAME_ENC}/-/link/my-app"
```

## 权限提示

| 操作 | scope |
|------|-------|
| 读公开包 | 无 |
| 读私有包 | `read:package` |
| 删除包版本 | `write:package` 或 owner 身份 |
| 绑定/解绑包到仓库 | `write:package` + `write:repository` |
