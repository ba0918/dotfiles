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
│   └── .config/
│       ├── git/
│       │   ├── ignore         # → ~/.config/git/ignore   (XDG 自動検出)
│       │   ├── attributes     # → ~/.config/git/attributes (XDG 自動検出)
│       │   └── template/      # → ~/.config/git/template
│       └── secretlint/
│           └── .secretlintrc.json  # → ~/.config/secretlint/.secretlintrc.json
├── fish/                      # 手動ファイルのみ（プラグインは fish_plugins で管理）
│   └── .config/fish/          # config.fish / fish_plugins / up.fish / clipboard2path.fish
├── apt/                       # 同梱 apt リポジトリ（bootstrap.sh が導入）
│   └── fish-shell-ubuntu-release-4-noble.sources    # fish 4.x PPA
├── nvim/                      # 確定（LazyVim ベース）
│   └── .config/nvim/          # init.lua / lazyvim.json / stylua.toml / lua/{config,plugins}
├── ai/                        # LLM 設定を集約（secret 混入厳禁）
│   ├── claude/                # CLAUDE.md / bash-env.sh / conf.d / build-settings
│   │   │                      #   （CLAUDE.md は template 配布、bash-env.sh は symlink 配布）
│   │   │                      #   hook スクリプトの実体は ai/shared/hooks/（両ツール共有）
│   │   │                      #   output-styles/gal.md は shared/persona/gal.md の symlink
│   │   ├── conf.d/            # settings.json の分割管理（→ build-settings で合成）
│   │   │   ├── 10-base.json   #   model / effort / language 等
│   │   │   ├── 20-deny.json   #   GENERATED: deny-patterns.yaml から生成（gitignore 済み）
│   │   │   ├── 25-allow.json  #   permissions.allow / ask ベースライン
│   │   │   ├── 30-hooks.json  #   hooks 設定
│   │   │   ├── 40-env.json    #   env 設定
│   │   │   ├── 50-sandbox.json #  sandbox 設定
│   │   │   └── 60-plugins.json #  enabledPlugins / extraKnownMarketplaces
│   │   └── build-settings     # conf.d/ → ~/.claude/settings.json 合成スクリプト
│   ├── codex/                 # AGENTS.md / hooks.json（hook 定義のみ。実体は shared/hooks/）
│   │                          #   AGENTS.md は template 配布 → ~/.codex/AGENTS.md
│   │                          #   hooks.json は symlink 配布 → ~/.codex/hooks.json
│   ├── opencode/              # opencode.json（template 配布 → ~/.opencode/opencode.json）
│   │                          #   read/external_directory の deny は書かない（生成物が正本）
│   └── shared/                # 共通契約 + deny-patterns.yaml（deny パターン正本）
│       └── hooks/             # security hooks の実体。Claude / Codex 両方へ配布
│                              #   block_dangerous / detect_secret / detect_mojibake
│                              #   hook_input（イベント正規化）/ run-optional（外部依存ガード）
│                              #   tests/ を $HOME に出さないためファイル単位で配布
├── yazi/                      # 育成中
│   └── .config/yazi/          # yazi.toml / keymap.toml（WSL 向け explorer opener）
├── glow/                      # 確定
│   └── .config/glow/          # glow.yml（スタイル等）
├── herdr/                     # 確定
│   └── .config/herdr/         # config.toml（プラグインは herdr plugin install で導入）
├── devbox/                    # 確定（PHP ツールチェーンの devbox global 宣言）
│   ├── global/                # devbox.json / devbox.lock → ~/.local/share/devbox/global/default/ へ symlink
│   └── flake/                 # timecop 付き php のビルド定義（レガシープロジェクト向け）
├── npm/                       # 確定（JS サプライチェーン対策）
│   └── .npmrc                 # → ~/.npmrc（min-release-age=7）
├── pnpm/                      # 確定（JS サプライチェーン対策）
│   └── .config/pnpm/          # config.yaml（minimumReleaseAge 分単位）
├── bun/                       # 確定（JS サプライチェーン対策）
│   └── .bunfig.toml           # → ~/.bunfig.toml（minimumReleaseAge 秒単位）
├── mise/
│   └── config.toml            # グローバル config 実体（MISE_GLOBAL_CONFIG_FILE）
├── meta/
│   ├── LLM-SETTINGS.md        # LLM 設定の conf.d / deny-patterns パイプライン仕様書
│   └── MIGRATION.md           # 既存 $HOME ファイルの取り込み手順
├── scripts/
│   ├── sync-shared.sh         # claude-skills 共有文書を ai/shared/vendor/ に同期
│   ├── generate-deny.sh       # deny-patterns.yaml → 各ツール形式に変換（純粋変換器）
│   ├── test_sync_shared.sh    # sync-shared.sh のテスト
│   ├── test_generate_deny.sh  # generate-deny.sh のテスト
│   └── test_run_optional.sh   # run-optional.sh のテスト
├── bootstrap.sh                # 新規マシン用 wrapper（config 解決 + trust + apt 設定）
├── CLAUDE.md                  # Claude Code 用エントリ（AGENTS.md を参照）
├── AGENTS.md                  # このファイル（本体）
└── .gitignore                 # secret / runtime artifact をブロック
```

binary の導入は `[tools]` の宣言に集約されるが、自作ツール
(`clipboard2path-wsl`) は aqua 標準レジストリに無いため、ツール repo が公開する
カスタム aqua レジストリ（`https://raw.githubusercontent.com/ba0918/clipboard2path-wsl/main/registry.yaml`）
を `mise/config.toml` の `[settings] aqua.registries` で参照する（設定ベースなので
repo 位置非依存、fish の config.fish や bootstrap.sh では env 設定不要）。
systemd unit / wl-paste wrapper は repo 内に置かず、
`clipboard2path-wsl init --no-hook` が生成する（fish hook のみ dotfiles 管理）。

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

