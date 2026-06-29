# 04 — Trigger a deploy workflow and wait for it

**Skill triggered**: `gitea-actions` (with `gitea-shared`)

## User prompt

> Run `deploy.yml` in `team-a/web` against `main`, with environment input `staging`. Wait until done and tell me the result.

## Why this needs care

- `dispatch_workflow` is a **real CI execution** (real cost, real side effects).
- On Gitea **1.25+** (including 1.26.4), poll run status via `GET /actions/runs/{run_id}` and check `status=completed` + `conclusion`.
- On Gitea **1.24.x**, fallback to `/actions/tasks` (single `status` field, no list-jobs API).
- The endpoint name is `dispatches` (plural) on 1.21+. Old singular `dispatch` is gone.

## Expected flow

### 1. Confirm with user

Agent should show:

> About to dispatch `deploy.yml` on branch `main` of `team-a/web` with inputs `{environment: "staging"}`. This will run real CI. OK?

Wait for explicit yes.

### 2. Dispatch (returns 204 No Content)

```bash
curl -fsSL -X POST \
  -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"ref":"main","inputs":{"environment":"staging"}}' \
  "${GITEA_HOST}/api/v1/repos/team-a/web/actions/workflows/deploy.yml/dispatches"
```

Empty body on success.

### 3. Find the freshly created run

```bash
sleep 3   # give Gitea a moment to materialize the run
NEW_RUN=$(curl -fsSL \
  -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
  "${GITEA_HOST}/api/v1/repos/team-a/web/actions/runs?page=1&limit=10" \
  | jq '.workflow_runs | map(select(.event=="workflow_dispatch")) | .[0]')

RUN_ID=$(echo "$NEW_RUN" | jq -r '.id')
RUN_NUMBER=$(echo "$NEW_RUN" | jq -r '.run_number')
echo "Triggered run #${RUN_NUMBER} (id=${RUN_ID})"
echo "Web UI: ${GITEA_HOST}/team-a/web/actions/runs/${RUN_NUMBER}"
```

If `/actions/runs` returns 404 (Gitea < 1.25), replace the URL with `/actions/tasks`.

### 4. Poll until terminal state

```bash
while true; do
  INFO=$(curl -fsSL -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
    "${GITEA_HOST}/api/v1/repos/team-a/web/actions/runs/${RUN_ID}" \
    | jq '{status, conclusion}')
  STATUS=$(echo "$INFO" | jq -r '.status')
  CONCLUSION=$(echo "$INFO" | jq -r '.conclusion // empty')
  echo "[$(date +%H:%M:%S)] status=${STATUS} conclusion=${CONCLUSION}"
  [ "$STATUS" = "completed" ] && break
  sleep 10
done

echo "Final: ${CONCLUSION}"
```

### 5. On failure, pull job logs

```bash
if [ "$CONCLUSION" = "failure" ]; then
  JOB_ID=$(curl -fsSL -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
    "${GITEA_HOST}/api/v1/repos/team-a/web/actions/runs/${RUN_ID}/jobs" \
    | jq -r '.jobs | map(select(.conclusion=="failure")) | .[0].id // .jobs[0].id')

  if [ -n "$JOB_ID" ] && [ "$JOB_ID" != "null" ]; then
    curl -fsSL -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
      -o failure.log \
      "${GITEA_HOST}/api/v1/repos/team-a/web/actions/jobs/${JOB_ID}/logs"
    echo "Saved job log to failure.log"
  fi

  echo "Artifacts (if any):"
  curl -fsSL -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
    "${GITEA_HOST}/api/v1/repos/team-a/web/actions/runs/${RUN_ID}/artifacts" \
    | jq '.artifacts | [.[] | {name, size_in_bytes, archive_download_url}]'
fi
```

## Variations

- "Just trigger it, don't wait" -> stop after step 2.
- "Trigger but only if no other run is in progress" -> before step 2, check
  `actions/runs?status=in_progress` and bail if non-empty.
- "Disable this workflow temporarily" -> `PUT /actions/workflows/deploy.yml/disable` (returns 204).
- "Rerun the failed jobs" -> `POST /actions/runs/${RUN_ID}/rerun-failed-jobs` (confirm with user first).
