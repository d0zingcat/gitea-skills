---
name: gitea-pull
version: 1.0.0
description: "Gitea Pull Request 管理：创建/编辑/合并/关闭 PR、读 diff 与文件清单、Review 流程（创建 review、提交 pending review、批准/驳回/dismiss、添加内联评论）、reviewers 增减、用 base 更新 PR 分支。涵盖 /repos/{owner}/{repo}/pulls 系列 endpoint。当用户需要在 Gitea 上提 PR、合并 PR、走代码评审流程、回滚 review、查 PR 改动文件或 diff 时使用。"
---

# Gitea Pull Request

**开始前必读 [`../gitea-shared/SKILL.md`](../gitea-shared/SKILL.md)**：认证、curl 模板、错误处理、安全规则。

下面所有 curl 都省略 `-H "Authorization: token ${GITEA_ACCESS_TOKEN}" -H "Accept: application/json"`。

## 关键概念

- **PR number** 与 issue 共享一个仓库内序列。
- PR 有两组 endpoint：
  - issue 视角：`/repos/{owner}/{repo}/issues/{n}`（评论、标签、状态切换、assignees 走这条）
  - PR 视角：`/repos/{owner}/{repo}/pulls/{n}`（diff、files、reviews、merge、reviewer、update branch 走这条）
- **draft PR**：通过在 title 加 `WIP:` 前缀实现（gitea-mcp 暴露的 `draft` 参数本质是改 title）。

## 列出 PR

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls?state=open&sort=recentupdate&page=1&limit=50" \
  | jq '[.[] | {number, title, state, head: .head.ref, base: .base.ref, user: .user.login, mergeable, merged}]'
```

可选 query 参数：

| 参数 | 含义 |
|------|------|
| `state` | `open`（默认）/ `closed` / `all` |
| `sort` | `oldest` / `recentupdate`（默认）/ `recentclose` / `leastupdate` / `mostcomment` / `leastcomment` / `priority` |
| `milestone` | milestone ID |
| `labels` | 逗号分隔 label ID |
| `poster` | 创建者 username |
| `base_branch` | 限定目标分支名 |
| `page` / `limit` | 分页 |

## PR 详情

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}"
```

精简：

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}" \
  | jq '{number, title, state, body, mergeable, merged, head: {ref:.head.ref,sha:.head.sha}, base: .base.ref, user: .user.login}'
```

## 创建 PR

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{
    "title": "Add feature X",
    "body": "## Summary\n...",
    "head": "feat/x",
    "base": "main",
    "labels": [3],
    "milestone": 1,
    "reviewers": ["alice"],
    "team_reviewers": ["frontend"]
  }' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls"
```

字段说明（来自 swagger `CreatePullRequestOption`）：

| 字段 | 必填 | 说明 |
|------|------|------|
| `title` | 是 | draft 时手动加 `WIP: ` 前缀 |
| `body` | 否 | markdown |
| `head` | 是 | source 分支；跨仓库写 `username:branch` |
| `base` | 是 | target 分支 |
| `assignee` | 否 | 单个 username |
| `assignees` | 否 | username 数组 |
| `labels` | 否 | label ID 数组 |
| `milestone` | 否 | milestone ID |
| `reviewers` | 否 | username 数组（创建时一并请求评审，省去后续 `requested_reviewers` 调用） |
| `team_reviewers` | 否 | team slug 数组 |
| `due_date` | 否 | ISO 8601 |

跨仓库 PR 的 `head` 写法：`fork-owner:branch-name`。

## 编辑 PR

```bash
curl -fsSL -X PATCH -H "Content-Type: application/json" \
  -d '{"title":"Add feature X (rev2)","body":"updated","base":"develop"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}"
```

可改字段：`title`、`body`、`base`、`assignees`、`milestone`、`labels`、`state`（`open` 重开 / `closed` 关闭）、`due_date`、`unset_due_date`、`allow_maintainer_edit`。

