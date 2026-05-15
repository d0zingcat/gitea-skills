# gitea-skills

[![lint](https://github.com/d0zingcat/gitea-skills/actions/workflows/lint.yml/badge.svg)](https://github.com/d0zingcat/gitea-skills/actions/workflows/lint.yml)
[![compatibility-matrix](https://github.com/d0zingcat/gitea-skills/actions/workflows/compatibility.yml/badge.svg)](https://github.com/d0zingcat/gitea-skills/actions/workflows/compatibility.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Gitea 1.21–1.25](https://img.shields.io/badge/Gitea-1.21%E2%80%931.25-success)](#%E5%85%BC%E5%AE%B9%E6%80%A7)

> 中文 (you are here) · [English](README.en.md)

把 [gitea-mcp](https://gitea.com/gitea/gitea-mcp) 的 80 多个 tool 用 13 个 [agent skill](https://docs.claude.com/en/docs/claude-code/skills) 重新组织。每个 skill 是一份按需加载的 markdown 文档，整体让 LLM 上下文占用大幅下降。

只在 agent 判断"和 Gitea 相关"时才会把对应 SKILL.md 注入上下文；agent 接着用纯 `curl` + `jq` 跟 Gitea 通信，**不需要额外安装任何二进制或 daemon**。

> **为什么不直接用 MCP server？** MCP 的工作方式是把全部 80 余个 tool schema 一次性塞进每次对话，哪怕本次根本用不上 Gitea。skill 模式下，每个域只在元数据里留约 100 字的描述，详细指令在被触发时才加载。

## 兼容性

[![compatibility-matrix](https://github.com/d0zingcat/gitea-skills/actions/workflows/compatibility.yml/badge.svg)](https://github.com/d0zingcat/gitea-skills/actions/workflows/compatibility.yml)

CI 每周一自动跑 [兼容矩阵](.github/workflows/compatibility.yml)，对每个版本拉起 fresh Gitea 容器，用 admin token 跑创建 repo / 分支 / 文件 / issue / 评论 / 标签 / 里程碑 / PR / diff / 搜索 / 通知 / actions 路由探针约 30 项断言。

| Gitea | 状态 | 备注 |
|---|---|---|
| 1.25 | ✅ | 全部 30 项通过 |
| 1.24 | ✅ | 全部 30 项通过（也是文档校准的基准版本） |
| 1.23 | ✅ | 28 项通过；search `sort=created` 在该版本不可用，已跳过 |
| 1.22 | ✅ | 27 项通过；同 1.23 + 一项 search sort 兼容跳过 |
| 1.21 | ✅ | 27 项通过 |

整套 skill **面向自部署 Gitea 实例**：内网域名、自签名证书、反向代理 path 前缀、HTTP 明文部署、被禁用的模块——`gitea-shared` 都覆盖了。

## 13 个 skill

| Skill | 范围 | 触发场景 |
|-------|------|---------|
| [gitea-shared](gitea-shared/SKILL.md) | 认证、host、TLS、分页、错误处理、版本兼容、安全规则 | 第一次用 Gitea、SSL 错误、401/403/404、配 `GITEA_HOST`/`GITEA_ACCESS_TOKEN` |
| [gitea-repo](gitea-repo/SKILL.md) | 仓库、分支、commit、文件读写、tag、release、tree | 创建/列出/fork 仓库、管理分支、读写文件、打 tag、发 release |
| [gitea-issue](gitea-issue/SKILL.md) | issue、评论、标签关联、表情回应 | 提 issue、评论、改状态、打标签 |
| [gitea-pull](gitea-pull/SKILL.md) | PR、review、合并、reviewers、diff/files/commits | 提交 PR、走代码评审、合并 PR、撤销 review |
| [gitea-actions](gitea-actions/SKILL.md) | workflows、runs（tasks）、job 日志、artifacts、runners、secrets/variables（仓库/组织/用户级）、enable/disable | 看 CI、手动 dispatch、查 build 日志、管理 runner |
| [gitea-wiki](gitea-wiki/SKILL.md) | Wiki 页面、修订历史 | 在 Gitea Wiki 上写文档 |
| [gitea-label](gitea-label/SKILL.md) | 仓库 + 组织 label | 管理标签、批量创建、归档 |
| [gitea-milestone](gitea-milestone/SKILL.md) | 仓库里程碑 | 创建/关闭里程碑、设置截止时间 |
| [gitea-notification](gitea-notification/SKILL.md) | 用户通知收件箱 | 看 Gitea 收件箱、批量已读 |
| [gitea-search](gitea-search/SKILL.md) | 跨仓库搜 issue/PR、找仓库、用户、团队 | 全实例查找 |
| [gitea-user](gitea-user/SKILL.md) | 当前用户、所属组织、实例版本 | 验证身份、查所属 org、看 Gitea 版本 |
| [gitea-package](gitea-package/SKILL.md) | 包注册中心（container/npm/maven/...） | 浏览包、清理旧版本、绑到仓库 |
| [gitea-timetracking](gitea-timetracking/SKILL.md) | issue 秒表、工时记录 | 给 issue 计时、按仓库/人统计 |

总文档量 2756 行，单文件均 < 500 行（符合 skill-creator 规范）。

## 安装

### 方式 A：npx skills add（推荐）

```bash
npx skills add d0zingcat/gitea-skills -g --all
```

一行搞定，自动 clone + 全部 13 个 skill 一次性 symlink 到 agent skill 目录。

### 方式 B：手动克隆 + symlink

```bash
git clone https://github.com/d0zingcat/gitea-skills.git ~/code/gitea-skills

mkdir -p ~/.agents/skills
for d in ~/code/gitea-skills/gitea-*/; do
  ln -s "$d" ~/.agents/skills/
done
```

安装完后重启 agent 让它扫到新 skill。

## 配置

克隆后运行一次：

```bash
bash setup.sh
```

交互式输入 Gitea host 和 PAT，验证连通性，写入 `~/.config/gitea-skills/config`（chmod 600）。之后 skill 自动读取，**无需手动 export 任何变量**。

- 更新 token：`bash setup.sh`（再次运行覆盖）
- 删除配置：`bash setup.sh --uninstall`

完整说明（自签 CA / 反向代理 path 前缀 / scope 选择）见 [gitea-shared/SKILL.md](gitea-shared/SKILL.md)。

## 用法示例

详见 [examples/](examples/) 目录的完整演示：

| # | 示例 | 涉及 skill |
|---|------|-----------|
| 1 | [跨仓库列出我的 open PR](examples/01-list-my-open-prs.md) | `gitea-search` |
| 2 | [建一个 bug issue 并打标签](examples/02-create-issue-and-label.md) | `gitea-issue` + `gitea-label` |
| 3 | [合并 PR 的安全流程](examples/03-merge-pr-with-confirmation.md) | `gitea-pull` |
| 4 | [触发 workflow 并轮询结果](examples/04-trigger-and-wait-workflow.md) | `gitea-actions` |
| 5 | [清理旧的 container 版本](examples/05-cleanup-old-package-versions.md) | `gitea-package` |

安装好之后，agent 会根据你说什么挑对应 skill。破坏性操作（merge、delete、PUT secret、workflow dispatch）按 `gitea-shared` 的规则，必须先和你确认。

## 设计原则

1. **纯 curl + jq，零额外依赖。** 每个示例都是可直接粘贴的 shell。
2. **OpenAPI 是真理。** 当 gitea-mcp 源码和 Gitea OpenAPI 不一致，以 OpenAPI 为准。skill 也提示 agent 在不确定时直接 jq `${GITEA_HOST}/swagger.v1.json`。
3. **渐进式加载。** 顶层描述约 100 字；完整 SKILL.md 只在被触发时加载。
4. **自部署优先。** TLS、反代、模块开关都是一等公民。
5. **安全护栏。** token 不回显、破坏性操作必确认、API 缺失时给出 Web UI 退路。

## Gitea 1.24.6 的已知 API 缺口

下列限制来自 Gitea 上游 API 本身，不是 skill 的锅：

- 没有 `GET /actions/runs/{id}`（单 run 详情）
- 没有 list-jobs API；要拉 job log 必须从外部（webhook 回调、Web UI）拿到 `job_id`
- 没有 cancel-run / rerun-run

`gitea-actions/SKILL.md` 给出"打开 Web UI"的退路。

## 贡献

欢迎 issue 和 PR。我们的迭代流程：

1. 读 gitea-mcp 的 Go 源码盘点 endpoint
2. 对照 `${GITEA_HOST}/swagger.v1.json` 找差异
3. 在真实 Gitea 实例上跑只读冒烟
4. 两边都过才合入

如果你在某个非 1.24.6 的 Gitea 版本上发现行为不一样，请提 issue 附：

- Gitea 版本（`/api/v1/version` 输出）
- 出问题的 endpoint 路径
- 实测 vs 文档预期的差异

## License

[MIT](LICENSE)
