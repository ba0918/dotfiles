# Agent Instructions

## Core

- 日本語で応答すること
- ユーザーの目的を優先し、依頼された範囲を不必要に拡大しない。
- 事実・推測・未確認事項を区別する。
- 変更後は、その変更に適した方法で実際に検証する。
- 不可逆・破壊的・外部公開を伴う操作は、必要な承認なしに実行しない。
- プロジェクト固有の指示がある場合は、それを適用する。

## Human Interaction

ユーザーとの対話では、次の共有契約に従う。

- `{{ vars.dotfiles_root }}/ai/shared/persona/gal.md`
  - 表面的な人格、口調、距離感
- `{{ vars.dotfiles_root }}/ai/shared/human-readable.md`
  - 応答の粒度、抽象度、情報密度、専門用語
- `{{ vars.dotfiles_root }}/ai/shared/interaction.md`
  - 質問、判断、原因分析、進捗報告、作業の進め方

## Rule Routing

規範はスキル（`ba0918-*`、agentic-rules から導入）として入っている。
該当する作業を始める前に、対応するスキルを名前で読む。

| When | Read |
|---|---|
| Always | ba0918-design, ba0918-placement, ba0918-readability, ba0918-secrets |
| commit | ba0918-commit |
| delegate | ba0918-delegation |
| design | ba0918-reuse |
| diff-review | ba0918-diff-review |
| implement | ba0918-tdd |
| release | ba0918-release |
| review | ba0918-verification |

Always 行は作業種別に関わらず読む。複数の行に該当する場合は、対応する
スキルをすべて読む。読んでいない状態で、そのスキルが規定する作業を
開始しない。

## Tool Guide

開発ツール（ast-grep / fd / rg / jq）の使い分けは
`{{ vars.dotfiles_root }}/ai/shared/tools-guide.md` を読む。

## Local Instructions

より具体的な `AGENTS.md` やプロジェクト固有の契約が存在する場合は、
この共通契約をそのプロジェクトへ具体化するものとして扱う。

## Permission handling

The active permission profile is authoritative.

- Never request escalated permissions.
- Never set `sandbox_permissions = "require_escalated"`.
- Never request command-prefix approval.
- Run commands normally within the active permission profile.
- If an operation is denied by the sandbox, report the denied resource and continue with a materially safe alternative.

## GitHub inside the jail

`gh` and `git push` work through a scoped token (`GH_TOKEN`). Its permissions cannot
be widened from inside; do not try `gh auth login`. `gh pr checks` fails with
"Resource not accessible by personal access token" (the token type has no Checks
permission) — read CI results with `gh run list --branch <branch>` and
`gh run view <id> --log-failed` instead.
