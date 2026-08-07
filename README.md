# dotfiles

`ba0918` の dotfiles。**mise** の `bootstrap` で管理する。

## セットアップ（新マシン / WSL 内）

前提: mutable前の WSL。Windows 側の環境構築は対象外。

```bash
# 1. mise を入れる (まだ無ければ)
curl https://mise.run | sh

# 2. repo を clone
git clone <this-repo> ~/develop/dotfiles

# 3. グローバル config に repo への source を宣言
#    ~/.config/mise/config.toml に [dotfiles] などを追記（段階移行中は install..sh 参照）

# 4. 一括適用
mise trust ~/develop/dotfiles
mise bootstrap
```

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
├── fish/                   # 育成中
│   └── .config/fish/
├── nvim/                   # 育成中
│   └── .config/nvim/
├── claude/                 # → ~/.claude/* （secret 除外）
│   └── .claude/
├── codex/                  # → ~/.codex/*   （secret 除外）
│   └── .codex/
├── meta/
│   └── MIGRATION.md        # 既存設定の取り込み手順
├── install.sh              # GCM 専用インストーラ（apt）
└── .gitignore              # secret / runtime artifact をブロック
```

## よく使うコマンド

```bash
mise bootstrap                     # [bootstrap.packages] + [dotfiles] + [tools] を適用
mise bootstrap --dry-run           # 何が起きるか確認
mise bootstrap --skip packages     # 一部スキップ
mise bootstrap dotfiles status     # dotfiles の適用状態
mise bootstrap dotfiles status --missing
mise bootstrap packages status --missing
./install.sh                       # GCM のみ導入（略式: --check で状態確認）
```

## 外部ツール依存

- システムパッケージ / dev ツールは **mise** (`[bootstrap.packages]` / `[tools]`)
  で宣言する
- **[delta](https://github.com/dandavison/delta)** — `core.pager` /
  `interactive.diffFilter` に使う色付き diff（`apt:git-delta`）
- **[git-credential-manager](https://github.com/git-ecosystem/git-credential-manager)**
  — `credential.helper = manager`。WSL では Windows Credential Manager (DPAPI)。
  mise registry に無いため `./install.sh` で導入

未インストールでも `.gitconfig` 自体は読み込めるが、`core.pager` が効かず
`git` が「delta: command not found」で怒る。`mise bootstrap` で `git-delta` を入れてから
使うか、一時的にページャを戻す (`git -c core.pager=less diff`) で回避可能。

## パッケージの追加手順

1. 新しいディレクトリを作る: `mkdir -p newpkg/.config/newpkg`
2. そこに設定ファイルを置く（`$HOME` からの相対パスをそのまま再現）
3. `~/.config/mise/config.toml` の `[dotfiles]` に source を追記
4. `.gitignore` に runtime / secret パスを追記

既存の `~/.config/...` を取り込む手順は [meta/MIGRATION.md](meta/MIGRATION.md) を見る。

## 安全設計

- `mise bootstrap --dry-run` で衝突を確認してから実適用する
- 既存の実ファイルがある対象は mise が refuse する（`--force` は明示的に渡す）
- `.gitignore` で credentials / session / sqlite / history を絶対ブロック
- `mise bootstrap dotfiles unapply --dry-run` で剥がす前に確認できる