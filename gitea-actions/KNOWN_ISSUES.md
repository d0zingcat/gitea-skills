# Gitea Actions Skill 已知问题

## 1.26.4 仍缺失：cancel run API

Gitea 1.26.4 swagger 没有 `POST /actions/runs/{run}/cancel`（或等价 endpoint）。要取消正在运行的 workflow，只能引导用户到 Web UI：

```
${GITEA_HOST}/${OWNER}/${REPO}/actions/runs/${RUN_NUMBER}
```

---

## 历史：1.24.x 上的 Actions API 缺陷（已在 1.25+ 修复）

以下问题记录在 Gitea **1.24.6** 上，升级到 **1.25+**（含你们的 1.26.4）后应改用 `/actions/runs` 系列 endpoint。

### `/actions/jobs/{job_id}/logs` 在 1.24.x 上不可用

#### 现象

调用 `GET /api/v1/repos/{owner}/{repo}/actions/jobs/{job_id}/logs` 始终返回 **HTTP 500**（空 message），无论传入什么 `job_id`。

#### 根因

1. **无法获取正确的 `job_id`**：`/actions/tasks` 返回的 `id` 是 `ActionTask.ID`，而 logs endpoint 需要 `ActionRunJob.ID`；1.24.x 没有 `/actions/runs/{id}/jobs`
2. **日志读取路径与 Web UI 不同**：API 走文件存储，Web UI 走数据库 cursor
3. **错误处理 bug**：job 不存在时返回 500 而非 404

#### 1.25+ 修复方式

```bash
# 1. 列 jobs 拿正确的 job_id
curl ... "/actions/runs/${RUN_ID}/jobs" | jq '.jobs[].id'

# 2. 读日志
curl ... "/actions/jobs/${JOB_ID}/logs"
```

### 1.24.x 缺失的 endpoint（1.25+ 已引入）

| endpoint | 1.24.x | 1.25+ |
|----------|--------|-------|
| `GET /actions/runs` | 404 | ✅ |
| `GET /actions/runs/{run}` | 404 | ✅ |
| `GET /actions/runs/{run}/jobs` | 404 | ✅ |
| `GET /actions/jobs/{job_id}` | 404 | ✅ |
| `POST /actions/runs/{run}/rerun` | 404 | ✅ |
| `DELETE /actions/runs/{run}` | 404 | ✅（1.26.4） |

验证环境（历史）：Gitea `1.24.6+1-g4bb4f81c61`，2026-05-18。
