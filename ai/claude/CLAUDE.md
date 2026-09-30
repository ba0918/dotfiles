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

## Rule Routing

規範は `ba0918-*` skill として提供される。
現在の作業に該当する skill のみ読む。

| When                                     | Read                        |
| ---------------------------------------- | --------------------------- |
| architecture / design decision           | ba0918-design, ba0918-reuse |
| implementation                           | ba0918-tdd                  |
| code readability concern                 | ba0918-readability          |
| information placement decision           | ba0918-placement            |
| secrets / credentials / sensitive config | ba0918-secrets              |
| commit                                   | ba0918-commit               |
| delegate to subagent                     | ba0918-delegation           |
| diff review                              | ba0918-diff-review          |
| release                                  | ba0918-release              |
| verification / review                    | ba0918-verification         |
| worktree                                 | ba0918-worktree             |

複数に該当する場合は必要なものを組み合わせる。
関連しない skill は予防的に読み込まない。

diff-review の提示には `kemi` skill を使う。

## Local Instructions

より具体的な `AGENTS.md` やプロジェクト固有の契約が存在する場合は、
この共通契約をそのプロジェクトへ具体化するものとして扱う。

## Verification

変更内容に応じた妥当な検証を行う。

影響範囲が限定されている場合は、その範囲に対応する検証を優先し、
無関係な広範囲の検証を必要なく実行しない。

安全なローカル検証は、途中で逐次承認を求めず、
失敗が今回の変更に起因する場合は修正して再実行してよい。

## レビューの任意の席（kotowari-review・ba0918-review）

kotowari-review と ba0918-review の full review で、quality のレビュー役に加えて立てる別モデルの席。数だけ指定されたときは上から順に使う。

- gpt: `ba0918-opencode-exec` で実行する。渡す値は次のとおり。
  - モデル: `openai/gpt-6-sol`
  - コマンド名: `opencode2`
  - 前置コマンド: `kakoi` `--profile` `external-review` `--policy-file` `{{ vars.dotfiles_root }}/ai/kakoi/policy/readonly-workspace.toml` `--`
  - 変更なし: 指定する
  - プロンプト: レビュー依頼をファイルに書いて渡す
  - 結果の読み方: stdout ファイルの最後のメッセージを finding の JSON として読む。stderr ファイルには opencode のログと kakoi の警告が入る
