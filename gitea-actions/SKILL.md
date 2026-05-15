---
name: gitea-actions
version: 1.0.0
description: "Gitea Actions：列工作流、列运行（runs/tasks）、dispatch workflow、读 job 日志、读写仓库/组织/用户级 secrets 与 variables、管理 artifacts 与 runners、enable/disable workflow。涵盖 /repos/{o}/{r}/actions、/orgs/{org}/actions、/user/actions、/admin/actions 系列 endpoint。当用户需要看 CI 跑得怎么样、手动 dispatch workflow、查 build 日志、配 CI 用的 token 或环境变量、管理 self-hosted runner、下载 build 产物时使用。"
---

# Gitea Actions

**开始前必读 [`../gitea-shared/SKILL.md`](../gitea-shared/SKILL.md)**：认证、curl 模板、错误处理、安全规则。

下面 curl 都省略 `-H "Authorization: token ${GITEA_ACCESS_TOKEN}" -H "Accept: application/json"`。本文以 **Gitea 1.24.6** 的 OpenAPI 为准（`${GITEA_HOST}/swagger.v1.json`）。

## 关键概念

```
Workflow (.gitea/workflows/*.yml, 由 workflow_id=文件名 标识)
├── Run                                ← /actions/tasks 列出（注意：路径用 tasks，不是 runs）
│   └── Job (job_id)                   ← API 没有 list jobs；job_id 从 web UI 或事件回调拿
│       └── Log                        ← /actions/jobs/{job_id}/logs
└── Artifact (artifact_id)             ← /actions/artifacts，可下载 zip

Repo / Org / User / Admin 都各自有 runners 和（部分场景）secrets / variables。
```

- `workflow_id` 通常用 workflow 文件名（如 `ci.yml`），少数 endpoint 也接受数值 ID
- Secret 写后**不可读回值**（只能列名字）；Variable 明文可读
- **重要**：1.24.6 的 Actions API 不提供单 run 详情、cancel run、rerun run、list jobs。这些是 swagger 真实缺失，要做这些操作只能引导用户去 Web UI

## 一览：1.24.6 真实可用的 Actions endpoint

| 域 | endpoint | 方法 |
|----|----------|------|
| Workflows | `/repos/{o}/{r}/actions/workflows` | GET |
| | `/repos/{o}/{r}/actions/workflows/{workflow_id}` | GET |
| | `/repos/{o}/{r}/actions/workflows/{workflow_id}/dispatches` | POST |
| | `/repos/{o}/{r}/actions/workflows/{workflow_id}/enable` | PUT |
| | `/repos/{o}/{r}/actions/workflows/{workflow_id}/disable` | PUT |
| Runs (Tasks) | `/repos/{o}/{r}/actions/tasks` | GET |
| Job logs | `/repos/{o}/{r}/actions/jobs/{job_id}/logs` | GET |
| Artifacts | `/repos/{o}/{r}/actions/artifacts` | GET |
| | `/repos/{o}/{r}/actions/artifacts/{artifact_id}` | GET, DELETE |
| | `/repos/{o}/{r}/actions/artifacts/{artifact_id}/zip` | GET (302 → blob) |
| | `/repos/{o}/{r}/actions/runs/{run}/artifacts` | GET |
| Secrets (Repo) | `/repos/{o}/{r}/actions/secrets` | GET |
| | `/repos/{o}/{r}/actions/secrets/{name}` | PUT, DELETE |
| Variables (Repo) | `/repos/{o}/{r}/actions/variables` | GET |
| | `/repos/{o}/{r}/actions/variables/{name}` | GET, POST, PUT, DELETE |
| Runners (Repo) | `/repos/{o}/{r}/actions/runners` | GET |
| | `/repos/{o}/{r}/actions/runners/{runner_id}` | GET, DELETE |
| | `/repos/{o}/{r}/actions/runners/registration-token` | GET, POST |
| Org level | `/orgs/{org}/actions/secrets`、`/variables`、`/runners` | 同上模式 |
| User level | `/user/actions/secrets/{name}` (PUT/DELETE) | 个人 secret 没 list |
| | `/user/actions/variables`、`/{name}` | 完整 |
| | `/user/actions/runners`、`/{runner_id}`、`/registration-token` | 完整 |
| Admin | `/admin/actions/runners`、`/{runner_id}`、`/registration-token` | 完整 |

**API 缺失（1.24.6 上不可用，需引导用户用 Web UI）**：单 run 详情、列 jobs、cancel run、rerun run、retry single job。

## Workflows

### 列出 workflows

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/workflows?page=1&limit=50" \
  | jq '.workflows | [.[] | {id, name, path, state}]'
