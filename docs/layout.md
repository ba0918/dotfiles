# リポジトリ構成

## 管理モデル

トップレベルの各ディレクトリが「パッケージ」で、パッケージ内のパスは
`$HOME` からの相対パスをそのまま再現する。`mise/config.toml` の `[dotfiles]`
に source を宣言すると、`mise bootstrap` がその配下を `$HOME` に
シンボリックリンクとして展開する。

グローバル config の実体は `mise/config.toml`。fish の `config.fish` が
`MISE_GLOBAL_CONFIG_FILE` を設定するので、fish 経由なら `mise` コマンドが
直接使える。`./bootstrap.sh` は config の場所解決・trust・apt リポジトリ
設定まで含むラッパーで、新マシンの初回適用に使う。

配布方式は 2 種類ある:

- **symlink 配布** — repo 内のファイルが `$HOME` からシンボリックリンクされる。
  `~/.gitconfig` のように外部ツールが書き込むファイルは、
  symlink 経由で repo ファイルそのものが変更される点に注意
- **template 配布** — `mise/config.toml` で `mode = "template"` を指定すると、
  `{{ config_root }}` などのプレースホルダを展開した実ファイルが生成される。
  `opencode.json` のように repo ルートの絶対パスが必要な場合に使う。
  `{{ config_root }}` は `MISE_GLOBAL_CONFIG_ROOT`（bootstrap.sh と config.fish
  が設定する）で repo ルートに解決される

`~/.config/mise/config.toml` は存在しない（撤去済み）。config 編集は repo 内の
`mise/config.toml` に対して行い、`mise` コマンドは fish 経由で使う

## パッケージ一覧

```
dotfiles/
├── git/                       # → ~/.gitconfig + ~/.config/git/*
│   ├── .gitconfig
│   └── .config/
│       ├── git/
│       │   ├── ignore         # global gitignore（XDG 自動検出）
│       │   ├── attributes     # global gitattributes（XDG 自動検出）
│       │   └── template/      # git init テンプレート
│       └── secretlint/
│           └── .secretlintrc.json
├── fish/                      # → ~/.config/fish/*（プラグインは fish_plugins + fisher）
│   └── .config/fish/
│       ├── config.fish
│       ├── fish_plugins
│       ├── functions/up.fish
│       └── conf.d/clipboard2path.fish
├── nvim/                      # → ~/.config/nvim/*（LazyVim ベース）
│   └── .config/nvim/
├── ai/                        # LLM 設定の集約（secret 混入厳禁）
│   ├── claude/                # → ~/.claude/*
│   │   ├── CLAUDE.md          # template 配布
│   │   ├── bash-env.sh        # symlink 配布
│   │   ├── build-settings     # conf.d/ → settings.json 合成スクリプト
│   │   ├── conf.d/            # settings.json の分割管理（10-base〜60-plugins）
│   │   ├── rules/             # → ~/.claude/rules/*（Claude 専用ルール。model-routing）
│   │   └── agents/            # → ~/.claude/agents/*（judge / scout の agent 定義）
│   ├── codex/                 # → ~/.codex/*
│   │   ├── AGENTS.md          # template 配布
│   │   ├── hooks.json         # symlink 配布
│   │   ├── jail.conf          # bubblewrap の mount table
│   │   ├── bin/codex          # jail shim
│   │   └── jail-bin/          # jail 内でだけ PATH 先頭に来る代替コマンド
│   ├── opencode/              # → ~/.opencode/opencode.json（template 配布）
│   │   └── opencode.json
│   └── shared/                # Claude / Codex 共通
│       ├── hooks/             # security hook スクリプト（両ツールに配布）
│       │   └── tests/         # pytest テスト
│       ├── deny-patterns.yaml # LLM の deny 設定の正本
│       ├── persona/gal.md     # output-style（~/.claude/output-styles/ から symlink）
│       └── vendor/            # claude-skills から同期した共有文書
├── yazi/                      # → ~/.config/yazi/*（TUI ファイルマネージャ）
│   └── .config/yazi/
├── glow/                      # → ~/.config/glow/*（Markdown レンダラ）
│   └── .config/glow/
├── herdr/                     # → ~/.config/herdr/*（ターミナルマルチプレクサ）
│   └── .config/herdr/
├── npm/                       # → ~/.npmrc
│   └── .npmrc                 # サプライチェーン対策（min-release-age=7）
├── pnpm/                      # → ~/.config/pnpm/*
│   └── .config/pnpm/          # サプライチェーン対策（minimumReleaseAge 分単位）
├── bun/                       # → ~/.bunfig.toml
│   └── .bunfig.toml           # サプライチェーン対策（minimumReleaseAge 秒単位）
├── apt/                       # 同梱 apt リポジトリ（bootstrap.sh が導入）
│   ├── fish-shell-ubuntu-release-4-noble.sources
│   ├── gierens.sources        # eza 配布元
│   └── mise.sources
├── devbox/                    # PHP ツールチェーン（nix ベース）
│   ├── global/                # → ~/.local/share/devbox/global/default/
│   │   ├── devbox.json
│   │   └── devbox.lock
│   └── flake/                 # timecop 付き php のビルド定義（レガシー向け）
├── docker/                    # WSL 内ネイティブ dockerd（opt-in）
│   ├── install.sh             # 導入スクリプト（Desktop 検出で拒否、--dry-run あり）
│   ├── docker.sources         # Docker 公式 apt リポジトリ
│   └── daemon.json            # → /etc/docker/daemon.json
├── mise/
│   └── config.toml            # グローバル config 実体（MISE_GLOBAL_CONFIG_FILE）
├── meta/                      # 仕様書・手順書
│   ├── LLM-SETTINGS.md        # LLM 設定パイプライン仕様書
│   ├── MIGRATION.md           # 既存設定の取り込み手順
│   └── INVENTORY-*.md         # 棚卸し記録
├── docs/                      # 人間向け詳細リファレンス
├── scripts/
│   ├── generate-deny.sh       # deny-patterns.yaml → 各ツール形式に変換
│   ├── sync-shared.sh         # claude-skills 共有文書を vendor/ に同期
│   ├── run-tests.sh           # 全テストの入口（mise run test / CI）
│   ├── lint.sh                # 追跡中の bash スクリプトに shellcheck（mise run lint / CI）
│   └── test_*.sh              # bash テストハーネス
├── .github/workflows/ci.yml   # GitHub Actions（テスト / shellcheck / secret スキャン）
├── .shellcheckrc              # shellcheck の repo 全体の除外
├── .gitleaks.toml             # gitleaks の allowlist（secret 検出テストの fixture）
├── bootstrap.sh               # 新マシン用 wrapper
├── CLAUDE.md                  # Claude Code エントリ（→ AGENTS.md）
├── AGENTS.md                  # エージェント向け変更契約
└── .gitignore
```

## パッケージの追加手順

1. `mkdir -p <pkg>/<$HOME からの相対パス>` でツリーを作る
2. 設定ファイルを配置する
3. `.gitignore` に runtime / secret パターンを追記する
4. `mise/config.toml` の `[dotfiles]` に source を追記して適用する

既存の `~/.config/...` を取り込むときは [meta/MIGRATION.md](../meta/MIGRATION.md) を参照。