切换 draft 状态：把 `title` 改为带或不带 `WIP: ` 前缀。

## 关闭 / 重开 PR

```bash
# 关闭
curl -fsSL -X PATCH -H "Content-Type: application/json" \
  -d '{"state":"closed"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}"
# 重开
curl -fsSL -X PATCH -H "Content-Type: application/json" \
  -d '{"state":"open"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}"
```

## Diff 与文件清单

### 拉取 diff（文本）

```bash
curl -fsSL -H "Accept: text/plain" \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}.diff"
```

`.patch` 后缀返回 mbox 格式。

### 改动文件清单

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/files?page=1&limit=50" \
  | jq '[.[] | {filename, status, additions, deletions, changes}]'
```

可选 query：

| 参数 | 含义 |
|------|------|
| `whitespace` | `ignore-all` / `ignore-change` / `ignore-eol` / `show-all`（diff 算行差时怎么处理空白） |
| `skip-to` | 跳到指定文件路径之后才开始返回（大 PR 分批拉文件用） |
| `page` / `limit` | 分页 |

### PR commits 列表

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/commits?page=1&limit=50" \
  | jq '[.[] | {sha: .sha[0:8], msg: (.commit.message | split("\n")[0]), author: .commit.author.name}]'
```

可选 query：

| 参数 | 含义 |
|------|------|
| `verification` | `true` 包含每个 commit 的 GPG 签名信息 |
| `files` | `true` 每个 commit 的 changed files 也包含进来 |
| `page` / `limit` | 分页 |

## 合并 PR

**这是高风险操作，合并前确认用户意图。**

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{
    "Do": "merge",
    "MergeTitleField": "Add feature X (#42)",
    "MergeMessageField": "Closes #41",
    "delete_branch_after_merge": true
  }' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/merge"
```

**注意大小写**：merge body 里 `Do`、`MergeTitleField`、`MergeMessageField`、`MergeCommitID` 是首字母大写（历史遗留）；`delete_branch_after_merge`、`force_merge`、`head_commit_id`、`merge_when_checks_succeed` 是 snake_case。这是 swagger 真实定义，照抄即可。

`Do` 取值（来自 swagger `MergePullRequestForm.Do.enum`）：

| 值 | 含义 |
|------|------|
| `merge` | 普通 merge commit |
| `rebase` | rebase 后 fast-forward |
| `rebase-merge` | rebase 后再做一个 merge commit |
| `squash` | squash 后单 commit |
| `fast-forward-only` | 仅 fast-forward，base 落后于 head 才能成功，否则 422 |
| `manually-merged` | 标记为已手动合并（须配合 `MergeCommitID`） |

其他字段：

| 字段 | 说明 |
|------|------|
| `MergeCommitID` | 配合 `manually-merged`，告诉 Gitea 已经手动合到哪个 commit |
| `delete_branch_after_merge` | 合并后删 head 分支 |
| `force_merge` | 即使检查未通过也合并 |
| `head_commit_id` | 期望的 head SHA，若实际 head 不匹配则 409 |
| `merge_when_checks_succeed` | CI 通过后自动合并（auto-merge） |

### 检查 PR 是否已合并

```bash
# 204 = merged, 404 = not merged
curl -sSL -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/merge"
```

### 取消已 schedule 的 auto-merge

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/merge"
```

## update_branch（让 PR 分支跟上 base）

```bash
curl -fsSL -X POST \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/update"
```

可加 `?style=merge` 或 `?style=rebase`。默认 merge。

## Reviewers

### 添加 reviewer

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"reviewers":["alice","bob"],"team_reviewers":["frontend"]}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/requested_reviewers"
```

### 移除 reviewer

```bash
curl -fsSL -X DELETE -H "Content-Type: application/json" \
  -d '{"reviewers":["alice"]}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/requested_reviewers"
