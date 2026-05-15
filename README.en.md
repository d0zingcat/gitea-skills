# gitea-skills

[![lint](https://github.com/d0zingcat/gitea-skills/actions/workflows/lint.yml/badge.svg)](https://github.com/d0zingcat/gitea-skills/actions/workflows/lint.yml)
[![compatibility-matrix](https://github.com/d0zingcat/gitea-skills/actions/workflows/compatibility.yml/badge.svg)](https://github.com/d0zingcat/gitea-skills/actions/workflows/compatibility.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Gitea 1.21–1.25](https://img.shields.io/badge/Gitea-1.21%E2%80%931.25-success)](#tested-against)

> [中文](README.md) · English (you are here)

A set of 13 [agent skills](https://docs.claude.com/en/docs/claude-code/skills) that wrap the Gitea REST API, designed to replace the [gitea-mcp](https://gitea.com/gitea/gitea-mcp) server with progressive-disclosure markdown documents that consume far less LLM context.

Each skill loads only when the agent decides it's relevant. The agent then talks to Gitea via plain `curl` + `jq`, with no extra binary or daemon to install.

> **Why not the MCP server?** The MCP approach injects all ~80 tool schemas into every conversation, even ones unrelated to Gitea. That's a lot of context spent on schemas you may never call. With skills, the description of each domain (~100 words) lives in metadata; the full instructions only load when triggered.

## Tested against

[![compatibility-matrix](https://github.com/d0zingcat/gitea-skills/actions/workflows/compatibility.yml/badge.svg)](https://github.com/d0zingcat/gitea-skills/actions/workflows/compatibility.yml)

CI runs the [compatibility matrix](.github/workflows/compatibility.yml) weekly: a fresh Gitea container per version, an admin token, ~30 assertions covering create repo / branch / file / issue / comment / label / milestone / PR / diff / search / notifications / actions endpoints.

| Gitea | Status | Notes |
|---|---|---|
| 1.25 | ✅ | 30/30 |
| 1.24 | ✅ | 30/30 — baseline version the docs were calibrated on |
| 1.23 | ✅ | 28/30 — `search?sort=created` not available, intentionally skipped |
| 1.22 | ✅ | 27/30 — same as 1.23 plus one extra search-sort skip |
| 1.21 | ✅ | 27/30 |

The skills are **designed for self-hosted Gitea instances**: internal hostnames, self-signed certificates, reverse-proxy path prefixes, HTTP-only deployments, disabled modules — all covered in `gitea-shared`.

## The 13 skills

| Skill | What it covers | When it triggers |
|-------|---------------|------------------|
| [gitea-shared](gitea-shared/SKILL.md) | Auth, host config, TLS, pagination, error handling, version compat, security rules | First time using Gitea, SSL errors, 401/403/404, configuring `GITEA_HOST`/`GITEA_ACCESS_TOKEN` |
| [gitea-repo](gitea-repo/SKILL.md) | Repos, branches, commits, file read/write, tags, releases, tree | Create/list/fork repos, manage branches, read or edit files, tag, release, browse tree |
| [gitea-issue](gitea-issue/SKILL.md) | Issues, comments, labels assoc., reactions | File issues, comment, change state, label issues |
| [gitea-pull](gitea-pull/SKILL.md) | PRs, reviews, merge, reviewers, diff/files/commits | Open/merge PRs, run code review flow, dismiss reviews |
| [gitea-actions](gitea-actions/SKILL.md) | Workflows, runs (tasks), job logs, artifacts, runners, secrets/variables (repo/org/user), enable/disable | CI status, dispatch workflows, fetch build logs, manage runners |
| [gitea-wiki](gitea-wiki/SKILL.md) | Wiki pages, revisions | Manage repo wiki content |
| [gitea-label](gitea-label/SKILL.md) | Repo + org labels | Manage labels, batch create, archive |
| [gitea-milestone](gitea-milestone/SKILL.md) | Repo milestones | Create/close milestones, set due dates |
| [gitea-notification](gitea-notification/SKILL.md) | User notifications | Inbox, mark read, scope by repo/subject |
| [gitea-search](gitea-search/SKILL.md) | Cross-repo issues/PRs, repos, users, org teams | Find things across the instance |
| [gitea-user](gitea-user/SKILL.md) | Current user, user orgs, instance version | Verify identity, list joined orgs, check Gitea version |
| [gitea-package](gitea-package/SKILL.md) | Packages registry (container/npm/maven/...) | Browse packages, clean old versions, link to repos |
| [gitea-timetracking](gitea-timetracking/SKILL.md) | Issue stopwatches, time entries | Track issue time, report by repo/user |

Total: 2,756 lines, all individual SKILL.md under 500 lines per skill-creator guidelines.

## Installation

These skills follow the standard agent-skill layout (`<skill-name>/SKILL.md` with YAML frontmatter). Install by pointing your agent's skill loader at this directory.

### Option A: clone + symlink (simple)

```bash
git clone https://your-gitea/your-org/gitea-skills.git ~/code/gitea-skills

# Then link each skill into the agent's skills directory.
# Adjust the target path to your agent (Claude Code, OpenCode, etc.).
mkdir -p ~/.agents/skills
for d in ~/code/gitea-skills/gitea-*/; do
  ln -s "$d" ~/.agents/skills/
done
```

### Option B: clone directly into the skills dir

```bash
cd ~/.agents/skills
git clone https://your-gitea/your-org/gitea-skills.git tmp
mv tmp/gitea-* .
rm -rf tmp
```

After installation, restart the agent so it picks up the new skills.

## Configuration

After cloning, run once:

```bash
bash setup.sh
```

It interactively asks for your Gitea host and PAT, validates connectivity, and writes to `~/.config/gitea-skills/config` (chmod 600). Skills auto-load this file — **no manual export needed**.

- Update token: `bash setup.sh` (run again to overwrite)
- Remove config: `bash setup.sh --uninstall`

Full details (self-signed CA, reverse-proxy path prefix, scope selection) in [gitea-shared/SKILL.md](gitea-shared/SKILL.md).

## Usage examples

See [examples/](examples/) for full walkthroughs:

| # | Example | Skill(s) |
|---|---------|---------|
| 1 | [List my open PRs across repos](examples/01-list-my-open-prs.md) | `gitea-search` |
| 2 | [Open a bug issue and label it](examples/02-create-issue-and-label.md) | `gitea-issue` + `gitea-label` |
| 3 | [Merge a PR with safety checks](examples/03-merge-pr-with-confirmation.md) | `gitea-pull` |
| 4 | [Trigger and wait for a workflow](examples/04-trigger-and-wait-workflow.md) | `gitea-actions` |
| 5 | [Clean up old container versions](examples/05-cleanup-old-package-versions.md) | `gitea-package` |

Once installed, the agent picks the right skill based on what you ask. Destructive operations (merge, delete, secret PUT, workflow dispatch) require explicit user confirmation per the rules in `gitea-shared`.

## Design principles

1. **Plain curl + jq, no extra dependencies.** Every example is a real shell command you could paste.
2. **Swagger as ground truth.** When the gitea-mcp source code and Gitea OpenAPI disagreed, the OpenAPI won. The skills tell the agent to consult `${GITEA_HOST}/swagger.v1.json` whenever uncertain.
3. **Progressive disclosure.** Top-level descriptions are ~100 words. Full SKILL.md only loads when triggered. Reference sections inside each skill are easy to skim.
4. **Self-hosted by default.** TLS, reverse proxy, disabled modules are first-class concerns.
5. **Security guardrails.** Tokens never echoed; destructive ops always confirmed; Web UI fallback when API is missing.

## Limitations / known gaps in Gitea 1.24.6

These come from the Gitea API itself, not the skills:

- No `GET /actions/runs/{id}` (single-run details endpoint)
- No `list jobs` API; you must already know the `job_id` to fetch logs
- No `cancel run` or `rerun run` endpoint
- These are documented in `gitea-actions/SKILL.md` with "open the Web UI" fallbacks

## Contributing

Issues and PRs welcome. The skill-creator workflow we used:
1. Read gitea-mcp Go source for endpoint inventory
2. Diff against `${GITEA_HOST}/swagger.v1.json`
3. Run live smoke tests against a real Gitea instance
4. Iterate until both pass

If you find an endpoint that behaves differently on a Gitea version other than 1.24.6, please open an issue with:
- Gitea version (`/api/v1/version`)
- Endpoint path
- Observed vs expected behavior

## License

[MIT](LICENSE)
