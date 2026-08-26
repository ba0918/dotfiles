# 外部ツール依存

このリポジトリの設定ファイルが正しく動くために必要な外部ツール。
多くは `mise/config.toml` の `[bootstrap.packages]`（apt パッケージ）と
`[tools]`（バイナリツール）で宣言されており、`mise bootstrap` で一括導入される。

## git

`git/.gitconfig` は以下に依存する:

- **delta** — `core.pager` と `interactive.diffFilter` に使う色付き diff ビューア。
  `[bootstrap.packages]` の `apt:git-delta` で導入。未インストールでも `.gitconfig`
  自体は読み込めるが、`delta: command not found` で怒る。一時回避は
  `git -c core.pager=less diff`
- **gh** — GitHub の credential helper（`!gh auth git-credential`）。
  `[tools]` の `gh` で導入
- **glab** — GitLab の認証は `glab auth login` で SSH 鍵を発行・GitLab へ登録する。
  `[tools]` の `glab` で導入
- **マシンごとの git identity** — `[user]` は repo に持たない（環境分離）。
  `~/.config/git/config.local`（gitignore 済み）を include して各マシンで設定する:
  ```bash
  git config --file ~/.config/git/config.local user.name "<名前>"
  git config --file ~/.config/git/config.local user.email "<メール>"
  ```

## fish

`fish/.config/fish` は以下に依存する:

- **fish 本体** — 4.x は repo 同梱の PPA（`apt/fish-shell-ubuntu-release-4-noble.sources`）
  から `apt:fish` で導入
- **シェルツール** — `bat` / `fd-find` / `eza` / `zoxide` / `fzf`。
  config.fish の alias / abbr / プロンプト連携に使う。すべて `[bootstrap.packages]`
  の `apt:*` 宣言
- **clipboard2path-wsl** — 自作ツール（[ba0918/clipboard2path-wsl]）。
  クリップボードの画像をファイル保存してパスを返す daemon。
  binary は `[settings] aqua.registries` で参照するツール repo 公開の
  aqua registry 経由で `[tools]` から導入。systemd user service と
  wl-paste wrapper は `clipboard2path-wsl init --no-hook` が生成する
  （fish hook のみ `conf.d/clipboard2path.fish` を dotfiles 管理）
- **Aikido Safe Chain**（[AikidoSec/safe-chain]）— npm / pnpm / bun / pip 等の
  パッケージマネージャをラップし、マルウェア検知 + 最小リリース年齢（デフォルト 48h）
  を適用。実体は `~/.safe-chain/`（dotfiles 管轄外）。`bootstrap.sh` が sha256
  検証付きで導入。config.fish は存在する場合のみ source する。
  非対話シェル（LLM エージェント等）へは mise の PATH 経由で shim が渡る
- **opencode** — `[tools]` で導入（`aqua:anomalyco/opencode`）。
  fish の config.fish が opencode の有無で alias / hook をロードする

## nvim

- **neovim** — `[tools]` の `neovim`。LazyVim は Neovim 0.12+ を要求。
  旧 appimage（`/opt/nvim`）は廃止済み

## yazi

- **yazi** — `[tools]` の `yazi`。`ya` 関数で起動すると終了時のカレント
  ディレクトリに移動。`S` で ripgrep によるファイル内容検索、`E` で
  Windows Explorer を開く（WSL 向け opener は `explorer.exe` へ委譲）

## glow

- **glow** — `[tools]` の `glow`（`aqua:charmbracelet/glow`）

## herdr

- **herdr** — `[tools]` の `herdr`（`aqua:herdrdev/herdr`）
- **herdr-file-viewer** — プラグイン。`herdr plugin install smarzban/herdr-file-viewer`
  で手動導入。`plugins.json` は生成物のため repo 除外

## devbox / PHP

PHP ツールチェーン（php / xdebug / pcov / composer）は mise ではなく
devbox（nix ベース）で管理する。aqua に php 拡張の管理が無く、mise では
ext の再ビルドが手動になるのが理由。

- **devbox** — `[tools]` の `aqua:jetify-com/devbox` で導入
- **nix** — devbox が初回実行時に single-user モードで自動導入する（daemon 不要）。
  fish の config.fish が `devbox global shellenv --init-hook` を source して PATH を通す
