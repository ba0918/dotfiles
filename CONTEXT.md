# CONTEXT.md

このリポジトリで 2 通りに読める言葉の読みと、使わない言い方。意味の典拠は各仕様書
（`docs/spec/`）で、ここは索引。

## Safe Chain のシム

`~/.safe-chain/shims/` にある実行ファイル群。自分のディレクトリを PATH から外して
`safe-chain <コマンド>` を exec し、Safe Chain が PATH の次の本体を実行する。典拠:
`docs/spec/safe-chain-path.md` 2 章。

使わない言い方: 単に「シム」（kakoi のシム `ai/kakoi/shim/codex` と区別が
つかない）。

## Safe Chain の本体

`~/.safe-chain/bin/safe-chain`。シムが exec する先。典拠: 同上。

## 直書きの要素

`ai/claude/conf.d/40-env.json` の `env.PATH`（conf.d の合成後の値）を `:` で分割した要素の
うち、末尾の `$PATH` という字句を除き、`$HOME` と `$DOTFILES_ROOT` だけを絶対パスに展開した列。
継承した PATH は含まない。典拠: `docs/spec/safe-chain-path.md` 2 章。

使わない言い方: 「settings.json の PATH」（生成物の展開後の列を指してしまう）。
