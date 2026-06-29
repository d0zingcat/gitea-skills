#!/usr/bin/env bash
# Read-only + write smoke test of the documented endpoints.
# Requires: GITEA_HOST, GITEA_ACCESS_TOKEN, jq, curl.
#
# Creates a temp repo, exercises endpoints from each gitea-* skill, then
# leaves the repo behind (CI uses a throw-away Gitea container so cleanup
# is a no-op).
#
# Exits non-zero on any failed assertion.

set -uo pipefail

: "${GITEA_HOST:?GITEA_HOST not set}"
: "${GITEA_ACCESS_TOKEN:?GITEA_ACCESS_TOKEN not set}"

# Output helpers
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }

PASS=0
FAIL=0
SKIP=0
ERRORS=()

# api: GET wrapper (token included). Stdout = body. Returns curl exit.
api() {
  curl -fsSL \
    -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
    -H "Accept: application/json" \
    "$@"
}

# api_with_status: any verb. Stdout: body. Sets HTTP_CODE global. Never exits.
HTTP_CODE=
api_with_status() {
  local body_file
  body_file=$(mktemp)
  HTTP_CODE=$(curl -sSL -o "$body_file" -w '%{http_code}' \
    -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
    -H "Accept: application/json" \
    "$@" || echo "000")
  cat "$body_file"
  rm -f "$body_file"
}

# assert NAME CMD -- evaluate CMD; PASS if exit 0
assert() {
  local name="$1" cmd="$2"
  if eval "$cmd" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    green "  PASS  $name"
  else
    local rc=$?
    FAIL=$((FAIL + 1))
    ERRORS+=("$name (rc=$rc)")
    red   "  FAIL  $name"
  fi
}

# assert_http NAME EXPECTED_CODE METHOD URL [extra args]
assert_http() {
  local name="$1" expect="$2"; shift 2
  local body_file
  body_file=$(mktemp)
  local code
  code=$(curl -sSL -o "$body_file" -w '%{http_code}' \
    -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
    -H "Accept: application/json" \
    "$@" || echo "000")
  if [ "$code" = "$expect" ]; then
    PASS=$((PASS + 1))
    green "  PASS  $name (HTTP $code)"
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("$name expected $expect got $code")
    red   "  FAIL  $name expected HTTP $expect got $code"
    echo "        body: $(head -c 300 "$body_file")"
  fi
  rm -f "$body_file"
}

# Capture variable from a JSON response field. On failure prints reason and
# returns 1 instead of crashing the whole script under set -e.
json_extract() {
  local label="$1"; shift  # remaining: curl args
  local body_file
  body_file=$(mktemp)
  local code
  code=$(curl -sSL -o "$body_file" -w '%{http_code}' \
    -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
    -H "Accept: application/json" \
    "$@" || echo "000")
  if [ "$code" -ge 200 ] && [ "$code" -lt 300 ]; then
    cat "$body_file"
    rm -f "$body_file"
    return 0
  else
    red   "  FAIL  $label (HTTP $code): $(head -c 300 "$body_file")"
    rm -f "$body_file"
    FAIL=$((FAIL + 1))
    ERRORS+=("$label HTTP $code")
    return 1
  fi
}

echo "============================================================"
echo "Gitea version: ${GITEA_VERSION:-unknown}"
echo "GITEA_HOST:    ${GITEA_HOST}"
echo "============================================================"

echo
echo "== gitea-shared =="
assert "/version reachable"  'api "${GITEA_HOST}/api/v1/version" | jq -e .version'
assert "/user authenticated" 'api "${GITEA_HOST}/api/v1/user" | jq -e .login'

ME=$(api "${GITEA_HOST}/api/v1/user" | jq -r .login 2>/dev/null || echo "")
if [ -z "$ME" ] || [ "$ME" = "null" ]; then
  red "FATAL: could not determine current user"
  exit 1
fi
echo "Authenticated as: $ME"

REPO="smoke-$(date +%s)"

echo
echo "== gitea-repo (create + branch + file) =="
RESP=$(json_extract "create repo" \
  -X POST -H "Content-Type: application/json" \
  -d "{\"name\":\"${REPO}\",\"auto_init\":true,\"private\":false,\"default_branch\":\"main\"}" \
  "${GITEA_HOST}/api/v1/user/repos") && {
  if echo "$RESP" | jq -e .full_name >/dev/null 2>&1; then
    PASS=$((PASS+1)); green "  PASS  create repo"
  else
    FAIL=$((FAIL+1)); ERRORS+=("create repo no full_name"); red "  FAIL  create repo: response missing full_name"
  fi
}

