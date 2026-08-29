# AGENTS.md

このリポジトリ用の AI エージェント向け指示書（実体）。
Codex / Cursor / Aider などで読み込まれる標準ファイル。Claude Code では
`CLAUDE.md` が本ファイルを参照する。

## プロジェクト概要

- 個人用 dotfiles（WSL2 + fish + 多数の dev ツール）
- 管理方式: **mise bootstrap** による宣言的シンボリックリンク展開
  (`[bootstrap.packages]` / `[dotfiles]` / `[tools]`)
- 各トップレベルディレクトリが「パッケージ」。パッケージ内のパスは `$HOME` からの
  相対パスをそのまま再現し、`mise/config.toml` の `[dotfiles]` source 宣言で
  `$HOME` にシンボリックリンク展開される
- グローバル config の実体は `mise/config.toml`（`MISE_GLOBAL_CONFIG_FILE` で参照）
- 使用者: 単一ユーザー / 単一マシンが現状、将来的にクロス環境の可能性あり

## 変更時に守るルール

### 1. Secret は絶対コミットしない

- `.env*` / `*.pem` / `*.key` / `auth.json` / `.credentials.json` / `.git-credentials`
  等は `.gitignore` で鉄壁ブロック済み
- `ai/claude/` や `ai/codex/` に新しいファイルを足すときは **credentials / history /
  sqlite / sessions / cache / backups が混入していないか必ず確認**する
- 新しい secret パスが発覚したら `.gitignore` と `ai/shared/deny-patterns.yaml` に
  追記する（deny-patterns.yaml が LLM の deny 設定の正本。
  詳細は [meta/LLM-SETTINGS.md](meta/LLM-SETTINGS.md)）
- `[bootstrap.secrets]` を使う場合も平文 secret を repo / config に永続化しない

### 2. symlink の副作用を意識する

- `~/.gitconfig` などツール経由で書き換えられるファイルは **symlink 経由で
  repo ファイルそのものが変更される**
- 例: `gh auth setup-git` / `glab auth login` が `~/.gitconfig` や `~/.ssh/config`
  に追記 → `git/.gitconfig` や repo 外の diff として検出される
- こうした外部書き込みは整理してからコミットする

### 3. スクリプトの出力は中立英語

- スクリプトの stdout/stderr、ヘッダコメント、エラーメッセージは
  **ニュートラルな英語**で書く（ペルソナ / 絵文字 / 親しみ口調は入れない）
- ユーザー向け会話文・README・コミットメッセージは**日本語**
- ドキュメントとスクリプトで言語を分けてる点に注意

### 4. 日本語で応答・コミット

- 会話応答は日本語
- コミットメッセージも日本語
- 技術用語とコード識別子は原形

### 5. mise は dry-run 先行

- `mise bootstrap --dry-run` で衝突・差分を確認してから実適用する
- `apply --force` は既存実ファイルを置き換えるため、内容を確認してから使う
- repo 内ファイルが symlink 化されないよう、git status で短期の変更を監視する

### 6. テストスキップの禁止

グローバル指針と同じ: 失敗するテストはスキップ (`skip` / `xit` / 削除) ではなく
修正で対応する。

この repo のテストは 2 系統あり、`mise run test`（`scripts/run-tests.sh`）で全部回る。
GitHub Actions（`.github/workflows/ci.yml`）も同じ入口を main への push で回すが、
PR 運用ではないので CI は入った後の検知器。対象を触ったら push 前に手元で回すこと
（コマンドは [docs/commands.md](docs/commands.md) のテスト節を参照）。

- **pytest** — `ai/shared/hooks/tests/`（security hooks）
- **bash ハーネス** — `scripts/test_*.sh`（生成スクリプト / ラッパ）

新しい bash スクリプトは CI の `mise run lint`（shellcheck）の対象に自動で入る
（git 管理下で bash の shebang を持つファイルすべて）。

### 7. 生成物は「空でも成功」させない

deny 設定のように**生成に失敗しても形だけ妥当なものが出る**種類の成果物は、
件数なり不変条件なりを検査して落とすところまで書く。過去に
`generate-deny.sh` が mawk 環境で 0 件を返しながら終了コード 0 で成功し、
deny が空の `settings.json` が黙って配布された。

同じ理由で、シェルスクリプトの正規表現は **POSIX 互換に保つ**。`\s` / `\d` などの
GNU 拡張は Debian/Ubuntu 既定の mawk では無言で一致しなくなる。

## hook を追加するときの制約

hook 設定で repo 外の対象（通知スクリプト、外部ツールの状態管理など）を
叩くときは、直接コマンドを書かず `run-optional.sh` を経由する。
新マシンでは依存が存在しないため、ラッパーが無音でスキップする。
コマンド自体の失敗はそのまま伝播する（壊れた依存は見えたままにする）。

参照先の一覧と呼び出し方は
[docs/dependencies.md](docs/dependencies.md) の「hook の repo 外依存」を参照。

## 参照先

| ドキュメント | 内容 |
|---|---|
| [docs/layout.md](docs/layout.md) | 構成・パッケージ一覧・追加手順 |
| [docs/commands.md](docs/commands.md) | コマンドリファレンス |
| [docs/dependencies.md](docs/dependencies.md) | 外部ツール依存・サプライチェーン対策・codex jail |
| [docs/troubleshooting.md](docs/troubleshooting.md) | トラブルシューティング |
| [meta/LLM-SETTINGS.md](meta/LLM-SETTINGS.md) | LLM 設定の conf.d / deny-patterns パイプライン |
| [meta/MIGRATION.md](meta/MIGRATION.md) | 既存設定の取り込み手順 |