```

## Review

Review 是一组评审动作的容器，可附带内联评论。一个 review 有四种状态：`PENDING`、`APPROVED`、`REQUEST_CHANGES`、`COMMENT`。

### 列出 review

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/reviews?page=1&limit=50" \
  | jq '[.[] | {id, user: .user.login, state, submitted_at, body}]'
```

### 单个 review

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/reviews/${REVIEW_ID}"
```

### Review 的内联评论

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/reviews/${REVIEW_ID}/comments" \
  | jq '[.[] | {id, path, position, body, user: .user.login}]'
```

### 创建 review

可一次性带上所有内联评论。`event` 决定状态：

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{
    "commit_id": "abc123...",
    "body": "Overall LGTM, two small nits.",
    "event": "APPROVED",
    "comments": [
      {"path":"src/foo.go","old_position":12,"body":"typo here"},
      {"path":"src/foo.go","new_position":34,"body":"can be simpler"}
    ]
  }' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/reviews"
```

字段说明：

- `commit_id`：评审针对的 head SHA（不写则取当前 head）
- `event`：`APPROVED` / `REQUEST_CHANGES` / `COMMENT` / 不传或 `PENDING`（暂存为 pending）
- `comments[]`:
  - `path`：相对仓库根的文件路径
  - `old_position`：在 old file（删除/未变行）上的行号
  - `new_position`：在 new file（新增/未变行）上的行号
  - `body`：评论文本

`old_position` 与 `new_position` 二选一即可，对应行号取自 `pulls/{n}/files` 响应的 patch hunks。

### 提交 pending review

如果先创建了 PENDING review（`event` 不传），后续提交：

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"event":"APPROVED","body":"Final approval"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/reviews/${REVIEW_ID}"
```

### 删除 review

```bash
curl -fsSL -X DELETE \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/reviews/${REVIEW_ID}"
```

### Dismiss review

驳回他人的 review（取消其 APPROVED / REQUEST_CHANGES 效力，常配合 PR 强制流程使用）：

```bash
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"message":"Outdated due to new commits","priors":false}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/reviews/${REVIEW_ID}/dismissals"
```

### 撤销 dismiss

```bash
curl -fsSL -X POST \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/reviews/${REVIEW_ID}/undismissals"
```

恢复被 dismiss 的 review 的效力。

## PR 状态（CI/合并检查）

PR head commit 的检查状态走 commit statuses endpoint：

```bash
HEAD_SHA=$(curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}" | jq -r '.head.sha')
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/commits/${HEAD_SHA}/statuses?page=1&limit=50" \
  | jq '[.[] | {context, state, description, target_url}]'
```

或综合状态：

```bash
curl -fsSL "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/commits/${HEAD_SHA}/status"
```

## 常见组合

### 完整发起 + 评审 + 合并

```bash
# 1. 建 PR
PR_NUM=$(curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"title":"feat: x","body":"...","head":"feat/x","base":"main"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls" | jq -r '.number')

# 2. 请求评审
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"reviewers":["alice"]}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${PR_NUM}/requested_reviewers"

# 3. （reviewer 操作）批准
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"event":"APPROVED","body":"LGTM"}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${PR_NUM}/reviews"

# 4. 合并 + 删分支
curl -fsSL -X POST -H "Content-Type: application/json" \
  -d '{"Do":"squash","delete_branch_after_merge":true}' \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${PR_NUM}/merge"
```

### 把 PR 分支与 base 同步

```bash
curl -fsSL -X POST \
  "${GITEA_HOST}/api/v1/repos/${OWNER}/${REPO}/pulls/${N}/update?style=rebase"
```

## 权限提示

| 操作 | scope |
|------|-------|
| 读 PR、diff、files | `read:repository` |
| 创建/编辑 PR | `write:repository` |
| 创建/提交 review | `write:repository`（且作为协作者） |
| 合并 PR | `write:repository`（且具备分支合并权限） |