# 認証（gh / glab、SSH 運用）
gh auth setup-git                # GitHub の credential helper に gh を登録
glab auth login                  # GitLab のブラウザ認証 + SSH 鍵発行・登録

# clipboard2path-wsl（自作ツール。ツール repo 公開の aqua レジストリで導入）
mise bootstrap                   # [tools] の aqua:ba0918/clipboard2path-wsl が入る
clipboard2path-wsl init --no-hook # unit / wl-paste wrapper を生成（destructive なので再実行注意）
clipboard2path-wsl status        # service / hook / wrapper の状態
systemctl --user restart clipboard2path    # 手動再起動（ExecStart は mise の latest パスを参照）

# Claude Code settings.json の管理（conf.d → build-settings）
ai/claude/build-settings              # conf.d/ を合成して ~/.claude/settings.json に書き込み
ai/claude/build-settings --dry-run    # 書き込まず stdout に出力
ai/claude/build-settings --clean      # runtime allow をリセットしてベースラインに戻す
ai/claude/build-settings --status     # managed vs runtime allow の内訳を表示
scripts/generate-deny.sh claude       # deny-patterns.yaml → Claude Code 形式で stdout
scripts/generate-deny.sh opencode     # deny-patterns.yaml → OpenCode 形式で stdout
scripts/generate-deny.sh opencode-apply # ~/.opencode/opencode.json の deny を上書き

# テスト（スクリプト側の検証。CI は無いので変更時は手で回す）
bash scripts/test_generate_deny.sh   # deny 生成のカバレッジ / opencode-apply
bash scripts/test_run_optional.sh    # 外部依存ラッパのスキップ挙動
bash scripts/test_sync_shared.sh     # claude-skills 同期
python3 -m pytest ai/shared/hooks/tests    # security hooks

# herdr（ターミナルマルチプレクサ。config.toml のみ dotfiles 管理）
herdr plugin install smarzban/herdr-file-viewer   # プラグイン導入（plugins.json は生成物として repo 除外）
herdr plugin list                # 導入済みプラグインの確認

# devbox（PHP ツールチェーンの閉じ込め管理。nix store ベース）
devbox global list                          # グローバル導入パッケージの一覧
devbox global add <pkg>                     # 追加（devbox.json を更新。repo の symlink 実体が変わる）
devbox global shellenv --init-hook -r | source  # lock / config 変更後に環境を再生成して source する
devbox run -- php -v                       # プロジェクト環境でコマンド実行
devbox services start|stop php-fpm         # php-fpm サービス（ポート 8082）

