# Gitea Actions Skill 已知问题

## `/actions/jobs/{job_id}/logs` 在 Gitea 1.24.x 上不可用

### 现象

调用 `GET /api/v1/repos/{owner}/{repo}/actions/jobs/{job_id}/logs` 始终返回 **HTTP 500**（空 message），无论传入什么 `job_id`。

而同一实例的 Web UI 能正常显示 job 日志。

### 根因分析

通过阅读 Gitea v1.24.6 源码（`routers/api/v1/repo/actions_run.go` + `routers/common/actions.go`），确认存在以下两个问题：

#### 问题 1：无法获取正确的 `job_id`

| 概念 | 数据库表 | API 暴露方式 |
|------|----------|-------------|
| ActionTask（runner 执行单元） | `action_task` | `GET /actions/tasks` 返回，`id` 字段 = `ActionTask.ID` |
| ActionRunJob（workflow 中的 job） | `action_run_job` | **无 list endpoint** |
| ActionRun（一次 workflow 运行） | `action_run` | **无 list endpoint**（1.24.x 没有 `/actions/runs`） |

`/actions/jobs/{job_id}/logs` 需要的是 `action_run_job.ID`，但 1.24.x 的 API **没有任何 endpoint 能返回这个 ID**：

- `/actions/tasks` 返回的 `id` 是 `ActionTask.ID`（源码 `services/convert/convert.go:228`）
- `/actions/runs`、`/actions/runs/{id}/jobs`、`/actions/jobs` 在 1.24.x 上均 **404**（swagger 中未注册）

`ActionTask.JobID` 字段指向 `ActionRunJob.ID`，但 API 响应中未暴露此字段。

#### 问题 2：日志读取路径与 Web UI 不同

API 和 Web UI 读取日志走的是**完全不同的代码路径**：

| | API (`/api/v1/.../actions/jobs/{id}/logs`) | Web UI (POST logCursors) |
|---|---|---|
| 入口 | `routers/api/v1/repo/actions_run.go` | `routers/web/repo/actions/view.go` |
| 读取方式 | `actions.OpenLogs()` → 从文件存储/DBFS 读取完整日志文件 | 从 `ActionTaskStep` 表按 cursor 增量读取 |
| 失败原因 | 日志文件存储不可达或文件不存在 → 500 | 数据在数据库中，不依赖文件存储 |

源码关键路径（`routers/common/actions.go:31-71`）：

```go
func DownloadActionsRunJobLogs(...) error {
    task, err := actions_model.GetTaskByID(ctx, curJob.TaskID)
    // ...
    reader, err := actions.OpenLogs(ctx, task.LogInStorage, task.LogFilename)
    // ↑ 这里失败 → 返回 500
}
```

`OpenLogs` 根据 `task.LogInStorage` 决定从 DBFS 还是对象存储读取。如果存储后端（Minio/S3/本地路径）不可达或日志文件已被清理，就会 500。

#### 问题 3：错误处理 bug

`actions_run.go:46-49` 中 `GetRunJobByID` 返回 `ErrNotExist` 时，handler 直接 `ctx.APIErrorInternal(err)` 返回 500，而不是 404：

```go
curJob, err := actions_model.GetRunJobByID(ctx, jobID)
if err != nil {
    ctx.APIErrorInternal(err) // BUG: 应检查 ErrNotExist 返回 404
    return
}
```

这导致无法区分"job 不存在"和"日志读取失败"。

### 影响范围

- `gitea-mcp` 的 `get_job_log_preview` / `download_job_log` 方法在 Gitea 1.24.x 上完全不可用
- `gitea-actions` skill 中关于 job logs 的指导在 1.24.x 上无法执行
- `list_runs`、`list_jobs`、`list_run_jobs` 在 1.24.x 上均 404（这些 endpoint 在 1.25+ 才引入）

### 临时解决方案

目前在 Gitea 1.24.x 上**没有可用的 API 方式获取 job 日志**。可选的 workaround：

1. **升级 Gitea 到 1.25+**：引入了 `/actions/runs`、`/actions/runs/{id}/jobs` 等 endpoint，且修复了日志读取问题
2. **检查日志存储配置**：确认 `app.ini` 中 `[storage.actions_log]` 或 `[actions]` 段的存储后端可达
3. **引导用户查看 Web UI**：`${GITEA_HOST}/${OWNER}/${REPO}/actions/runs/${RUN_NUMBER}`

### 验证环境

- Gitea 版本：`1.24.6+1-g4bb4f81c61`
- 验证日期：2026-05-18
- 验证仓库：`productivity/quantpi-system`、`productivity/ac-web-api`（所有仓库均复现）
