# AGENTS.md

このリポジトリ用の AI エージェント向け指示書（実体）。
Codex / Cursor / Aider などで読み込まれる標準ファイル。Claude Code では
`CLAUDE.md` が本ファイルを参照する。

## プロジェクト概要

- 個人用 dotfiles（WSL2 + fish + 多数の dev ツール）
- 管理方式: **mise bootstrap** による宣言的シンボリックリンク展開
  (`[bootstrap.packages]` / `[dotfiles]` / `[tools]`)
- 使用者: 単一ユーザー / 単一マシンが現状、将来的にクロス環境の可能性あり

## レイアウト規則

トップレベルの各ディレクトリがパッケージ（旧 Stow パッケージ）で、
`[dotfiles]` の source 宣言を通じて `$HOME` の下に symlink 展開される。
グローバル config の実体は `mise/config.toml`（`MISE_GLOBAL_CONFIG_FILE` で参照）で、
その `[dotfiles]` が repo 内の相対パスを source に指す。

```
dotfiles/
├── git/                       # 確定
│   ├── .gitconfig             # → ~/.gitconfig
│   └── .config/git/
│       ├── ignore             # → ~/.config/git/ignore   (XDG 自動検出)
│       ├── attributes         # → ~/.config/git/attributes (XDG 自動検出)
│       └── template/          # → ~/.config/git/template
├── fish/                      # 手動ファイルのみ（プラグインは fish_plugins で管理）
│   └── .config/fish/          # config.fish / fish_plugins / up.fish / clipboard2path.fish
├── apt/                       # 同梱 apt リポジトリ（bootstrap.sh が導入）
│   └── fish-shell-ubuntu-release-4-noble.sources    # fish 4.x PPA
├── nvim/                      # 育成中
├── claude/                    # 育成中（secret 混入厳禁）
├── codex/                     # 育成中（secret 混入厳禁）
├── mise/
│   └── config.toml            # グローバル config 実体（MISE_GLOBAL_CONFIG_FILE）
├── meta/
│   └── MIGRATION.md           # 既存 $HOME ファイルの取り込み手順
├── bootstrap.sh                # 新規マシン用 wrapper（config 解決 + trust + apt 設定）
├── install.sh                  # GCM 専用インストーラ（apt）
├── CLAUDE.md                  # Claude Code 用エントリ（AGENTS.md を参照）
├── AGENTS.md                  # このファイル（本体）
└── .gitignore                 # secret / runtime artifact をブロック
```

新しいパッケージを追加するときは:

1. `mkdir -p <pkg>/<$HOME からの相対パス>` でツリーを作る
2. 設定ファイルを配置する
3. `.gitignore` に runtime / secret パターンを追記する
4. `mise/config.toml` の `[dotfiles]` に source を追記して適用する

## コマンドリファレンス

```bash
# 新規マシンでの一括適用（config 場所解決 + trust + apt 設定込み）
./bootstrap.sh                     # 新マシン / repo をどこに置いても 1 コマンド

# mise で一括適用（2 回目以降 / fish 経由）
mise bootstrap                     # packages → dotfiles → tools を順に適用
mise bootstrap --dry-run           # 何が起きるか確認
mise bootstrap dotfiles status     # dotfiles の適用状態 (applied/missing/differs)
mise bootstrap dotfiles status --missing
mise bootstrap packages status --missing
mise bootstrap dotfiles apply --dry-run
mise bootstrap dotfiles unapply --dry-run

# GCM のみ（mise registry に無いため）
./install.sh                      # 導入
./install.sh --check              # 状態確認
```

グローバル config の実体は `mise/config.toml`（`MISE_GLOBAL_CONFIG_FILE` で参照）。
`~/.config/mise/config.toml` は存在しない（撤去済み）。config 編集は repo 内
`mise/config.toml` に対して行い、`mise` コマンドは fish 経由で使う
（fish の config.fish が `MISE_GLOBAL_CONFIG_FILE` を設定する）。
`./bootstrap.sh` は `apt/*.sources`（fish PPA 等）を `/etc/apt/sources.list.d/` に
未設定なら導入して `apt-get update` する（sudo を要求）。

## 変更時に守るルール

### 1. Secret は絶対コミットしない

- `.env*` / `*.pem` / `*.key` / `auth.json` / `.credentials.json` / `.git-credentials`
  等は `.gitignore` で鉄壁ブロック済み
- `claude/` や `codex/` に新しいファイルを足すときは **credentials / history /
  sqlite / sessions / cache / backups が混入していないか必ず確認**する
- 新しい secret パスが発覚したら `.gitignore` に追記する
- `[bootstrap.secrets]` を使う場合も平文 secret を repo / config に永続化しない

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

### 5. mise は dry-run 先行

- `mise bootstrap --dry-run` で衝突・差分を確認してから実適用する
- `apply --force` は既存実ファイルを置き換えるため、内容を確認してから使う
- repo 内ファイルが symlink 化されないよう、git status で短期の変更を監視する

### 6. テストスキップの禁止

グローバル指針と同じ: 失敗するテストはスキップ (`skip` / `xit` / 削除) ではなく
修正で対応する。dotfiles には今のところテストがないが、将来スクリプト化された
検証を足すときの方針として保持。

## 外部ツール依存

`git/.gitconfig` は以下に依存:

- **[delta](https://github.com/dandavison/delta)** — `core.pager` と
  `interactive.diffFilter`（mise の `apt:git-delta` で導入）
- **[git-credential-manager](https://github.com/git-ecosystem/git-credential-manager)**
  — `credential.helper` / WSL では `credentialStore = wincredman` で Windows
  Credential Manager (DPAPI) に資格情報を保存。`./install.sh` で導入

`fish/.config/fish` は以下に依存（すべて `[bootstrap.packages]` の `apt:*` 宣言）:

- **fish 本体** — `apt:fish`。4.x は repo 同梱の PPA
  (`apt/fish-shell-ubuntu-release-4-noble.sources`) から導入
- **bat / fd-find / eza / zoxide / fzf** — config.fish の alias / abbr /
  プロンプト連携（`apt:bat` / `apt:fd-find` / `apt:eza` / `apt:zoxide` / `apt:fzf`）
- **opencode** — `mise bootstrap` の `[tools]` で導入（`aqua:anomalyco/opencode`）

## トラブルシュート

| 症状 | 原因と対処 |
|------|-----------|
| `mise bootstrap dotfiles apply` で "refusing to overwrite existing files" | $HOME 側に実ファイルがある。内容を確認して `--force` で置換、または退避 |
| `git` 実行時に `delta: command not found` | delta 未導入。`mise bootstrap` で入れるか一時的に `git -c core.pager=less ...` で回避 |
| `~/.gitconfig` に突然大量の差分 | `gcm configure` などツールが symlink 先に書き込んだ可能性。差分を確認して整理する |
| `.gitconfig` などの apply で repo 内ファイルが symlink 化する | `[dotfiles]` がディレクトリ symlink を指す場合、file-level 宣言でなくディレクトリ単位で宣言する（secretlint の例） |
| Windows 側でコピーしたファイルに `:Zone.Identifier` が付く | global ignore で除外済み (`~/.config/git/ignore`) |

## 関連ドキュメント

- [README.md](README.md) — 外向け / ユーザー向けの案内
- [meta/MIGRATION.md](meta/MIGRATION.md) — 既存 `~/.config/*` を取り込む手順