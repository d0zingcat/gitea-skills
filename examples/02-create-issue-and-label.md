# 02 — Open a bug issue and tag it

**Skills triggered**: `gitea-issue` + `gitea-label` (and `gitea-shared`)

## User prompt

> Open a bug issue in `team-a/web`: title "Login button unresponsive on Safari 17", and tag it as `bug` and `frontend`.

## Expected agent reasoning

1. Labels are referenced by **numeric ID**, not name. Need to look up the IDs first.
2. Then create the issue with `labels: [<id1>, <id2>]` in the body.

## Two-step command

```bash
# Step 1: get label IDs
LABELS_JSON=$(curl -fsSL \
  -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
  "${GITEA_HOST}/api/v1/repos/team-a/web/labels?limit=100")

BUG_ID=$(echo "$LABELS_JSON" | jq -r '.[] | select(.name=="bug") | .id')
FE_ID=$(echo "$LABELS_JSON" | jq -r '.[] | select(.name=="frontend") | .id')

# Sanity check before creating
echo "bug=${BUG_ID}, frontend=${FE_ID}"

# Step 2: create issue with labels in one shot
jq -n --argjson b "$BUG_ID" --argjson f "$FE_ID" '{
  title: "Login button unresponsive on Safari 17",
  body: "Steps to reproduce ...",
  labels: [$b, $f]
}' | curl -fsSL -X POST \
  -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d @- \
  "${GITEA_HOST}/api/v1/repos/team-a/web/issues" \
  | jq '{number, title, html_url}'
```

## What the agent should NOT do

- Pass `labels: ["bug", "frontend"]` (strings) -> Gitea will silently drop them. Labels MUST be IDs.
- Skip the bug-label-doesn-t-exist case. If `BUG_ID` comes back empty, agent should offer to create the label first via gitea-label.

## Variation: also assign and set milestone

Edit step 2 body:

```json
{
  "title": "...",
  "body": "...",
  "labels": [3, 7],
  "assignees": ["alice"],
  "milestone": 1
}
```

Agent should warn that `assignees` is usernames (string) but `labels` and `milestone` are IDs (number).
