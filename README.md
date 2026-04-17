# dotfiles

`ba0918` の dotfiles。GNU Stow で管理する。

## セットアップ

```bash
git clone <this-repo> ~/develop/dotfiles
cd ~/develop/dotfiles
./install.sh            # stow を自動インストール → dry-run → 実リンク
```

## レイアウト

各トップレベルディレクトリが「**Stow パッケージ**」で、そのツリー構造がそのまま
`$HOME` の下に symlink される。

```
dotfiles/
├── git/                # → ~/.gitconfig + ~/.config/git/{ignore,attributes}
│   ├── .gitconfig
│   └── .config/git/
│       ├── ignore      # global gitignore (XDG, 自動検出)
│       └── attributes  # global gitattributes (XDG, 自動検出)
├── fish/               # → ~/.config/fish/*
│   └── .config/fish/
├── nvim/               # → ~/.config/nvim/*
│   └── .config/nvim/
├── claude/             # → ~/.claude/* （secret 除外）
│   └── .claude/
├── codex/              # → ~/.codex/*   （secret 除外）
│   └── .codex/
├── meta/
│   └── MIGRATION.md    # 既存設定の取り込み手順
├── install.sh          # stow ラッパー（自動インストール + dry-run → link）
├── Makefile            # make install / check / unlink / relink
└── .gitignore          # secret / runtime artifact を鉄壁ブロック
```

## よく使うコマンド

```bash
./install.sh                 # 全パッケージを install
./install.sh --dry-run       # 何が起きるか確認
./install.sh --unlink        # 全部剥がす
./install.sh --deps          # 外部ツール (stow/delta/GCM) のみ導入
./install.sh git fish        # 個別パッケージのみ

make list                    # パッケージ一覧
make check                   # 全部 dry-run
make install                 # 全部 install
make install-fish            # fish だけ install
make relink                  # unlink → install で貼り直し
```

## 外部ツール依存

`git/.gitconfig` は以下の外部ツールに依存する。`./install.sh --deps` で自動インストールできる:

- **[delta](https://github.com/dandavison/delta)** — `core.pager` / `interactive.diffFilter` に使う色付き diff
- **[git-credential-manager](https://github.com/git-ecosystem/git-credential-manager)** — `credential.helper = manager`。WSL なら Windows Credential Manager (DPAPI) に資格情報を保存する

未インストールでも `.gitconfig` 自体は読み込めるが、`core.pager` が効かず `git` が「delta: command not found」で怒る。`--deps` を走らせてから `install.sh` するか、一時的にページャを戻す (`git -c core.pager=less diff`) で回避可能。

## パッケージの追加手順

1. 新しいディレクトリを作る: `mkdir -p newpkg/.config/newpkg`
2. そこに設定ファイルを置く（`$HOME` からの相対パスをそのまま再現）
3. `./install.sh newpkg` で symlink
4. `.gitignore` に runtime / secret パスを追記

既存の `~/.config/...` を取り込む手順は [meta/MIGRATION.md](meta/MIGRATION.md) を見る。

## 安全設計

- `install.sh` は最初に `--dry-run` を走らせて衝突を検出してから実リンクを張る
- `.gitignore` で credentials / session / sqlite / history を絶対ブロック
- `stow` は既存の実ファイルを上書きしない（衝突なら失敗する）ので、間違って消える心配なし
- アンリンクも `make unlink` 一発で戻せる
