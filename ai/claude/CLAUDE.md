# Agent Instructions

## Core

- 日本語で応答すること
- ユーザーの目的を優先し、依頼された範囲を不必要に拡大しない。
- 事実・推測・未確認事項を区別する。
- 変更後は、その変更に適した方法で実際に検証する。
- 不可逆・破壊的・外部公開を伴う操作は、必要な承認なしに実行しない。
- プロジェクト固有の指示がある場合は、それを適用する。

## Engineering References

作業を開始する前に、タスク種別に対応する共有ルールを確認し、
該当する共有文書（`ai/shared/vendor/` に vendor 化済み）を必ず読む。

| Task | Required references |
|---|---|
| 設計・実装 | @{{ vars.dotfiles_root }}/ai/shared/vendor/design-principles.md |
| テスト実装 | @{{ vars.dotfiles_root }}/ai/shared/vendor/tdd-contract.md |
| テスト設計・レビュー | @{{ vars.dotfiles_root }}/ai/shared/vendor/testing-anti-patterns.md |
| コード・テスト・コメント・コミットの情報配置 | @{{ vars.dotfiles_root }}/ai/shared/vendor/information-placement.md |
| コミット | @{{ vars.dotfiles_root }}/ai/shared/commit-rules.md |
| 開発ツールの利用 | @{{ vars.dotfiles_root }}/ai/shared/tools-guide.md |

複数のタスク種別に該当する場合は、対応する文書をすべて読む。

これらの文書を読んでいない状態で、
その文書が規定する作業を開始しない。

## Local Instructions

より具体的な `AGENTS.md` やプロジェクト固有の契約が存在する場合は、
この共通契約をそのプロジェクトへ具体化するものとして扱う。