# レガシープロジェクトで timecop を使う（dotfiles の flake を参照）
devbox init                                 # プロジェクトに devbox.json を作成
# devbox.json の packages に "path:/home/mizumi/develop/dotfiles/devbox/flake" を追加
devbox generate direnv                       # .envrc を生成（cd した瞬間に timecop 付き php が有効）

# direnv（プロジェクト単位の環境自動切替）
direnv allow                                # .envrc を許可（devbox generate direnv が自動実行する）
direnv reload                               # 環境を再読込
```

グローバル config の実体は `mise/config.toml`（`MISE_GLOBAL_CONFIG_FILE` で参照）。
`~/.config/mise/config.toml` は存在しない（撤去済み）。config 編集は repo 内
`mise/config.toml` に対して行い、`mise` コマンドは fish 経由で使う
（fish の config.fish が `MISE_GLOBAL_CONFIG_FILE` と `MISE_GLOBAL_CONFIG_ROOT` を設定する）。
`MISE_GLOBAL_CONFIG_ROOT` は `{{ config_root }}` を repo ルートへ解決し、
dotfiles の template（opencode.json 等）で repo ルート相対パスを使えるようにする。
`./bootstrap.sh` は `apt/*.sources`（fish PPA 等）を `/etc/apt/sources.list.d/` に
未設定なら導入して `apt-get update` する（sudo を要求）。

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

この repo のテストは 2 系統ある。CI は無いので、対応する対象を触ったら手で回すこと
（コマンドは「コマンドリファレンス」参照）。

- **pytest** — `ai/shared/hooks/tests/`（security hooks）
- **bash ハーネス** — `scripts/test_*.sh`（生成スクリプト / ラッパ）

### 7. 生成物は「空でも成功」させない

deny 設定のように**生成に失敗しても形だけ妥当なものが出る**種類の成果物は、
件数なり不変条件なりを検査して落とすところまで書く。過去に
`generate-deny.sh` が mawk 環境で 0 件を返しながら終了コード 0 で成功し、
deny が空の `settings.json` が黙って配布された。

同じ理由で、シェルスクリプトの正規表現は **POSIX 互換に保つ**。`\s` / `\d` などの
GNU 拡張は Debian/Ubuntu 既定の mawk では無言で一致しなくなる。

## 外部ツール依存

`git/.gitconfig` は以下に依存:

- **[delta](https://github.com/dandavison/delta)** — `core.pager` と
  `interactive.diffFilter`（mise の `apt:git-delta` で導入）
- **[gh](https://cli.github.com/)** — GitHub の credential helper
  （`!gh auth git-credential`）。`[tools]` の `gh` で導入
- **マシンごとの git identity** — `[user]` は repo に持たない（環境分離）。
  `~/.config/git/config.local`（gitignore 済み）を include して各マシンで設定する:
  `git config --file ~/.config/git/config.local user.name "<名前>"`
  `git config --file ~/.config/git/config.local user.email "<メール>"`
  新マシン（会社 PC 等）ではこの 2 行を環境に合わせて実行すること

`fish/.config/fish` は以下に依存（すべて `[bootstrap.packages]` の `apt:*` 宣言）:

- **fish 本体** — `apt:fish`。4.x は repo 同梱の PPA
  (`apt/fish-shell-ubuntu-release-4-noble.sources`) から導入
- **bat / fd-find / eza / zoxide / fzf** — config.fish の alias / abbr /
  プロンプト連携（`apt:bat` / `apt:fd-find` / `apt:eza` / `apt:zoxide` / `apt:fzf`）
- **opencode** — `mise bootstrap` の `[tools]` で導入（`aqua:anomalyco/opencode`）

`fish/.config/fish` は以下に依存:

- **clipboard2path-wsl** — 自作ツール。`conf.d/clipboard2path.fish`（fish hook）だけ
  dotfiles が管理する。binary は `[tools]` の `aqua:ba0918/clipboard2path-wsl`（ツール repo
  公開の aqua レジストリ）で導入
- **systemd user サービス / wl-paste wrapper** — `clipboard2path-wsl init --no-hook`
  が生成する（dotfiles 管轄外）。unit の `ExecStart` は mise installs の `latest`
  シンボリックパスを参照するため、`mise up` 後の再起動で追従

`fish/.config/fish/config.fish` は以下に依存（条件付きロード）:

- **Aikido Safe Chain** — npm/pnpm/bun/pip 等のパッケージマネージャをラップし、
  マルウェア検知 + 最小リリース年齢（デフォルト 48h）を適用。実体は `~/.safe-chain/`
  （dotfiles 管轄外）。config.fish は `"$HOME/.safe-chain/scripts/init-fish.fish"` が
  存在する場合のみ source する。インストールは `bootstrap.sh` が sha256 検証付きで実施。
  設定ファイル（`~/.safe-chain/config.json`）はデフォルトのまま（リリース年齢は
  npm/pnpm/bun 各ネイティブ設定の 7 日制限が上位でカバー）

`yazi/.config/yazi` は以下に依存:

- **yazi** — `[tools]` の `yazi` で導入（mise 管轄）
- **explorer.exe** — WSL から Windows Explorer / 既定アプリを呼び出す opener。
  テキスト系は `nvim`、それ以外は `explorer.exe` へ委譲する

`glow/.config/glow` は以下に依存:

- **glow** — `[tools]` の `glow`（`aqua:charmbracelet/glow`）で導入（mise 管轄）。
  snap 版から移行済み（snap は削除対象）

`ai/opencode/opencode.json` は以下に依存:

- **opencode** — `[tools]` の `opencode`（`aqua:anomalyco/opencode`）で導入（mise 管轄）。
  グローバル config（`~/.opencode/opencode.json`）は dotfiles が管理する。
  `instructions` が repo ルート相対パスを指すため **template 配布**
  （`mode = "template"` + `{{ vars.dotfiles_root }}`）にしてあり、rendered 実ファイルに
  なる（symlink ではない）。`MISE_GLOBAL_CONFIG_ROOT`（bootstrap.sh / config.fish が設定）で
  `{{ config_root }}` が repo ルートへ解決される
- **claude-skills** — `plugin` 宣言で導入（`ba0918/claude-skills`。更新は `opencode plugin ba0918/claude-skills --force --global`）。
  スキル本体は opencode が管理するキャッシュに配置されるため repo 外

`apm` は以下に依存:

- **apm** — `[tools]` の `"pipx:apm-cli"` で導入（mise 管轄）。Microsoft の
  Agent Package Manager。aqua レジストリに未登録のため **pipx バックエンド**
  （`pip install apm-cli` 相当）で導入する。エージェント設定（skill / plugin /
  MCP 等）を `apm.yml` + `apm.lock` で宣言管理するツールで、設定ファイル自体は
  dotfiles 管理しない（各プロジェクトの `apm.yml` に宣言）

`devbox` は以下に依存:

- **devbox** — `[tools]` の `"aqua:jetify-com/devbox"` で導入（mise 管轄）。
  PHP ツールチェーン（php / xdebug / pcov / composer）は mise ではなく **devbox global**
  で管理する（aqua に php 拡張の管理が無く、mise では ext の再ビルドが手動になるため）。
  グローバル宣言（`devbox.json` / `devbox.lock`）は `devbox/global/` が実体で、
  `~/.local/share/devbox/global/default/` に symlink 展開される。`devbox.d/` と
  `.devbox/` は生成物として repo 除外
- **nix** — devbox が初回実行時に single-user モードで自動導入する（daemon 不要）。
  PHP のビルド依存含め `/nix/store` に閉じ込めるため apt の dev パッケージは不要。
  fish の config.fish が `devbox global shellenv --init-hook` を source して
  PATH と PHP プラグインの env（PHPRC / PHPFPM_PORT 等）を読み込む
- **direnv** — `[tools]` の `direnv` で導入（mise 管轄）。プロジェクト単位の環境
  自動切替に使う。`devbox generate direnv` で `.envrc` を生成すると、そのディレクトリに
  cd した瞬間に devbox 環境（timecop 付き php 等）が有効になる。fish の config.fish が
  `direnv hook fish` を source する（interactive のみ）
- **timecop flake** — `devbox/flake/` が実体。php-timecop（kiddivouchers 版 v1.8.0）を
  `php.buildPecl` でビルドし、php85 + xdebug + pcov と合成した php を出力する。
  nixpkgs に timecop が無いため自前の flake が必要。レガシープロジェクトでは
  `devbox.json` の packages に `path:/home/mizumi/develop/dotfiles/devbox/flake` を
  追加して使う（グローバルには timecop を入れない。`flake.lock` で nixpkgs を固定）

`~/.claude/*`（ai/claude）と `~/.codex/*`（ai/codex）は以下に依存:

- **claude-code** — `[tools]` の `claude`（`aqua:anthropics/claude-code`）で導入（mise 管轄）。
  リリース高頻度の AI CLI のため最新追従が優先で、グローバルの `minimum_release_age = "7d"`
  を per-tool で短縮（`minimum_release_age = "1d"`）している。aqua の cosign /
  GitHub Artifact Attestations 検証は有効のまま（ポリシー緩和は claude / codex に限定）。
  旧ネイティブ install（`~/.local/bin/claude` + `~/.local/share/claude`）は撤去済み。
  設定（`~/.claude/`）は dotfiles 管理。`settings.json` は `ai/claude/conf.d/` で
  分割管理し `build-settings` で合成（詳細は [meta/LLM-SETTINGS.md](meta/LLM-SETTINGS.md)）。
  共通契約（`interaction.md` / `human-readable.md`）は `~/.claude/rules/` の symlink で
  常時適用（model-routing.md と同じ場所）。output-style の `gal.md` は
  `ai/shared/persona/gal.md` の symlink（`@` 参照を使わないためモデルの Read 依存がなく、
  どのモデルでも persona が効く）
- **codex** — `[tools]` の `codex`（`aqua:openai/codex`）で導入（mise 管轄）。claude と同様に
  per-tool で `minimum_release_age = "1d"` にして最新追従。旧 bun global 導入（`@openai/codex`）は
  撤去済み。設定（`~/.codex/`）は dotfiles 管理。`AGENTS.md` は template 配布（rendered 実ファイル）、
  `hooks.json` は symlink 配布。security hooks（block_dangerous / detect_secret /
  detect_mojibake）のスクリプト実体は Claude Code と共有で `ai/shared/hooks/` にあり、
  `~/.claude/hooks/` と `~/.codex/hooks/` の両方に同じファイルを配布する。
  hooks の導入後は `codex /hooks` で trust が必要（trust state は config.toml の
  `[hooks.state]` に保存される。`herdr-agent-state.sh` は herdr 管轄で dotfiles 配布外）

  hook スクリプトを 1 つに統合しているのは、以前 Claude 用と Codex 用に同じ検出
  ロジックを 2 部持っていて、`scan()` とパターン定義が完全に重複していたため。
  イベント形式の差（Codex だけが `apply_patch` を出す）は `hook_input.edited_files`
  が吸収するので、検出器側はどちらから呼ばれたかを気にしない。
  `detect_*.py` は同じディレクトリの `hook_input.py` を import するため、
  **配布先ごとに hook_input.py も併せて配る必要がある**（`[dotfiles]` で宣言済み）

### LLM hook が参照する repo 外の依存

`~/.claude` / `~/.codex` の hook 設定には、この repo が導入しない対象を叩くものがある。
**新マシンではこれらは存在しない**ので、すべて `run-optional.sh`
（`ai/shared/hooks/run-optional.sh` → `~/.claude/hooks/` と `~/.codex/hooks/` に配布）
経由で起動し、対象が無ければ黙って何もしない。

| 参照先 | 使う設定 | 誰の管轄か |
|--------|----------|-----------|
| `~/.claude/statusline.py` | `10-base.json` の `statusLine` | ローカル専用。repo 未管理 |
| `$HOME/develop/claude-notify` | `30-hooks.json` の Notification / Stop | 別 repo。手動 clone |
| `~/.claude/hooks/herdr-agent-state.sh`<br>`~/.codex/herdr-agent-state.sh` | 両者の SessionStart | herdr 管轄。dotfiles 配布外 |

これらを叩く hook を足すときは、直接コマンドを書かずに必ずラッパを挟むこと:

```
bash "$HOME/.claude/hooks/run-optional.sh" <存在チェックするパス> -- <実行するコマンド>
bash "$HOME/.claude/hooks/run-optional.sh" --cd <作業ディレクトリ> <パス> -- <コマンド>
```

ラッパが飲み込むのは「依存が無い」ケースだけで、コマンド自体の失敗は
そのまま終了コードとして伝播する（壊れた依存は見えたままにする）。

`herdr/.config/herdr` は以下に依存:

- **herdr** — `[tools]` の `herdr`（`aqua:herdrdev/herdr`）で導入（mise 管轄）
- **herdr-file-viewer** — プラグイン。`herdr plugin install smarzban/herdr-file-viewer`
  で導入。config.toml の `[[keys.command]]`（prefix+f / prefix+shift+f）が参照する。
  `plugins.json` は生成物（plugin install / link / enable 時に herdr が自動書き込み）
  のため repo から除外し、新マシンでは上記コマンドで再現する

## トラブルシュート

| 症状 | 原因と対処 |
|------|-----------|
| `mise bootstrap dotfiles apply` で "refusing to overwrite existing files" | $HOME 側に実ファイルがある。内容を確認して `--force` で置換、または退避 |
| `git` 実行時に `delta: command not found` | delta 未導入。`mise bootstrap` で入れるか一時的に `git -c core.pager=less ...` で回避 |
| `~/.gitconfig` に突然大量の差分 | `gcm configure` などツールが symlink 先に書き込んだ可能性。差分を確認して整理する |
| `.gitconfig` などの apply で repo 内ファイルが symlink 化する | `[dotfiles]` がディレクトリ symlink を指す場合、file-level 宣言でなくディレクトリ単位で宣言する（secretlint の例） |
| Windows 側でコピーしたファイルに `:Zone.Identifier` が付く | global ignore で除外済み (`~/.config/git/ignore`) |
| `clipboard2path-wsl` が起動しない / `command not found` | aqua カスタムレジストリは `mise/config.toml` の `[settings] aqua.registries` で設定済み。導入は `mise bootstrap`、手動再起動は `systemctl --user restart clipboard2path` |
| `mise x clipboard2path-wsl` で "not found in tool registry" | ショート名解決が効かない。`aqua:ba0918/clipboard2path-wsl` のフル名を指定する。シェル経由（shim）では問題ない |
| `herdr/.config/herdr/config.toml` に意図しない差分が出る | herdr が実行時に config.toml を書き戻す（write-through。onboarding / [ui] 等の変更で upsert）。差分を確認して整理する。`herdr/.config/herdr/config.toml` は repo 実体と一致させる |
| `herdr plugin` の keybinding が効かない | プラグイン未導入。`herdr plugin install smarzban/herdr-file-viewer` で再現する |
| `codex` の security hook（危険コマンドブロック / secret / mojibake 検出）が効かない | フック未 trust の可能性。`codex /hooks` で trust する。または `~/.codex/hooks.json` / `~/.codex/hooks/*.py` の symlink が未適用（`mise bootstrap dotfiles status` で確認） |
| `~/.codex/hooks` の apply が "refusing to overwrite existing files" になる | 旧方式のディレクトリ symlink が残っている。`rm ~/.codex/hooks`（symlink 自体を消す。repo の実体は消えない）してから `mise bootstrap dotfiles apply` でファイル単位に張り直す |
| hook が `ModuleNotFoundError: hook_input` で落ちる | 配布先ディレクトリに `hook_input.py` が無い。`detect_*.py` は同じディレクトリから import する。`mise bootstrap dotfiles status` で `~/.claude/hooks/hook_input.py` と `~/.codex/hooks/hook_input.py` を確認 |
| `generate-deny.sh` が "deny pattern extraction is incomplete" で落ちる | deny-patterns.yaml に足したカテゴリが `ALL_CATEGORIES` に未登録。スクリプト側にも追加する（この検査が無いと deny が黙って欠ける） |
| `devbox global shellenv` が "environment may be out of date" 警告を出し php が見つからない | 新規マシンでは `bootstrap.sh` が自動で再生成する。lock / config を手動変更した場合などは `devbox global shellenv --init-hook -r \| source` で環境を再生成してからシェルを起動し直す |
| statusline が空 / 通知が飛ばない | 参照先（`~/.claude/statusline.py`、`$HOME/develop/claude-notify`）が未導入。`run-optional.sh` が意図的に無音でスキップしている。導入すればそのまま有効になる |

## 関連ドキュメント

- [README.md](README.md) — 外向け / ユーザー向けの案内
- [meta/LLM-SETTINGS.md](meta/LLM-SETTINGS.md) — LLM 設定の conf.d / deny-patterns パイプライン仕様書
- [meta/MIGRATION.md](meta/MIGRATION.md) — 既存 `~/.config/*` を取り込む手順