```

### 获取 workflow 定义

`workflow_id` 用文件名（推荐）或数值 ID：

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/workflows/ci.yml"
```

### Enable / Disable workflow

```bash
# 禁用
curl -fsSL -X PUT \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/workflows/ci.yml/disable"
# 启用
curl -fsSL -X PUT \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/workflows/ci.yml/enable"
```

成功返回 **204 No Content**。

### Dispatch workflow

需要 workflow 里声明 `on: workflow_dispatch`。**这是真实执行 CI 的操作**，调用前必须和用户确认意图，包括 `ref` 和 `inputs`。

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{
    "ref": "main",
    "inputs": {"environment":"prod","version":"1.2.3"}
  }' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/workflows/ci.yml/dispatches"
```

成功返回 **204 No Content**（无 body）。失败常见：
- 422：`ref` 不存在 / workflow 没声明 `workflow_dispatch` / `inputs` 不符 schema
- 404：workflow 文件不存在或无权访问
- 403：scope 不足（需 `write:repository`）

> **路由说明**：1.21+ 唯一规范路径是 `/dispatches`（复数）。极老版本的 `/dispatch` 单数已不再支持。

## Workflow Runs（Tasks）

### 列出 runs

**1.24.6 的列 runs endpoint 是 `/actions/tasks`**，路径名是历史遗留（响应字段还是 `workflow_runs`）：

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/tasks?page=1&limit=50" \
  | jq '.workflow_runs | [.[] | {id, run_number, name, event, status, head_branch, head_sha: .head_sha[0:8], created_at}]'
```

`ActionTask` 字段（来自 swagger）：`id`、`name`、`head_branch`、`head_sha`、`run_number`、`event`、`display_title`、`status`、`workflow_id`、`url`、`created_at`、`updated_at`、`run_started_at`。

注意 swagger 中 **没有 `conclusion` 字段**——`status` 已经包含了 `success` / `failure` / `cancelled` / `skipped` 这些终态值（不是只放在 conclusion 里）。

筛某状态：

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/tasks?limit=100" \
  | jq '.workflow_runs | map(select(.status=="failure"))'
```

### 单 run 详情

**1.24.6 swagger 没有 `GET /actions/runs/{id}` 或 `/actions/tasks/{id}`**。退路：

- 在 list 里 jq 过滤：`jq '.workflow_runs[] | select(.id == 493976)'`
- 用浏览器看：`${GITEA_HOST}/${OWNER}/${REPO}/actions/runs/${RUN_NUMBER}`（注意是 `run_number`，不是 `id`）

### Cancel / Rerun

**1.24.6 swagger 没有这两个 endpoint**。引导用户在 Web UI 操作：

```
${GITEA_HOST}/${OWNER}/${REPO}/actions/runs/${RUN_NUMBER}
```

## Job 日志

### 看 job 日志

```bash
curl -fsSL -o "${OUT}.log" \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/jobs/${JOB_ID}/logs"
```

注意 endpoint 是 **`logs` 复数**。日志是纯文本。

### 怎么拿到 `job_id`？

**1.24.6 没有 list jobs 的 API**。两个常见来源：

1. **Webhook / 事件回调**：如果你在监听 Gitea 的 `workflow_job` event，事件 payload 里有 `id`
2. **Web UI**：浏览器打开 `${GITEA_HOST}/${OWNER}/${REPO}/actions/runs/${RUN_NUMBER}`，每个 job 的 URL 是 `/actions/runs/${RUN_NUMBER}/jobs/${JOB_INDEX}`，但**这里的 `JOB_INDEX` 是 0 起的下标，不是 API 的 `job_id`**。要拿真实 `job_id` 需要从 web 页 dev tools 看 XHR，或者在 webhook 接收处记录

实际工程做法：让 CI 在 step 里通过环境变量记录 `${{ github.run_id }}` 等，或者把日志手动 echo 到 artifact 里上传，下载 artifact 替代直接读 job log。

## Artifacts

### 列出仓库 artifacts

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/artifacts?page=1&limit=30&name=my-artifact" \
  | jq '.artifacts | [.[] | {id, name, size_in_bytes, expired, expires_at, archive_download_url, run_id: .workflow_run.id}]'
```

可选 `name=<exact>` 按名字精确过滤。响应包装在 `{artifacts:[...], total_count}` 里。

`ActionArtifact` 字段：`id`、`name`、`size_in_bytes`、`url`、`archive_download_url`、`expired`、`expires_at`、`created_at`、`updated_at`、`workflow_run.{id, head_sha, repository_id}`。