assert "list my repos"     'api "${GITEA_HOST}/api/v1/user/repos?limit=50" | jq -e "length > 0"'
assert "get repo metadata" "api '${GITEA_HOST}/api/v1/repos/${ME}/${REPO}' | jq -e .full_name"
assert "list branches"     "api '${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/branches' | jq -e 'length > 0'"

assert "create branch (old_ref_name)" "api -X POST -H 'Content-Type: application/json' \
  -d '{\"new_branch_name\":\"featx\",\"old_ref_name\":\"main\"}' \
  '${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/branches' | jq -e .name"

assert "git/trees uses per_page" "api '${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/git/trees/main?per_page=1' \
  | jq -e '.tree | length <= 1'"

CONTENT=$(printf "hello\n" | base64)
assert "create file" "api -X POST -H 'Content-Type: application/json' \
  -d \"\$(jq -n --arg c '$CONTENT' '{branch:\\\"main\\\",message:\\\"add hello\\\",content:\\\$c}')\" \
  '${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/contents/hello.txt' | jq -e .content.sha"

echo
echo "== gitea-issue =="
ISSUE_RESP=$(json_extract "create issue" \
  -X POST -H "Content-Type: application/json" \
  -d '{"title":"smoke issue","body":"smoke"}' \
  "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/issues") || ISSUE_RESP=""

ISSUE_NUM=$(echo "$ISSUE_RESP" | jq -r '.number // empty')
if [ -n "$ISSUE_NUM" ]; then
  PASS=$((PASS+1)); green "  PASS  create issue (#${ISSUE_NUM})"
  assert "list issues"  "api '${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/issues?state=all' | jq -e 'length > 0'"
  assert "add comment"  "api -X POST -H 'Content-Type: application/json' \
    -d '{\"body\":\"hi\"}' \
    '${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/issues/${ISSUE_NUM}/comments' | jq -e .id"
  assert "list comments" "api '${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/issues/${ISSUE_NUM}/comments' | jq -e 'length > 0'"
else
  red "  SKIP  issue follow-ups (no issue created)"
  SKIP=$((SKIP+3))
fi

echo
echo "== gitea-label =="
LABEL_RESP=$(json_extract "create label" \
  -X POST -H "Content-Type: application/json" \
  -d '{"name":"bug","color":"#d73a4a"}' \
  "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/labels") || LABEL_RESP=""

LABEL_ID=$(echo "$LABEL_RESP" | jq -r '.id // empty')
if [ -n "$LABEL_ID" ]; then
  PASS=$((PASS+1)); green "  PASS  create label (id=${LABEL_ID})"
  if [ -n "${ISSUE_NUM:-}" ]; then
    assert "attach label" "api -X POST -H 'Content-Type: application/json' \
      -d '{\"labels\":[${LABEL_ID}]}' \
      '${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/issues/${ISSUE_NUM}/labels' | jq -e 'length > 0'"
  fi
else
  red "  SKIP  attach label (no label)"
  SKIP=$((SKIP+1))
fi

echo
echo "== gitea-milestone =="
json_extract "create milestone" \
  -X POST -H "Content-Type: application/json" \
  -d '{"title":"v1.0.0"}' \
  "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/milestones" \
  | jq -e .id >/dev/null 2>&1 \
  && { PASS=$((PASS+1)); green "  PASS  create milestone"; } \
  || true  # already counted by json_extract on failure

echo
echo "== gitea-pull =="
# Open a PR by creating a divergent commit on featx via the create-file
# endpoint (uses new_branch parameter so we don't depend on a prior create-branch
# call having materialized).
NEW=$(printf "hello v2\n" | base64)
DIVERGE_RESP=$(json_extract "create commit on featx-pr" \
  -X POST -H "Content-Type: application/json" \
  -d "$(jq -n --arg c "$NEW" '{branch:"main",new_branch:"featx-pr",message:"diverge for PR",content:$c}')" \
  "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/contents/extra.txt")
