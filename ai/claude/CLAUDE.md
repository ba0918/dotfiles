# Agent Instructions

## Core

- 日本語で応答すること
- ユーザーの目的を優先し、依頼された範囲を不必要に拡大しない。
- 事実・推測・未確認事項を区別する。
- 変更後は、その変更に適した方法で実際に検証する。
- 不可逆・破壊的・外部公開を伴う操作は、必要な承認なしに実行しない。
- プロジェクト固有の指示がある場合は、それを適用する。

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

この環境では、diff-review の提示手段は `diff-review-viewer` スキルが担う。

## Local Instructions

より具体的な `AGENTS.md` やプロジェクト固有の契約が存在する場合は、
この共通契約をそのプロジェクトへ具体化するものとして扱う。