### 列出某次 run 的 artifacts

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/runs/${RUN_ID}/artifacts" \
  | jq '.artifacts | [.[] | {id, name, size_in_bytes, expired}]'
```

注意这条 endpoint 中 `run` 是 `run_id`（数值），从 `/actions/tasks` 列出来的 `.workflow_runs[].id`。

### 获取单个 artifact 元数据

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/artifacts/${ARTIFACT_ID}" \
  | jq '{name, size_in_bytes, expired, archive_download_url}'
```

### 下载 artifact zip

```bash
# 直接跟随 302 拿到 blob
curl -fsSL -o "${OUT}.zip" \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/artifacts/${ARTIFACT_ID}/zip"
```

或者直接用 list 响应里 `archive_download_url` 字段。

### 删除 artifact

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/artifacts/${ARTIFACT_ID}"
```

**不可逆**，操作前确认用户意图。

## Secrets

`PUT` 是 upsert 语义，写入即覆盖。Secret 值**不可回读**，list 只返回 metadata。

### 列出 repo secrets

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/secrets?page=1&limit=50" \
  | jq '[.[] | {name, description, created_at}]'
```

### 创建/更新 repo secret

`CreateOrUpdateSecretOption` body：
- `data` (string, **必填**)：值
- `description` (string, 可选)：备注

```bash
curl -fsSL -X PUT -H "Content-Type: application/json" \
  -d '{"data":"my-secret-value","description":"Used by deploy step"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/secrets/${NAME}"
```

成功返回 **204 No Content**。**写之前必须和用户确认这会覆盖**已有值。

### 删除 repo secret

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/secrets/${NAME}"
```

### 组织级 secret

把 `repos/{owner}/{repo}` 换成 `orgs/{org}`，路径其余一致：

```bash
curl -fsSL "${GITEA_HOST}/api/v1/orgs/${ORG}/actions/secrets"
curl -fsSL -X PUT -H "Content-Type: application/json" \
  -d '{"data":"v","description":""}' \
  "${GITEA_HOST}/api/v1/orgs/${ORG}/actions/secrets/${NAME}"
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/orgs/${ORG}/actions/secrets/${NAME}"
```

### 用户级 secret

```bash
# 创建/更新（个人 secret）
curl -fsSL -X PUT -H "Content-Type: application/json" \
  -d '{"data":"v"}' \
  "${GITEA_HOST}/api/v1/user/actions/secrets/${NAME}"
# 删除
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/user/actions/secrets/${NAME}"
```

注意：**个人级 secret 没有 list endpoint**——只能记着名字单个查。

## Variables

明文可读 key-value。

### 列出 repo variables

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/variables?page=1&limit=50" \
  | jq '[.[] | {name, data, description}]'
```

注意字段是 **`data`** 不是 `value`。

### 获取单个

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/variables/${NAME}"
```

### 创建变量

`CreateVariableOption` body：
- `value` (**必填**)：值
- `description` (可选)：备注

`POST` 用于**首次创建**，已存在会 422。

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"value":"production","description":"deploy target env"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/variables/${NAME}"
```

### 更新变量

`UpdateVariableOption` body：
- `value` (**必填**)：新值
- `description` (可选)：新备注
- `name` (可选)：**重命名**！URL 中的旧名字会被改成 body 里的新名字

```bash
# 单纯改值
curl -fsSL -X PUT -H "Content-Type: application/json" \
  -d '{"value":"staging"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/variables/${NAME}"

# 同时改名
curl -fsSL -X PUT -H "Content-Type: application/json" \
  -d '{"name":"NEW_NAME","value":"staging"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/variables/${OLD_NAME}"
```

不确定是否存在就先 GET，404 就 POST，200 就 PUT。

### 删除变量

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/variables/${NAME}"
```

### 组织级 variable

| 操作 | endpoint |
|------|----------|
| 列出 | `GET /orgs/${ORG}/actions/variables` |
| 单个 | `GET /orgs/${ORG}/actions/variables/${NAME}` |
| 创建 | `POST /orgs/${ORG}/actions/variables/${NAME}` |
| 更新 | `PUT  /orgs/${ORG}/actions/variables/${NAME}` |
| 删除 | `DELETE /orgs/${ORG}/actions/variables/${NAME}` |

### 用户级 variable

| 操作 | endpoint |
|------|----------|
| 列出 | `GET /user/actions/variables` |
| 单个 | `GET /user/actions/variables/${NAME}` |
| 创建 | `POST /user/actions/variables/${NAME}` |
| 更新 | `PUT  /user/actions/variables/${NAME}` |
| 删除 | `DELETE /user/actions/variables/${NAME}` |

## Runners（self-hosted）

`ActionRunner` 字段：`id`、`name`、`status`（`offline`/`online`/`idle`/`active`）、`busy`、`ephemeral`、`labels[]`。

### 列出 repo runners

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/runners?limit=50" \
  | jq '.runners | [.[] | {id, name, status, busy, ephemeral, labels: [.labels[].name]}]'
```

