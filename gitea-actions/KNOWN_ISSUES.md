# Gitea Actions Skill — Known Issues

## Still missing on 1.26.4: cancel run API

Gitea 1.26.4 swagger does not include `POST /actions/runs/{run}/cancel` (or an equivalent endpoint). To cancel a running workflow, direct the user to the Web UI:

```
${GITEA_HOST}/${OWNER}/${REPO}/actions/runs/${RUN_NUMBER}
```

---

## Historical: Actions API gaps on 1.24.x (fixed in 1.25+)

The following issues were observed on Gitea **1.24.6**. After upgrading to **1.25+** (including 1.26.4), use the `/actions/runs` endpoints instead.

### `/actions/jobs/{job_id}/logs` unavailable on 1.24.x

#### Symptoms

Calling `GET /api/v1/repos/{owner}/{repo}/actions/jobs/{job_id}/logs` always returns **HTTP 500** (empty message), regardless of `job_id`.

#### Root cause

1. **Cannot obtain the correct `job_id`**: `/actions/tasks` returns `id` as `ActionTask.ID`, but the logs endpoint needs `ActionRunJob.ID`; 1.24.x has no `/actions/runs/{id}/jobs`
2. **Log read path differs from Web UI**: API uses file storage; Web UI uses database cursor
3. **Error handling bug**: returns 500 instead of 404 when job not found

#### Fix in 1.25+

```bash
# 1. List jobs to get the correct job_id
curl ... "/actions/runs/${RUN_ID}/jobs" | jq '.jobs[].id'

# 2. Read logs
curl ... "/actions/jobs/${JOB_ID}/logs"
```

### Endpoints missing on 1.24.x (added in 1.25+)

| endpoint | 1.24.x | 1.25+ |
|----------|--------|-------|
| `GET /actions/runs` | 404 | ✅ |
| `GET /actions/runs/{run}` | 404 | ✅ |
| `GET /actions/runs/{run}/jobs` | 404 | ✅ |
| `GET /actions/jobs/{job_id}` | 404 | ✅ |
| `POST /actions/runs/{run}/rerun` | 404 | ✅ |
| `DELETE /actions/runs/{run}` | 404 | ✅ (1.26.4) |

Verification environment (historical): Gitea `1.24.6+1-g4bb4f81c61`, 2026-05-18.
