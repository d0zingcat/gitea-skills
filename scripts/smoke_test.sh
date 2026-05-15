#!/usr/bin/env bash
# Read-only smoke test of the documented endpoints.
# Requires: GITEA_HOST, GITEA_ACCESS_TOKEN, jq, curl.
#
# Creates a temp repo, exercises endpoints from each gitea-* skill, then
# leaves the repo behind (CI uses a throw-away Gitea container so cleanup
# is a no-op).
#
# Exits non-zero on any failed assertion.

set -euo pipefail

: "${GITEA_HOST:?GITEA_HOST not set}"
: "${GITEA_ACCESS_TOKEN:?GITEA_ACCESS_TOKEN not set}"

H=(-H "Authorization: token ${GITEA_ACCESS_TOKEN}" -H "Accept: application/json")
PASS=0
FAIL=0
ERRORS=()

api() { curl -fsSL "${H[@]}" "$@"; }

assert() {
  local name="$1" cmd="$2"
  if eval "$cmd" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    printf '  PASS  %s\n' "$name"
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("$name")
    printf '  FAIL  %s\n' "$name"
  fi
}

echo "== gitea-shared =="
assert "/version reachable"    'api "${GITEA_HOST}/api/v1/version" | jq -e .version'
assert "/user authenticated"   'api "${GITEA_HOST}/api/v1/user" | jq -e .login'

ME=$(api "${GITEA_HOST}/api/v1/user" | jq -r .login)
REPO="smoke-$(date +%s)"

echo "== gitea-repo (create + branch + file) =="
assert "create repo"           'api -X POST -H "Content-Type: application/json" \
  -d "{\"name\":\"'"$REPO"'\",\"auto_init\":true,\"private\":false,\"default_branch\":\"main\"}" \
  "${GITEA_HOST}/api/v1/user/repos" | jq -e .full_name'

assert "list my repos"         'api "${GITEA_HOST}/api/v1/user/repos?limit=50" | jq -e "length > 0"'
assert "get repo metadata"     'api "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}" | jq -e .full_name'
assert "list branches"         'api "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/branches" | jq -e "length > 0"'

assert "create branch"         'api -X POST -H "Content-Type: application/json" \
  -d "{\"new_branch_name\":\"feat/x\",\"old_ref_name\":\"main\"}" \
  "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/branches" | jq -e .name'

assert "git/trees uses per_page" 'api "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/git/trees/main?per_page=2" \
  | jq -e ".tree | length <= 2"'

CONTENT=$(printf "hello\n" | base64)
assert "create file"           'api -X POST -H "Content-Type: application/json" \
  -d "$(jq -n --arg c "$CONTENT" "{branch:\"main\",message:\"add hello\",content:\$c}")" \
  "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/contents/hello.txt" | jq -e .content.sha'

echo "== gitea-issue =="
ISSUE_NUM=$(api -X POST -H "Content-Type: application/json" \
  -d "{\"title\":\"smoke issue\",\"body\":\"smoke\"}" \
  "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/issues" | jq -r .number)
assert "create issue"          '[ -n "$ISSUE_NUM" ] && [ "$ISSUE_NUM" != "null" ]'
assert "list issues"           'api "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/issues?state=all" | jq -e "length > 0"'
assert "add comment"           'api -X POST -H "Content-Type: application/json" \
  -d "{\"body\":\"hi\"}" \
  "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/issues/${ISSUE_NUM}/comments" | jq -e .id'
assert "list comments"         'api "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/issues/${ISSUE_NUM}/comments" | jq -e "length > 0"'

echo "== gitea-label =="
LABEL_ID=$(api -X POST -H "Content-Type: application/json" \
  -d "{\"name\":\"bug\",\"color\":\"#d73a4a\"}" \
  "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/labels" | jq -r .id)
assert "create label"          '[ -n "$LABEL_ID" ] && [ "$LABEL_ID" != "null" ]'
assert "attach label"          'api -X POST -H "Content-Type: application/json" \
  -d "{\"labels\":[${LABEL_ID}]}" \
  "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/issues/${ISSUE_NUM}/labels" | jq -e "length > 0"'

echo "== gitea-milestone =="
MS_ID=$(api -X POST -H "Content-Type: application/json" \
  -d "{\"title\":\"v1.0.0\"}" \
  "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/milestones" | jq -r .id)
assert "create milestone"      '[ -n "$MS_ID" ] && [ "$MS_ID" != "null" ]'

echo "== gitea-pull =="
# Need a commit on feat/x to open a PR
SHA=$(api "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/contents/hello.txt?ref=feat/x" | jq -r .sha)
NEW=$(printf "hello v2\n" | base64)
api -X PUT -H "Content-Type: application/json" \
  -d "$(jq -n --arg c "$NEW" --arg s "$SHA" "{branch:\"feat/x\",message:\"update\",content:\$c,sha:\$s}")" \
  "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/contents/hello.txt" >/dev/null

PR_NUM=$(api -X POST -H "Content-Type: application/json" \
  -d "{\"title\":\"smoke PR\",\"body\":\"smoke\",\"head\":\"feat/x\",\"base\":\"main\"}" \
  "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/pulls" | jq -r .number)
assert "create PR"             '[ -n "$PR_NUM" ] && [ "$PR_NUM" != "null" ]'
assert "list PRs"              'api "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/pulls?state=all" | jq -e "length > 0"'
assert "get PR diff"           'curl -fsSL -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
  "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/pulls/${PR_NUM}.diff" | grep -q "^diff"'
assert "get PR files"          'api "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/pulls/${PR_NUM}/files?whitespace=ignore-eol" | jq -e "length > 0"'
assert "get PR commits"        'api "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/pulls/${PR_NUM}/commits" | jq -e "length > 0"'

echo "== gitea-search =="
# Sort enum is the most regression-prone area
assert "search repos sort=created" 'api "${GITEA_HOST}/api/v1/repos/search?sort=created&order=desc&limit=5" | jq -e ".data | length > 0"'
assert "search repos sort=alpha"   'api "${GITEA_HOST}/api/v1/repos/search?sort=alpha&limit=5" | jq -e ".data"'
assert "search issues type=issues" 'api "${GITEA_HOST}/api/v1/repos/issues/search?type=issues&state=all&limit=5"'
assert "search users"              'api "${GITEA_HOST}/api/v1/users/search?q=${ME}&limit=5" | jq -e ".data"'

echo "== gitea-user =="
assert "/user/orgs"            'api "${GITEA_HOST}/api/v1/user/orgs"'

echo "== gitea-notification =="
assert "list notifications"    'api "${GITEA_HOST}/api/v1/notifications?status-types=unread"'

echo "== gitea-actions (path-only) =="
# A fresh sqlite Gitea may have actions disabled by default; tolerate 404
status=$(curl -sSL -o /dev/null -w '%{http_code}' "${H[@]}" \
  "${GITEA_HOST}/api/v1/repos/${ME}/${REPO}/actions/workflows")
case "$status" in
  200) printf '  PASS  workflows endpoint reachable (HTTP 200)\n'; PASS=$((PASS+1));;
  404) printf '  SKIP  workflows endpoint not enabled (HTTP 404)\n';;
  *)   printf '  FAIL  workflows endpoint unexpected HTTP %s\n' "$status"; FAIL=$((FAIL+1)); ERRORS+=("workflows unexpected $status");;
esac

echo
echo "Result: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed assertions:" >&2
  printf '  - %s\n' "${ERRORS[@]}" >&2
  exit 1
fi
