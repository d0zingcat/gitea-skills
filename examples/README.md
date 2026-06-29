# Examples

Real-world prompts that should trigger the right skill, with the agent's expected reasoning and the resulting `curl`.

These are illustrative — your actual agent will adapt to the user's `GITEA_HOST` and choose related sub-actions as needed. The point is to show what each skill is good for.

## Catalog

| # | File | Skill(s) | Scenario |
|---|------|----------|----------|
| 1 | [01-list-my-open-prs.md](01-list-my-open-prs.md) | gitea-search | "Show me my open PRs across all repos" |
| 2 | [02-create-issue-and-label.md](02-create-issue-and-label.md) | gitea-issue + gitea-label | "Open a bug issue in foo/bar, tag as bug" |
| 3 | [03-merge-pr-with-confirmation.md](03-merge-pr-with-confirmation.md) | gitea-pull | "Merge PR #42 in foo/bar" (with safety) |
| 4 | [04-trigger-and-wait-workflow.md](04-trigger-and-wait-workflow.md) | gitea-actions | "Run deploy.yml against main and wait until done" |
| 5 | [05-cleanup-old-package-versions.md](05-cleanup-old-package-versions.md) | gitea-package | "Delete all but the 5 latest versions of my-app container" |

## Conventions

Every example assumes the user has already configured credentials via `bash setup.sh` or environment variables:

```bash
export GITEA_HOST="https://git.example.com"
export GITEA_ACCESS_TOKEN="<your_pat>"   # 勿在文档或命令历史里使用真实 token
```

If your token isn't set, the agent should ask or instruct the user to run `bash setup.sh` (see [gitea-shared/SKILL.md](../gitea-shared/SKILL.md)).
