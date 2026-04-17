# CLAUDE.md

このリポジトリ用の AI エージェント向け指示書。Codex / Cursor / Aider
などとの互換性のため `AGENTS.md` は本ファイルへの symlink にしてある。

## プロジェクト概要

- 個人用 dotfiles（WSL2 + fish + 多数の dev ツール）
- 管理方式: **GNU Stow** ベースのシンボリックリンク展開
- 使用者: 単一ユーザー / 単一マシンが現状、将来的にクロス環境の可能性あり

## レイアウト規則

トップレベルの各ディレクトリが Stow パッケージで、**そのツリーがそのまま
`$HOME` の下に symlink 展開される**。

```
dotfiles/
├── git/                       # 確定
│   ├── .gitconfig             # → ~/.gitconfig
│   └── .config/git/
│       ├── ignore             # → ~/.config/git/ignore   (XDG 自動検出)
│       └── attributes         # → ~/.config/git/attributes (XDG 自動検出)
├── fish/                      # 育成中
├── nvim/                      # 育成中
├── claude/                    # 育成中（secret 混入厳禁）
├── codex/                     # 育成中（secret 混入厳禁）
├── meta/
│   └── MIGRATION.md           # 既存 $HOME ファイルの取り込み手順
├── install.sh                 # stow 自動導入 + dry-run → link、--deps で外部ツール
├── Makefile                   # make install/check/unlink/relink
├── CLAUDE.md                  # このファイル（本体）
├── AGENTS.md                  # → CLAUDE.md（symlink）
└── .gitignore                 # secret / runtime artifact をブロック
```

新しいパッケージを追加するときは:

1. `mkdir -p <pkg>/<$HOME からの相対パス>` でツリーを作る
2. 設定ファイルを配置する
3. `.gitignore` に runtime / secret パターンを追記する
4. `./install.sh <pkg>` で dry-run → 実リンク

## コマンドリファレンス

```bash
# Stow 操作
./install.sh                   # デフォルト (git) を dry-run → 実リンク
./install.sh --dry-run         # 衝突チェックのみ
./install.sh --unlink          # symlink を剥がす
./install.sh --deps            # 外部ツール (stow / delta / GCM) を導入
./install.sh <pkg> [<pkg>...]  # 個別パッケージを対象にする

make list                      # パッケージ一覧
make check                     # 全パッケージ dry-run
make install                   # 全パッケージ install
make relink                    # unlink → install
make install-<pkg>             # 個別 install
```

## 変更時に守るルール

### 1. Secret は絶対コミットしない

- `.env*` / `*.pem` / `*.key` / `auth.json` / `.credentials.json` / `.git-credentials`
  等は `.gitignore` で鉄壁ブロック済み
- `claude/` や `codex/` に新しいファイルを足すときは **credentials / history /
  sqlite / sessions / cache / backups が混入していないか必ず確認**する
- 新しい secret パスが発覚したら `.gitignore` に追記する

### 2. symlink の副作用を意識する

- `~/.gitconfig` などツール経由で書き換えられるファイルは **symlink 経由で
  repo ファイルそのものが変更される**
- 例: `git-credential-manager configure` が `~/.gitconfig` に `helper = ...` を
  追記 → `git/.gitconfig` に差分発生 → `git status` で検出される
- こうした外部書き込みは整理してからコミットする

### 3. スクリプトの出力は中立英語

- `install.sh` などスクリプトの stdout/stderr、ヘッダコメント、エラーメッセージは
  **ニュートラルな英語**で書く（ペルソナ / 絵文字 / 親しみ口調は入れない）
- ユーザー向け会話文・README・コミットメッセージは**日本語**
- ドキュメントとスクリプトで言語を分けてる点に注意

### 4. 日本語で応答・コミット

- 会話応答は日本語
- コミットメッセージも日本語
- 技術用語とコード識別子は原形

### 5. stow は dry-run 先行

- 破壊的ではないが衝突すると途中で止まるので、`--dry-run` で確認してから実リンクする
- `install.sh` は install モードで自動的に `phase 1 (dry-run) → phase 2 (link)`
  を順に実行する

### 6. テストスキップの禁止

グローバル指針と同じ: 失敗するテストはスキップ (`skip` / `xit` / 削除) ではなく
修正で対応する。dotfiles には今のところテストがないが、将来スクリプト化された
検証を足すときの方針として保持。

## 外部ツール依存

`git/.gitconfig` は以下に依存。`./install.sh --deps` で一括導入:

- **[delta](https://github.com/dandavison/delta)** — `core.pager` と
  `interactive.diffFilter`
- **[git-credential-manager](https://github.com/git-ecosystem/git-credential-manager)**
  — `credential.helper` / WSL では `credentialStore = wincredman` で Windows
  Credential Manager (DPAPI) に資格情報を保存

## トラブルシュート

| 症状 | 原因と対処 |
|------|-----------|
| `stow` で "existing target is neither a link nor a directory" | $HOME 側に実ファイルがある。バックアップして退避してから再実行 |
| `git` 実行時に `delta: command not found` | delta 未導入。`./install.sh --deps` で入れるか一時的に `git -c core.pager=less ...` で回避 |
| `~/.gitconfig` に突然大量の差分 | `gcm configure` などツールが symlink 先に書き込んだ可能性。差分を確認して整理する |
| Windows 側でコピーしたファイルに `:Zone.Identifier` が付く | global ignore で除外済み (`~/.config/git/ignore`) |

## 関連ドキュメント

- [README.md](README.md) — 外向け / ユーザー向けの案内
- [meta/MIGRATION.md](meta/MIGRATION.md) — 既存 `~/.config/*` を取り込む手順
