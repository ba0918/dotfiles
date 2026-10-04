# Agent Instructions

## Core

* 日本語で応答する。
* ユーザーの目的と依頼範囲を優先し、不必要に作業を拡大しない。
* 事実・推測・未確認事項を区別する。
* プロジェクト固有の指示がある場合は、それを優先して適用する。

## Workflow Routing

`ba0918-using-workflow` は、依頼が複数工程の開発作業であり、
brainstorm / plan / implement / review などの進め方を選ぶ必要がある場合に読む。

単純な質問、調査、説明、軽微な修正、明示された単一作業では、
workflow を適用する必要はない。

ユーザーが特定の workflow や skill を明示した場合は、それに従う。

## Human Interaction

ユーザーとの対話では、次の共有契約に従う。

- `{{ vars.dotfiles_root }}/ai/shared/persona/gal.md`
  - 表面的な人格、口調、距離感
- `{{ vars.dotfiles_root }}/ai/shared/human-readable.md`
  - 応答の粒度、抽象度、情報密度、専門用語
- `{{ vars.dotfiles_root }}/ai/shared/interaction.md`
  - 質問、判断、原因分析、進捗報告、作業の進め方

## Rule Routing

規範は `ba0918-*` skill として提供される。
現在の作業に該当する skill のみ読む。

| When                                     | Read                        |
| ---------------------------------------- | --------------------------- |
| architecture / design decision           | ba0918-design, ba0918-reuse |
| implementation                           | ba0918-tdd                  |
| code readability concern                 | ba0918-readability          |
| information placement decision           | ba0918-placement            |
| document creation / organization / pruning | ba0918-documents           |
| secrets / credentials / sensitive config | ba0918-secrets              |
| commit                                   | ba0918-commit               |
| delegate to subagent                     | ba0918-delegation           |
| diff review                              | ba0918-diff-review          |
| release                                  | ba0918-release              |
| CI / CD pipeline (workflow files)        | ba0918-ci                   |
| mutation testing (run / configure / CI)  | ba0918-mutation-testing     |
| verification / review                    | ba0918-verification         |
| worktree                                 | ba0918-worktree             |

複数に該当する場合は必要なものを組み合わせる。
関連しない skill は予防的に読み込まない。

文書ファイルを作るか判断するとき、配置・移動・削除を決めるとき、
古い文書を棚卸しするときは `ba0918-documents` を読む。

diff-review の提示には `kemi` skill を使う。

## Tool Guide

開発ツールの選択に迷った場合は
`{{ vars.dotfiles_root }}/ai/shared/tools-guide.md` を参照する。

既に適切なツールが明らかな場合は、事前に読む必要はない。

## Local Instructions

より具体的な `AGENTS.md` やプロジェクト固有の契約が存在する場合は、
この共通契約をそのプロジェクトへ具体化するものとして扱う。

## Verification

変更内容に応じた妥当な検証を行う。

影響範囲が限定されている場合は、その範囲に対応する検証を優先し、
無関係な広範囲の検証を必要なく実行しない。

安全なローカル検証は、途中で逐次承認を求めず、
失敗が今回の変更に起因する場合は修正して再実行してよい。

## Subagent operation rules

- Subagents in Codex consume many tokens. Invoke one only when the task needs a fresh context, such as a review from a different perspective.
- Whenever you call `wait_agent`, set `timeout_ms` to double the estimated time left until completion, in milliseconds. Make sure this fits within the tool’s min and max limits. If you cannot estimate the remaining time, simply use the default value. There is no need to shorten the wait time for quick checks, since notifications will cancel it early anyway. If a timeout happens, recalculate the expected completion time and wait again based on the same rules.

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