### 单 runner / 删除

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/runners/${RUNNER_ID}"
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/runners/${RUNNER_ID}"
```

### Runner 注册 token

注册新 runner 之前需要拿一次性 token：

```bash
# 读当前 token（GET）
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/runners/registration-token" \
  | jq -r '.token'

# 重新生成（POST，旧 token 失效）
curl -fsSL -X POST \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/runners/registration-token" \
  | jq -r '.token'
```

拿到 token 后，在 runner 主机上：

```bash
./act_runner register --no-interactive \
  --instance "${GITEA_HOST}" \
  --token "${TOKEN}" \
  --name "my-runner" \
  --labels "self-hosted,linux,x64"
```

### 组织 / 用户 / Admin runner

把 `repos/{owner}/{repo}` 换成相应前缀：

| Scope | 前缀 |
|-------|------|
| Repo | `/repos/${OWNER}/${REPO}/actions/runners` |
| Org | `/orgs/${ORG}/actions/runners` |
| User | `/user/actions/runners` |
| Admin（全实例） | `/admin/actions/runners` |

`/admin/actions/runners` 需要管理员权限，作用是看/删全实例 runner（包括别人的）。

## 常见组合

### 触发 workflow 并跟踪 status

```bash
# 1. 触发（成功 204 No Content）
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"ref":"main","inputs":{"environment":"staging"}}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/workflows/deploy.yml/dispatches"

# 2. 拿最新 workflow_dispatch run
sleep 3
RUN=$(curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/tasks?page=1&limit=10" \
  | jq '.workflow_runs | map(select(.event=="workflow_dispatch")) | .[0]')
RUN_ID=$(echo "$RUN" | jq -r '.id')
RUN_NUMBER=$(echo "$RUN" | jq -r '.run_number')

# 3. 轮询 status（在 list 里筛 id）
while true; do
  STATUS=$(curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/tasks?limit=20" \
    | jq -r --arg id "$RUN_ID" '.workflow_runs[] | select(.id==($id|tonumber)) | .status' | head -n1)
  echo "status: ${STATUS}"
  case "$STATUS" in
    success|failure|cancelled|skipped) break ;;
  esac
  sleep 10
done
echo "Web UI: ${GITEA_HOST}/${OWNER}/${REPO}/actions/runs/${RUN_NUMBER}"
```

### 拉 run 关联的 artifact

```bash
# 列出该 run 的 artifact
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/runs/${RUN_ID}/artifacts" \
  | jq '.artifacts'

# 下载第一个
ART_ID=$(curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/runs/${RUN_ID}/artifacts" \
  | jq -r '.artifacts[0].id')
curl -fsSL -o output.zip \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/artifacts/${ART_ID}/zip"
```

### 失败 run 后的诊断

```bash
# 1. 找最新失败 run
FAILED=$(curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/tasks?limit=50" \
  | jq '.workflow_runs | map(select(.status=="failure")) | .[0]')
echo "$FAILED" | jq '{id, run_number, name, head_branch}'
RUN_NUMBER=$(echo "$FAILED" | jq -r '.run_number')

# 2. 因为没有 list jobs API，直接给用户 Web UI 链接
echo "请打开 Web UI 查看 job 日志：${GITEA_HOST}/${OWNER}/${REPO}/actions/runs/${RUN_NUMBER}"

# 3. 如果 CI 上传了 artifact，直接下载
RUN_ID=$(echo "$FAILED" | jq -r '.id')
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/actions/runs/${RUN_ID}/artifacts" \
  | jq '.artifacts'
```

## 权限提示

| 操作 | scope |
|------|-------|
| 读 workflows / runs（tasks）/ artifacts | `read:repository` |
| dispatch / enable / disable | `write:repository` |
| 读 secrets metadata、读 variables | repo: `write:repository`；org: 组织 owner |
| 写 secrets / variables | repo: `write:repository`；org: 组织 owner |
| 删除 artifact | `write:repository` |
| 管理 runner、注册 token | repo: `write:repository`；org: org owner；admin: 实例管理员 |

**敏感操作清单**（必须先和用户确认）：
- `dispatch_workflow`（真实跑 CI，可能产生计费/部署）
- `PUT` 已存在的 secret / variable（覆盖）
- `DELETE` 任何 secret / variable / artifact / runner
- `PUT .../disable` workflow（停掉自动触发）
