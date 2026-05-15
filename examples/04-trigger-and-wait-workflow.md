# 04 — Trigger a deploy workflow and wait for it

**Skill triggered**: `gitea-actions` (with `gitea-shared`)

## User prompt

> Run `deploy.yml` in `team-a/web` against `main`, with environment input `staging`. Wait until done and tell me the result.

## Why this needs care

- `dispatch_workflow` is a **real CI execution** (real cost, real side effects).
- Gitea 1.24.6 has **no list-jobs API**, so polling status has to use `/actions/tasks` (the list of runs).
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
  "${GITEA_HOST}/api/v1/repos/team-a/web/actions/tasks?page=1&limit=10" \
  | jq '.workflow_runs | map(select(.event=="workflow_dispatch")) | .[0]')

RUN_ID=$(echo "$NEW_RUN" | jq -r '.id')
RUN_NUMBER=$(echo "$NEW_RUN" | jq -r '.run_number')
echo "Triggered run #${RUN_NUMBER} (id=${RUN_ID})"
echo "Web UI: ${GITEA_HOST}/team-a/web/actions/runs/${RUN_NUMBER}"
```

### 4. Poll until terminal state

```bash
while true; do
  STATUS=$(curl -fsSL -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
    "${GITEA_HOST}/api/v1/repos/team-a/web/actions/tasks?limit=20" \
    | jq -r --arg id "$RUN_ID" '.workflow_runs[] | select(.id == ($id | tonumber)) | .status' | head -n1)
  echo "[$(date +%H:%M:%S)] status=${STATUS}"
  case "$STATUS" in
    success|failure|cancelled|skipped) break ;;
  esac
  sleep 10
done

echo "Final: ${STATUS}"
```

### 5. On failure, surface artifacts (since job logs need a job_id we don't have)

```bash
if [ "$STATUS" = "failure" ]; then
  echo "Web UI for logs: ${GITEA_HOST}/team-a/web/actions/runs/${RUN_NUMBER}"
  echo "Artifacts (if any):"
  curl -fsSL -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
    "${GITEA_HOST}/api/v1/repos/team-a/web/actions/runs/${RUN_ID}/artifacts" \
    | jq '.artifacts | [.[] | {name, size_in_bytes, archive_download_url}]'
fi
```

If your CI uploads a `failure-context.zip` artifact, it can be fetched via `archive_download_url` — this is the recommended pattern given the missing job-log API.

## Variations

- "Just trigger it, don't wait" -> stop after step 2.
- "Trigger but only if no other run is in progress" -> before step 2, check
  `tasks?status=in_progress` and bail if non-empty.
- "Disable this workflow temporarily" -> `PUT /actions/workflows/deploy.yml/disable` (returns 204).
