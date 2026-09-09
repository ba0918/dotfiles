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

配布方式は次の3種類。宣言は [mise/config.toml](../mise/config.toml) が正本。

- **symlink 配布** — repo 内のファイルが `$HOME` からシンボリックリンクされる。
  `~/.gitconfig` のように外部ツールが書き込むファイルは、
  symlink 経由で repo ファイルそのものが変更される点に注意
- **symlink-each 配布** — fish / Neovim はディレクトリを実体のまま残し、
  Git 管理中のファイルだけを個別リンクにする（`manifest = "git"`）。
  プラグイン生成物や未追跡ファイルは配布しない。新しい設定は `git add <ファイル>` で
  Git の index に登録してから適用する。管理したリンクの記録は mise の state
  ディレクトリに保存されるため、削除しない。
- **template 配布** — `mise/config.toml` で `mode = "template"` を指定すると、
  `{{ config_root }}` などのプレースホルダを展開した実ファイルが生成される。
  `opencode.json` のように repo ルートの絶対パスが必要な場合と、
  `~/.claude/CLAUDE.md` のようにリンクではなく実体が置かれていること自体が
  必要な場合（[process-wrap の保護範囲](process-wrap.md)）に使う。
  `{{ config_root }}` は `MISE_GLOBAL_CONFIG_ROOT`（bootstrap.sh と config.fish
  が設定する）で repo ルートに解決される

`~/.config/mise/config.toml` は存在しない（撤去済み）。config 編集は repo 内の
`mise/config.toml` に対して行い、`mise` コマンドは fish 経由で使う

## パッケージ一覧

| 編集する内容 | 正本・編集先 | 配布先・用途 |
|---|---|---|
| Git | `git/.gitconfig`、`git/.config/git/` | `~/.gitconfig`、`~/.config/git/` |
| コミット時の secret 検出 | `git/.config/secretlint/` | `~/.config/secretlint/`。依存は `mise run bootstrap` で生成 |
| fish | `fish/.config/fish/` | `~/.config/fish/`。プラグインは `fish_plugins` と fisher で管理 |
| Neovim | `nvim/.config/nvim/` | `~/.config/nvim/`（LazyVim） |
| Claude Code | `ai/claude/` | `~/.claude/`。settings.json は `conf.d/` から合成 |
| Codex | `ai/codex/` | `~/.codex/`。AGENTS.md と hooks.json は template |
| OpenCode | `ai/opencode/opencode.json` | `~/.opencode/opencode.json`（template） |
| AI 共通設定 | `ai/shared/` | deny の正本、共通 hook、対話契約、persona |
| 規範スキルの配布 | `ai/apm/apm.yml` | `~/.apm/apm.yml`。APM が各ツールへ配布 |
| 隔離起動 | `ai/process-wrap/` | 起動シム、プロファイル、代替コマンド。[詳細](process-wrap.md) |
| Yazi / Glow / Herdr | `yazi/`、`glow/`、`herdr/` の `.config/` 配下 | `~/.config/` の各ツールディレクトリ |
| パッケージ導入時の保護 | `npm/`、`pnpm/`、`bun/` | 各パッケージマネージャの設定。[方針](dependencies.md#サプライチェーン対策) |
| apt の導入元 | `apt/*.sources` | `bootstrap.sh` が `/etc/apt/sources.list.d/` に配布 |
| PHP | `devbox/global/`、`devbox/flake/` | グローバル環境と timecop 付き PHP のビルド定義 |
| Docker / SSH | `docker/`、`ssh/` | 各 `install.sh` で任意導入。[依存と制約](dependencies.md) |
| ツール・配布宣言 | `mise/config.toml` | グローバル mise 設定 |
| テスト・生成処理 | `scripts/`、`ai/shared/hooks/tests/`、`ai/claude/tests/` | [実行方法](commands.md#テスト) |
| CI | `.github/workflows/ci.yml` | テスト・shellcheck・secret 検出 |
| エージェント指示 | `AGENTS.md`（`CLAUDE.md` から参照） | このリポジトリの変更ルール |

仕様・移行記録は `meta/`、利用手順は `docs/` に置く。

## パッケージの追加手順

1. `mkdir -p <pkg>/<$HOME からの相対パス>` でツリーを作る
2. 設定ファイルを配置する
3. `.gitignore` に runtime / secret パターンを追記する
4. `mise/config.toml` の `[dotfiles]` に source を追記する。
   fish / Neovim の既存ディレクトリ内なら宣言追加は不要。配布するファイルを個別に `git add` する
5. `mise bootstrap dotfiles diff` と `mise bootstrap dotfiles apply --dry-run` で確認して適用する

## 配布ファイルの撤去手順

fish / Neovim の `symlink-each` では、ファイルを Git の index から外して適用すると、
mise が記録済みのリンクを回収する。未管理のファイルは残る。

個別宣言やディレクトリ全体の宣言を撤去する場合は、以下の手順を使う。
`[dotfiles]` の行を消しても、適用済みマシンの symlink は残ってリンク切れになる
（`mise bootstrap` は宣言から消えた対象を回収せず、`dotfiles status` にも出ない）。

1. 宣言を消す前に `mise bootstrap dotfiles unapply <配布先パス>` で対象を回収する
2. `[dotfiles]` から行を消し、実体ファイルを削除する
3. 先に宣言を消してしまった場合は `find ~/.claude ~/.codex -maxdepth 2 -xtype l` で
   リンク切れを探して `rm` する（[docs/troubleshooting.md](troubleshooting.md) 参照）

既存の `~/.config/...` を取り込むときは [meta/MIGRATION.md](../meta/MIGRATION.md) を参照。