- **direnv** — `[tools]` の `direnv` で導入。プロジェクト単位の環境自動切替に使う。
  `devbox generate direnv` で `.envrc` を生成すると cd した瞬間に devbox 環境が有効になる
- **timecop flake** — `devbox/flake/` が実体。nixpkgs に php-timecop が無いため
  自前の flake でビルドする。レガシープロジェクト専用（グローバルには入れない）

## LLM ツール（claude / codex / opencode）

- **claude-code** — `[tools]` の `claude`（`aqua:anthropics/claude-code`）で導入。
  リリース高頻度のため `minimum_release_age` を per-tool で 1d に短縮。
  設定は `ai/claude/` で管理
- **codex** — `[tools]` の `codex`（`aqua:openai/codex`）で導入。同じく per-tool で 1d。
  設定は `ai/codex/` で管理
- **opencode** — `[tools]` の `opencode`（`aqua:anomalyco/opencode`）で導入。
  グローバル config は `ai/opencode/opencode.json` で template 配布。
  **claude-skills** プラグインは `opencode plugin ba0918/claude-skills --force --global`
  で導入（スキル本体は opencode のキャッシュに配置されるため repo 外）

`ai/shared/` の共通契約（`interaction.md` / `human-readable.md`）は
`~/.claude/rules/` にシンボリックリンクして常時適用する
（`model-routing.md` と同じ場所）。output-style の `persona/gal.md` は
`~/.claude/output-styles/` から symlink する。これにより `@` 参照を使わずに
すべてのモデルで共通設定が効く

hook スクリプトの実体は `ai/shared/hooks/` にあり、Claude Code と Codex
の両方に同じファイルを配布する。`detect_*.py` は同じディレクトリの
`hook_input.py` を import するため、配布先ごとに `hook_input.py` も併せて配る。
以前は Claude 用と Codex 用に同じ検出ロジックを 2 部持っていたが、
イベント形式の差は `hook_input.edited_files` が吸収するので統合した。

### codex jail

`codex` コマンドは `ai/codex/bin/codex` を経由して起動する。この shim
ディレクトリは `mise/config.toml` の `env._.path` で mise 管理の codex 本体より
前に置く（mise の hook-env が PATH を組み直しても順序が保たれる。config.fish の
`fish_add_path` は hook-env が走らない非対話シェル向けの保険で、それだけだと
組み直しの時点で本体に負ける）。`which codex` が
`~/.local/share/mise/installs/codex/...` を返したら jail を経由していない。
このシムは bubblewrap で mount
namespace を組み、以下の境界を作る:

| アクセス | 対象 |
|----------|------|
| **読み書き可** | 現在の worktree、共有 `.git`、`/tmp`、各種 cache、`~/.codex` の状態 |
| **隠蔽** | `~/.ssh` `~/.aws` `~/.gnupg` `~/.config/gh`、Windows ドライブ（`/mnt/c` 等）、worktree 内の `.env*`（雛形と `node_modules` 配下を除く） |
| **読み取り専用** | それ以外すべて（`~/.codex/config.toml` / `AGENTS.md` / hooks 等の指示ファイルを含む） |

この中で `codex --dangerously-bypass-approvals-and-sandbox` を動かす。
codex 自身の Permission Profile（Beta）は `.git` の read-only mount や
deny glob の fail-closed が重なって実用に耐えないため、境界を codex の外に出した。

認証情報を隠すため `git push` と `gh` は jail の中では失敗する（外で行う。
意図的に un-hide する手段は用意していない）。
mount table は `ai/codex/jail.conf`（`rw` / `ro` / `hide` の 3 directive、
`~` 展開あり）。cycle や skill-regression が箱の中から起動する opencode / claude
の状態ディレクトリも `rw` にしてある（それらの設定・指示ファイルは `ro`）。
別の CLI が `Read-only file system` で落ちたら、その CLI の状態ディレクトリを
`rw` で足す。

