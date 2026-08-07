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
```

初回実行後、対話シェルでは fish の config.fish が `MISE_GLOBAL_CONFIG_FILE` を
設定するので、以後はそのまま `mise bootstrap` を直接叩ける。
repo を別の場所に置いた場合は bootstrap.sh を使えば場所非依存で適用できる。

## fish プラグイン

tide / fzf.fish / z は fisher 管理。`fish_plugins` で宣言されているので
新規マシンでは `fisher install` で再現する（関数・completions 等の生成物は
repo に含めない）。

`mise bootstrap` は [bootstrap.packages] / [dotfiles] / [tools] を順に適用し、
システムパッケージ・dotfiles・開発ツールを一つで再現する。再実行は冪等。

## レイアウト

トップレベルは「パッケージ」で、source ツリーが `[dotfiles]` の宣言を通じて
`$HOME` の下に symlink 展開される。

```
dotfiles/
├── git/                    # → ~/.gitconfig + ~/.config/git/{ignore,attributes,template}
│   ├── .gitconfig
│   └── .config/git/
│       ├── ignore          # global gitignore (XDG, 自動検出)
│       ├── attributes      # global gitattributes (XDG, 自動検出)
│       └── template/       # git init テンプレート (global pre-commit 等)
├── fish/                   # 手動ファイルのみ（プラグインは fish_plugins + fisher）
│   └── .config/fish/
│       ├── config.fish
│       ├── fish_plugins
│       ├── functions/up.fish
│       └── conf.d/clipboard2path.fish     # Alt+V ペースト hook（dotfiles 管理）
├── nvim/                   # 育成中
│   └── .config/nvim/
├── claude/                 # → ~/.claude/* （secret 除外）
│   └── .claude/
├── codex/                  # → ~/.codex/*   （secret 除外）
│   └── .codex/
├── yazi/                   # → ~/.config/yazi/{yazi.toml,keymap.toml}
│   └── .config/yazi/
├── apt/                    # 同梱 apt リポジトリ (bootstrap.sh が導入)
│   └── fish-shell-ubuntu-release-4-noble.sources    # fish 4.x PPA
├── mise/
│   └── config.toml         # グローバル config の実体（MISE_GLOBAL_CONFIG_FILE で参照）
├── meta/
│   └── MIGRATION.md        # 既存設定の取り込み手順
├── bootstrap.sh            # 新規マシン用 wrapper（config 解決 + trust + apt 設定 + mise bootstrap）
└── .gitignore              # secret / runtime artifact をブロック
```

## よく使うコマンド

```bash
./bootstrap.sh                   # 新規マシンで一括適用（config 解決 + trust + apt 設定込み）
mise bootstrap                   # 2回目以降（config.fish が env を設定済み）
mise bootstrap --dry-run         # 何が起きるか確認
mise bootstrap --skip packages   # 一部スキップ
mise bootstrap dotfiles status   # dotfiles の適用状態
mise bootstrap dotfiles status --missing
mise bootstrap packages status --missing
gh auth setup-git                # GitHub の credential helper に gh を登録
glab auth login                  # GitLab のブラウザ認証 + SSH 鍵発行・登録
```

`./bootstrap.sh` は `apt/*.sources`（fish PPA 等）を `/etc/apt/sources.list.d/` に
未設定なら導入し、`apt-get update` する（sudo を要求。新規マシンでプロンプトが出る）。
`--dry-run` は導入が必要な apt リポジトリの検出と表示のみ行い、実際のコピーと
`apt-get update` は実行しない。

グローバル config は `mise/config.toml` が実体。
`MISE_GLOBAL_CONFIG_FILE` が未設定の環境（fish 外の sh 等）では tools が読めないので、
非対話シェルでも使いたい場合は同環境変数を export して使う。

## 外部ツール依存

- システムパッケージ / dev ツールは **mise** (`[bootstrap.packages]` / `[tools]`)
  で宣言する
- **[delta](https://github.com/dandavison/delta)** — `core.pager` /
  `interactive.diffFilter` に使う色付き diff（`apt:git-delta`）
- **[gh](https://cli.github.com/)** — GitHub の credential helper
  （`!gh auth git-credential`）。HTTPS リモートに遭遇しても自動認証される
- **[glab](https://gitlab.com/gitlab-org/cli)** — GitLab の認証は
  `glab auth login` で SSH 鍵を発行・GitLab へ登録する（GitLab の push は SSH）。
  `[tools]` の `glab` で導入
- **fish シェル本体と shell ツール** — fish / bat / fd-find / eza / zoxide / fzf
  は apt で配布（`[bootstrap.packages]` の `apt:*` 宣言）。
- **yazi** — TUI ファイルマネージャ（`[tools]` の `yazi`）。`ya` 関数で起動すると
  終了時のカレントディレクトリに移動。`S` で ripgrep によるファイル内容検索、
  `E` で Windows Explorer を開く（WSL 向け opener は `explorer.exe` へ委譲）。

未インストールでも `.gitconfig` 自体は読み込めるが、`core.pager` が効かず
`git` が「delta: command not found」で怒る。`mise bootstrap` で `git-delta` を入れてから
使うか、一時的にページャを戻す (`git -c core.pager=less diff`) で回避可能。

### その他の依存

- **clipboard2path-wsl** — 自作ツール（[ba0918/clipboard2path-wsl]）。クリップボードの
  画像をファイル保存してパスを返す daemon。binary は `[settings] aqua.registries`
  で参照するツール repo 公開の aqua registry 経由で `[tools]` から導入し、
  systemd user service と wl-paste wrapper は `clipboard2path-wsl init --no-hook`
  が生成する（fish hook のみ `conf.d/clipboard2path.fish` を dotfiles 管理）。
  動作確認は `clipboard2path-wsl status`。

## パッケージの追加手順

1. 新しいディレクトリを作る: `mkdir -p newpkg/.config/newpkg`
2. そこに設定ファイルを置く（`$HOME` からの相対パスをそのまま再現）
3. `mise/config.toml` の `[dotfiles]` に source を追記（repo 内からの相対パス）
4. `.gitignore` に runtime / secret パスを追記

既存の `~/.config/...` を取り込む手順は [meta/MIGRATION.md](meta/MIGRATION.md) を見る。

## 安全設計

- `mise bootstrap --dry-run` で衝突を確認してから実適用する
- 既存の実ファイルがある対象は mise が refuse する（`--force` は明示的に渡す）
- `.gitignore` で credentials / session / sqlite / history を絶対ブロック
- `mise bootstrap dotfiles unapply --dry-run` で剥がす前に確認できる