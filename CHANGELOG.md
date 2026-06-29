# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] – 2026-06-29

### Changed

- Recalibrated all skills against Gitea **1.26.4** OpenAPI (`gitea.quantpi.cn`).
- **`gitea-actions`**: major rewrite for 1.25+ Actions API:
  - Primary run listing via `GET /actions/runs` (replaces `/actions/tasks` as default).
  - Single run detail (`GET /actions/runs/{run}`), delete run, rerun run/failed-jobs/single-job.
  - List jobs (`GET /actions/runs/{run}/jobs`, `GET /actions/jobs`), job detail, job logs with correct `job_id`.
  - Document `status` + `conclusion` dual-field model on runs/jobs.
  - Keep `/actions/tasks` documented as 1.24.x fallback.
- **`gitea-shared`**: updated version compatibility matrix for 1.25+/1.26.4.
- CI compatibility matrix extended to Gitea **1.26**.
- Smoke tests probe `/actions/runs` in addition to `/actions/tasks`.

### Known limitations (Gitea 1.26.4 API)

- No `POST /actions/runs/{run}/cancel` — cancel via Web UI only.

### Fixed (relative to 1.24.6 baseline)

- Job logs, list jobs, run detail, and rerun endpoints are now documented and usable on 1.25+.

[Unreleased]: https://github.com/d0zingcat/gitea-skills/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/d0zingcat/gitea-skills/compare/v0.0.1...v0.1.0

## [0.0.1] – 2026-05-15

### Added

- 13 `gitea-*` agent skills covering the full surface area of the Gitea REST API.
- `gitea-shared`: auth, host config, TLS / self-signed CA, reverse-proxy path prefix,
  pagination, error handling, version compatibility matrix, security rules.
  First-class support for self-hosted Gitea instances (HTTP/HTTPS, intranet hostnames,
  disabled modules).
- `gitea-repo`: repos, branches, commits, file read/write (incl. `from_path` rename),
  tags, releases, tree.
- `gitea-issue`: issues, comments, labels association, **reactions**.
- `gitea-pull`: PRs, reviews, merge (with `fast-forward-only` + `manually-merged`),
  reviewers (incl. on create), update branch, **PR commits**, **undismissals**, dismiss,
  is-merged check, files (with `whitespace` / `skip-to`).
- `gitea-actions`: workflows (incl. enable/disable), runs (`/actions/tasks`),
  job logs, **artifacts** (full lifecycle), **runners** (repo/org/user/admin),
  secrets and variables (repo/org/user level).
- `gitea-wiki`: pages, revisions; corrected jq fields (`last_commit.sha`,
  `author.date`); content always base64.
- `gitea-label`: repo + org labels; color accepts `#xxxxxx` or `xxxxxx`.
- `gitea-milestone`: repo milestones with `due_on`.
- `gitea-notification`: list (with correct lowercase `subject-type` query),
  mark read (single thread + scoped batch).
- `gitea-search`: cross-repo issues/PRs (with `reviewed`), repo search (correct
  `sort` enum: `alpha/created/updated/size/git_size/lfs_size/stars/forks/id`),
  user search, org team search.
- `gitea-user`: current user, user orgs, instance version.
- `gitea-package`: list/versions/latest/files, **link/unlink** to repo, delete;
  full type enum (`alpine/cargo/chef/composer/conan/conda/container/cran/debian/
  generic/go/helm/maven/npm/nuget/pub/pypi/rpm/rubygems/swift/vagrant`).
- `gitea-timetracking`: stopwatch, time entries; jq uses `user_name` instead of
  deprecated `user_id`.

### Verified

All endpoint paths, parameter names, response field names, and HTTP methods are
verified against the live `swagger.v1.json` of Gitea **1.24.6**.
Live read-only smoke tests run on a self-hosted production instance.

### Known limitations (Gitea 1.24.6 API)

These are absent from the upstream API itself, not the skills:

- No `GET /actions/runs/{id}` (single-run details).
- No list-jobs endpoint; `job_id` must come from external sources (webhook payload, web UI).
- No cancel-run or rerun-run endpoint.
- All documented in `gitea-actions/SKILL.md` with Web UI fallbacks.

[0.0.1]: https://github.com/d0zingcat/gitea-skills/releases/tag/v0.0.1