jail に入るのは対話セッション・`exec`・`resume`・`fork`。
`app-server` / `mcp-server` は jail の外で動き、codex 自身の sandbox が
境界になる（Claude Code の codex plugin 経由の実行はこちら）。
`login` / `mcp` / `--version` などエージェントがコマンドを実行しない
呼び出しも素通しする。

環境変数での調整:
- `CODEX_JAIL_RW` / `CODEX_JAIL_HIDE`（コロン区切り）— 一時的な追加用
- `CODEX_JAIL_CONF` — table ごと差し替え
- `CODEX_JAIL_OFF=1` — jail 自体を外す

検証は `bash scripts/test_codex_jail.sh`。

### hook の repo 外依存

`~/.claude` / `~/.codex` の hook 設定には、この repo が導入しない対象を
参照するものがある。新マシンではこれらは存在しないので、すべて
`run-optional.sh`（`ai/shared/hooks/run-optional.sh` → 両方の hooks/ に配布）
経由で起動し、対象が無ければ無音でスキップする。

| 参照先 | 使う設定 | 管轄 |
|--------|----------|------|
| `~/.claude/statusline.py` | `10-base.json` の `statusLine` | ローカル専用。repo 未管理 |
| `$HOME/develop/claude-notify` | `30-hooks.json` の Notification / Stop | 別 repo。手動 clone |
| `~/.claude/hooks/herdr-agent-state.sh`、`~/.codex/herdr-agent-state.sh` | 両者の SessionStart | herdr 管轄。dotfiles 配布外 |

ラッパの呼び出し方:

```bash
bash "$HOME/.claude/hooks/run-optional.sh" <存在チェックするパス> -- <実行するコマンド>
bash "$HOME/.claude/hooks/run-optional.sh" --cd <作業ディレクトリ> <パス> -- <コマンド>
```

ラッパが飲み込むのは「依存が無い」ケースだけで、コマンド自体の失敗は
そのまま終了コードとして伝播する。

## その他

- **apm** — `[tools]` の `pipx:apm-cli` で導入。Agent Package Manager。
  各プロジェクトの `apm.yml` で宣言管理する
- **ripgrep** — `[tools]` の `ripgrep`。旧 apt 版から mise 管理へ移行済み
- **ollama** — `[tools]` の `ollama`（aqua）。公式 installer は使わず
  `ollama serve` で手動起動
- **tea** — `[tools]` の `go:gitea.dev/tea`。Gitea / Forgejo の CLI
- **ブラウザ自動化の依存** — agent-browser と Playwright が使う Chromium の
  共有ライブラリと CJK / 絵文字フォントを `[bootstrap.packages]` で宣言

## サプライチェーン対策

3 層構成でパッケージの導入リスクを軽減する:

1. **mise `minimum_release_age = "7d"`** — ツールバイナリの導入をリリースから
   7 日以上経過したものに制限（claude / codex は最新追従のため per-tool で 1d に短縮。
   aqua の cosign / GitHub Artifact Attestations 検証は有効）
2. **npm / pnpm / bun のネイティブ設定** — 依存パッケージのリリース年齢を 7 日以上に制限
3. **Aikido Safe Chain** — パッケージマネージャをラップし、マルウェア検知 +
   最小リリース年齢を適用。`bootstrap.sh` が sha256 検証付きで導入

## Docker（WSL 内ネイティブ）

`docker/install.sh` が Docker 公式 apt リポジトリ・`docker-ce` 一式・
`/etc/docker/daemon.json`・`docker` グループ・`/etc/wsl.conf` の `systemd=true`
を冪等に整える。

`[bootstrap.packages]` には入れない。会社 PC のように Docker Desktop の
WSL 統合が daemon を提供する環境で `docker-ce` を入れると
`/var/run/docker.sock` を取り合うため、Desktop を検出したら何もせず終了する。

`daemon.json` の `bip`（bridge IP）はデフォルトの 172.17.0.0/16 が社内 LAN と
重なったため、192.168.100.0/24 に固定している。値を変えるときは社内 LAN と
VPN の経路表と重ならないことを先に確認する。

[AikidoSec/safe-chain]: https://github.com/AikidoSec/safe-chain
[ba0918/clipboard2path-wsl]: https://github.com/ba0918/clipboard2path-wsl
