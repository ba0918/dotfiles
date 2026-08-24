# dotfiles

`ba0918` の dotfiles。**mise** の `bootstrap` で管理する。

## セットアップ（新マシン / WSL 内）

前提: まっさらな WSL。Windows 側の環境構築は対象外。

```bash
# 1. mise を入れる (まだ無ければ)
curl https://mise.run | sh

# 2. repo を clone（場所は自由。repo 内の相対パスで解決される）
git clone <this-repo> ~/develop/dotfiles

# 3. 一括適用（wrapper が config の場所解決・trust まで行う）
~/develop/dotfiles/bootstrap.sh

# 4. (opt-in) Docker Desktop を使わない機械だけ: WSL 内に dockerd を直接入れる
~/develop/dotfiles/docker/install.sh --dry-run   # 計画を確認
~/develop/dotfiles/docker/install.sh             # 適用（sudo。systemd 未有効なら wsl --shutdown が必要）
```

mise は `curl https://mise.run | sh` でも `apt install mise`（`apt/mise.sources` を
bootstrap.sh が登録する）でもよい。apt 経由なら `apt upgrade` で追従する。

初回実行後、対話シェルでは fish の config.fish が `MISE_GLOBAL_CONFIG_FILE` を
設定するので、以後は `mise bootstrap` を直接叩ける。
repo を別の場所に置いた場合は bootstrap.sh を使えば場所非依存で適用できる。

`./bootstrap.sh` は `apt/*.sources`（fish PPA 等）を `/etc/apt/sources.list.d/` に
未設定なら導入し、`apt-get update` する（sudo を要求）。

## fish プラグイン

tide / fzf.fish / z は fisher 管理。`fish_plugins` で宣言されているので
新規マシンでは `fisher install` で再現する（関数・completions 等の生成物は
repo に含めない）。

## レイアウト

トップレベルは「パッケージ」で、`mise/config.toml` の `[dotfiles]` 宣言を通じて
`$HOME` の下に symlink 展開される。

| パッケージ | 展開先 | 概要 |
|---|---|---|
| `git/` | `~/.gitconfig` + `~/.config/git/*` | git 設定、global ignore / attributes |
| `fish/` | `~/.config/fish/*` | config.fish、fish_plugins、関数 |
| `nvim/` | `~/.config/nvim/*` | LazyVim ベース |
| `ai/` | `~/.claude/*` `~/.codex/*` `~/.opencode/*` | LLM 設定の集約（secret 混入厳禁） |
| `yazi/` | `~/.config/yazi/*` | TUI ファイルマネージャ |
| `glow/` | `~/.config/glow/*` | Markdown レンダラ |
| `herdr/` | `~/.config/herdr/*` | ターミナルマルチプレクサ |
| `npm/` `pnpm/` `bun/` | `~/.npmrc` 等 | サプライチェーン対策（リリース年齢制限） |
| `apt/` | `/etc/apt/sources.list.d/` | 同梱 apt リポジトリ（bootstrap.sh が配布） |
| `devbox/` | `~/.local/share/devbox/...` | PHP ツールチェーン（nix ベース） |
| `docker/` | `/etc/docker/daemon.json` | WSL 内ネイティブ dockerd（opt-in） |
| `mise/` | `MISE_GLOBAL_CONFIG_FILE` | グローバル config 実体 |

詳細な構成は [docs/layout.md](docs/layout.md) を参照。

## サプライチェーン対策

パッケージ導入のリスクを 3 層で軽減する:

- **mise `minimum_release_age = "7d"`** — ツールバイナリの導入をリリースから
  7 日以上経過したものに制限
  （ただし **claude / codex** は AI CLI の最新追従が優先のため per-tool で 1d に短縮。
  aqua の cosign / GitHub Artifact Attestations 検証は有効）
- **npm / pnpm / bun のネイティブ設定** — 依存パッケージのリリース年齢を 7 日以上に制限
  （`min-release-age` / `minimumReleaseAge`。単位はエコシステムごとに異なる）
- **Aikido Safe Chain** — パッケージマネージャをラップし、マルウェア検知 +
  最小リリース年齢（デフォルト 48h）を適用。`bootstrap.sh` が sha256 検証付きで導入

## よく使うコマンド

```bash
./bootstrap.sh                   # 新規マシンで一括適用
mise bootstrap                   # 2回目以降
mise bootstrap --dry-run         # 確認
mise bootstrap dotfiles status   # 適用状態
gh auth setup-git                # GitHub の credential helper 登録
```

全コマンドは [docs/commands.md](docs/commands.md) を参照。

## パッケージの追加手順

1. `mkdir -p <pkg>/<$HOME からの相対パス>` でツリーを作る
2. 設定ファイルを配置する
3. `.gitignore` に runtime / secret パターンを追記する
4. `mise/config.toml` の `[dotfiles]` に source を追記して適用する

既存の `~/.config/...` を取り込む手順は [meta/MIGRATION.md](meta/MIGRATION.md) を参照。

## 安全設計

- `mise bootstrap --dry-run` で衝突を確認してから実適用する
- 既存の実ファイルがある対象は mise が refuse する（`--force` は明示的に渡す）
- `.gitignore` で credentials / session / sqlite / history を絶対ブロック
- `mise bootstrap dotfiles unapply --dry-run` で剥がす前に確認できる
- サプライチェーン対策は上記 3 層構成

## 詳細リファレンス

- [docs/layout.md](docs/layout.md) — 構成・パッケージ詳細
- [docs/commands.md](docs/commands.md) — コマンドリファレンス
- [docs/dependencies.md](docs/dependencies.md) — 外部ツール依存
- [docs/troubleshooting.md](docs/troubleshooting.md) — トラブルシューティング
- [meta/LLM-SETTINGS.md](meta/LLM-SETTINGS.md) — LLM 設定パイプライン仕様書
- [meta/MIGRATION.md](meta/MIGRATION.md) — 既存設定の取り込み手順
