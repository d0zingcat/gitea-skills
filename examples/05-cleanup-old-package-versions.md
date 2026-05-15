# 05 — Clean up old container package versions

**Skill triggered**: `gitea-package` (with `gitea-shared`)

## User prompt

> Delete all but the 5 latest versions of the container `productivity/my-app`. Keep `latest` always.

## Why this needs care

- Package deletion is **irreversible** — once deleted, image pulls fail immediately.
- Container package names commonly contain `/` (e.g. `org/image`); URL must be encoded.
- The skill must always show what would be deleted before doing it (dry-run first).

## Expected flow

### 1. List all versions

```bash
NAME_ENC=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "my-app")

curl -fsSL \
  -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
  "${GITEA_HOST}/api/v1/packages/productivity/container/${NAME_ENC}?limit=100" \
  | jq 'sort_by(.created_at) | reverse | [.[] | {version, created_at}]'
```

### 2. Compute what would be deleted (dry run)

```bash
TO_DELETE=$(curl -fsSL \
  -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
  "${GITEA_HOST}/api/v1/packages/productivity/container/${NAME_ENC}?limit=100" \
  | jq -r '
      sort_by(.created_at) | reverse
      | map(select(.version != "latest"))
      | .[5:]
      | .[].version')

echo "Would delete:"
echo "$TO_DELETE"
echo "Total: $(echo "$TO_DELETE" | wc -l) versions"
```

### 3. Confirm with user

Agent shows the list and asks: "Proceed?"

Wait for explicit yes.

### 4. Delete

```bash
for V in $TO_DELETE; do
  V_ENC=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$V")
  echo "Deleting ${V}"
  curl -fsSL -X DELETE \
    -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
    "${GITEA_HOST}/api/v1/packages/productivity/container/${NAME_ENC}/${V_ENC}"
done
```

### 5. Verify

```bash
curl -fsSL \
  -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
  "${GITEA_HOST}/api/v1/packages/productivity/container/${NAME_ENC}?limit=100" \
  | jq 'length'
```

Should now equal 5 + 1 (`latest`) = 6, or whatever remained.

## Edge cases the agent should handle

- **`latest` tag**: never delete; the jq filter above explicitly excludes it.
- **`sha256:...` digest versions**: container packages have one digest per build.
  These are usually NOT what users mean by "version" — agent should ask if they
  count toward the 5 to keep.
- **Versions referenced by linked repos**: deleting a version that's the latest
  pulled in a deploy can break running services. Agent should mention
  `/-/link` if a repo is linked.

## Variations

- "Keep last 30 days instead of last 5" ->
  ```bash
  CUTOFF=$(date -u -d '30 days ago' +%FT%TZ 2>/dev/null || date -u -v -30d +%FT%TZ)
  jq -r --arg c "$CUTOFF" 'map(select(.created_at < $c and .version != "latest")) | .[].version'
  ```
- "Just dry-run, never delete" -> stop after step 2.
- "All versions of all containers in this owner" -> wrap in
  `for NAME in $(curl ... /packages/productivity?type=container | jq -r '.[].name' | sort -u)`.