if [ -n "$DIVERGE_RESP" ]; then
  PASS=$((PASS+1)); green "  PASS  create commit on featx-pr"
  PR_RESP=$(json_extract "create PR" \
    -X POST -H "Content-Type: application/json" \
    -d '{"title":"smoke PR","body":"smoke","head":"featx-pr","base":"main"}' \
    "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/pulls") || PR_RESP=""

  PR_NUM=$(echo "$PR_RESP" | jq -r '.number // empty')
  if [ -n "$PR_NUM" ]; then
    PASS=$((PASS+1)); green "  PASS  create PR (#${PR_NUM})"
    assert "list PRs"        "api '${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/pulls?state=all' | jq -e 'length > 0'"
    assert "get PR diff"     "curl -fsSL -H 'Authorization: token ${GITEA_ACCESS_TOKEN}' \
      '${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/pulls/${PR_NUM}.diff' | grep -q '^diff'"
    assert "get PR files"    "api '${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/pulls/${PR_NUM}/files?whitespace=ignore-eol' | jq -e 'length > 0'"
    assert "get PR commits"  "api '${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/pulls/${PR_NUM}/commits' | jq -e 'length > 0'"
  else
    yellow "  SKIP  PR follow-ups"
    SKIP=$((SKIP+4))
  fi
else
  yellow "  SKIP  PR section (could not create divergent commit)"
  SKIP=$((SKIP+5))
fi

echo
echo "== gitea-search =="
# Sort enum is the most regression-prone area — skill docs claim these are
# the 1.24+ valid values. Older Gitea may differ; mark as soft check for
# pre-1.24 versions.
case "${GITEA_VERSION:-1.24}" in
  1.21|1.22|1.23)
    yellow "  NOTE  search sort enum may differ on $GITEA_VERSION; checking with conservative values"
    assert "search repos sort=alpha"  "api '${GITEA_HOST}/api/v1/repos/search?sort=alpha&limit=2' | jq -e .data"
    ;;
  *)
    assert "search repos sort=created" "api '${GITEA_HOST}/api/v1/repos/search?sort=created&order=desc&limit=2' | jq -e '.data | length >= 0'"
    assert "search repos sort=alpha"   "api '${GITEA_HOST}/api/v1/repos/search?sort=alpha&limit=2' | jq -e .data"
    ;;
esac
assert "search issues type=issues" "api '${GITEA_HOST}/api/v1/repos/issues/search?type=issues&state=all&limit=2'"
assert "search users"              "api '${GITEA_HOST}/api/v1/users/search?q=${ME}&limit=2' | jq -e .data"

echo
echo "== gitea-user =="
assert "/user/orgs" "api '${GITEA_HOST}/api/v1/user/orgs'"

echo
echo "== gitea-notification =="
assert "list notifications" "api '${GITEA_HOST}/api/v1/notifications?status-types=unread'"

echo
echo "== gitea-actions (path-only) =="
status=$(curl -sSL -o /dev/null -w '%{http_code}' \
  -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
  "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/actions/workflows")
case "$status" in
  200) PASS=$((PASS+1)); green "  PASS  workflows endpoint reachable (HTTP 200)";;
  404) yellow "  SKIP  workflows endpoint not enabled (HTTP 404)"; SKIP=$((SKIP+1));;
  *)   FAIL=$((FAIL+1)); ERRORS+=("workflows unexpected $status"); red "  FAIL  workflows endpoint unexpected HTTP $status";;
esac

# Tasks list (legacy alias, still present on 1.24+)
status=$(curl -sSL -o /dev/null -w '%{http_code}' \
  -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
  "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/actions/tasks")
case "$status" in
  200) PASS=$((PASS+1)); green "  PASS  tasks endpoint reachable (HTTP 200)";;
  404) yellow "  SKIP  tasks endpoint not enabled (HTTP 404)"; SKIP=$((SKIP+1));;
  *)   FAIL=$((FAIL+1)); ERRORS+=("tasks unexpected $status"); red "  FAIL  tasks endpoint unexpected HTTP $status";;
esac

# Runs list (canonical on 1.25+)
status=$(curl -sSL -o /dev/null -w '%{http_code}' \
  -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
  "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/actions/runs")
case "$status" in
  200) PASS=$((PASS+1)); green "  PASS  runs endpoint reachable (HTTP 200)";;
  404) yellow "  SKIP  runs endpoint not available on this version (HTTP 404)"; SKIP=$((SKIP+1));;
  *)   FAIL=$((FAIL+1)); ERRORS+=("runs unexpected $status"); red "  FAIL  runs endpoint unexpected HTTP $status";;
esac

echo
echo "============================================================"
echo "Result: PASS=${PASS}  FAIL=${FAIL}  SKIP=${SKIP}"
echo "============================================================"

if [ "$FAIL" -gt 0 ]; then
  echo
  red "Failed assertions:"
  printf '  - %s\n' "${ERRORS[@]}"
  exit 1
fi
