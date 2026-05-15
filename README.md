# gitea-skills

A set of 13 [agent skills](https://docs.claude.com/en/docs/claude-code/skills) that wrap the Gitea REST API, designed to replace the [gitea-mcp](https://gitea.com/gitea/gitea-mcp) server with progressive-disclosure markdown documents that consume far less LLM context.

Each skill loads only when the agent decides it's relevant. The agent then talks to Gitea via plain `curl` + `jq`, with no extra binary or daemon to install.

> **Why not the MCP server?** The MCP approach injects all ~80 tool schemas into every conversation, even ones unrelated to Gitea. That's a lot of context spent on schemas you may never call. With skills, the description of each domain (~100 words) lives in metadata; the full instructions only load when triggered.

## Tested against

- **Gitea 1.24.6** (production self-hosted instance)
- All endpoint paths and parameter names verified against the live `swagger.v1.json` of the same version
- Older Gitea versions (1.20–1.23) should work for most domains; `gitea-actions` and `gitea-shared` call out version-specific paths where they differ

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

Set two environment variables before invoking any Gitea skill:

```bash
# Self-hosted instance examples
export GITEA_HOST="https://git.internal.company.com"
# or with reverse-proxy path prefix
export GITEA_HOST="https://example.com/gitea"
# or HTTP intranet on non-standard port
export GITEA_HOST="http://192.168.1.10:3000"

# Personal Access Token from Settings → Applications → Manage Access Tokens
export GITEA_ACCESS_TOKEN="gta_xxxxxxxxxxxx"
```

The full configuration story (scopes for Gitea 1.20+, self-signed CA handling, `.netrc` alternative, git-side trust setup) lives in [gitea-shared/SKILL.md](gitea-shared/SKILL.md).

## Quick smoke test

```bash
# Connectivity (no token required)
curl -fsSL "${GITEA_HOST}/api/v1/version" | jq

# Token validity
curl -fsSL -H "Authorization: token ${GITEA_ACCESS_TOKEN}" \
  "${GITEA_HOST}/api/v1/user" | jq '{login, id}'
```

## Usage examples

Once installed, the agent picks the right skill based on what you ask:

- "list my open PRs in productivity org" → `gitea-search` triggers
- "create an issue in foo/bar with title 'memory leak'" → `gitea-issue`
- "what's the latest CI run status for foo/bar?" → `gitea-actions`
- "merge PR #42 in foo/bar with squash" → `gitea-pull` (will confirm before merging)

The agent reads the relevant SKILL.md, constructs the right `curl`, and executes. Destructive operations (merge, delete, secret PUT, workflow dispatch) require explicit user confirmation per the rules in `gitea-shared`.

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
