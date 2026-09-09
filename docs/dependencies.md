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
- **secretlint** — `git init` テンプレートの pre-commit hook が staged ファイルを検査する。
  PATH 上の `secretlint` は使わず、`git/.config/secretlint/`（→ `~/.config/secretlint`）に
  `package.json` + lockfile で固定した secretlint と preset を `mise run bootstrap` が
  `npm ci` で入れ、hook は config の隣の `node_modules/.bin/secretlint` を直接呼ぶ。
  PATH 依存にしないのは、環境ごとに別の secretlint（preset を同梱しない mise の
  `npm:secretlint` 版など）が拾われて hook が壊れたことがあるため。
  実行に `node` が要り、PATH に無ければ mise の shims から探す。
  未導入なら hook は fail-secure で commit を拒否する（`mise run bootstrap` で入る）
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
- **シェルツール** — `bat` / `fd-find` / `eza` / `zoxide`。
  config.fish の alias / abbr / プロンプト連携に使う。`[bootstrap.packages]`
  の `apt:*` 宣言
- **fzf** — fisher プラグイン `patrickf1/fzf.fish` が PATH 上の `fzf` を呼ぶ。
  apt 版は 0.44 系でプラグインが前提にする新しめのオプションに追いつかないため、
  `[bootstrap.packages]` ではなく `[tools]` の `fzf` で導入する
- **clipboard2path-wsl** — 自作ツール（[ba0918/clipboard2path-wsl]）。
  クリップボードの画像をファイル保存してパスを返す daemon。
  binary は `[tools]` の `github:ba0918/clipboard2path-wsl` で GitHub Releases から
  直接導入する。systemd user service と
  wl-paste wrapper は `clipboard2path-wsl init --no-hook` が生成する
  （fish hook のみ `conf.d/clipboard2path.fish` を dotfiles 管理）
- **Aikido Safe Chain**（[AikidoSec/safe-chain]）— npm / pnpm / bun / pip 等の
  パッケージマネージャをラップし、マルウェア検知 + 最小リリース年齢（デフォルト 48h）
  を適用。実体は `~/.safe-chain/`（dotfiles 管轄外）。`bootstrap.sh` が sha256
  検証付きで導入。config.fish は存在する場合のみ source する。
  起動経路と順序は [process-wrap の PATH](process-wrap.md#起動経路と-path)、
  検査条件は [Safe Chain の仕様](spec/safe-chain-path.md)を参照。
  隔離（process-wrap）の中も同じ PATH を継承するので、codex が起動する
  パッケージマネージャも Safe Chain を通る（隔離の中で `npm safe-chain-verify` と実際の
  `npm install` が通ることは実測済み）。`~/.safe-chain` は隔離の中では読み取り専用で、
  マルウェア DB の更新はホスト側の実行に任せる（隔離の中で更新が要る状態になったときの
  振る舞いは未検証）。Claude Code が起動する MCP サーバーも同じ `env.PATH` で起動すると
  考えられる（未検証）。今は `npx` / `uvx` で起動する MCP サーバーが無い（context7 は
  HTTP）ので影響は無く、browser-use プラグインを有効にすると `uvx` 起動なので Safe Chain
  の shim を通る
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
  最新追従を優先し `minimum_release_age` を per-tool で 0d にしている。
  設定は `ai/claude/` で管理
- **codex** — `[tools]` の `codex`（`aqua:openai/codex`）で導入。同じく per-tool で 0d。
  設定は `ai/codex/` で管理
- **opencode** — `[tools]` の `opencode`（`aqua:anomalyco/opencode`）で導入。同じく per-tool で 0d。
  グローバル config は `ai/opencode/opencode.json` で template 配布。
  **claude-skills** プラグインは `opencode plugin ba0918/claude-skills --force --global`
  で導入（スキル本体は opencode のキャッシュに配置されるため repo 外）

`ai/shared/` の共通契約（`interaction.md` / `human-readable.md`）は
`~/.claude/rules/` にシンボリックリンクして常時適用する。Claude 専用の
`model-routing.md` と、それが参照する agent 定義（`judge.md` / `scout.md`）は
`ai/claude/rules/` `ai/claude/agents/` から同様に symlink する。output-style の `persona/gal.md` は
`~/.claude/output-styles/` から symlink する。これにより `@` 参照を使わずに
すべてのモデルで共通設定が効く

hook スクリプトの実体は `ai/shared/hooks/` にあり、Claude Code と Codex
の両方に同じファイルを配布する。`detect_*.py` は同じディレクトリの
`hook_input.py` を import するため、配布先ごとに `hook_input.py` も併せて配る。
以前は Claude 用と Codex 用に同じ検出ロジックを 2 部持っていたが、
イベント形式の差は `hook_input.edited_files` が吸収するので統合した。

### process-wrap

`github:ba0918/process-wrap` と `apt:bubblewrap` を mise で導入する。
この repo が管理するのは `ai/process-wrap/` の起動シム・プロファイル・代替コマンド。
配布方法、PATH、トークン、隔離の限界は [process-wrap の運用](process-wrap.md)を参照。

### hook の repo 外依存

`~/.claude` / `~/.codex` の hook 設定には、この repo が導入しない対象を
参照するものがある。新マシンではこれらは存在しないので、すべて
`run-if-present` の `path` mode 経由で起動し、対象が無ければ無音でスキップする。
hook が動く PATH で `run-if-present` が解決できる必要があるが、そこに載る経路は
Claude 側と Codex 側で違う。

起動経路ごとの設定は [process-wrap の PATH](process-wrap.md#起動経路と-path)を参照。
Claude Code は生成済み settings.json、Codex は起動元から継承した PATH を使う。

`run-if-present` は `mise/config.toml` の `[tools]` table
（`github:ba0918/run-if-present`）で導入する。

| 参照先 | 使う設定 | 管轄 |
|--------|----------|------|
| `$HOME/develop/claude-notify` | `30-hooks.json` の Notification / Stop | 別 repo。手動 clone |
| `~/.claude/hooks/herdr-agent-state.sh`、`~/.codex/herdr-agent-state.sh` | 両者の SessionStart | herdr 管轄。dotfiles 配布外 |

`run-if-present` の呼び出し方:

```bash
run-if-present path <存在チェックするパス> -- <実行するコマンド>
run-if-present --chdir <作業ディレクトリ> path <パス> -- <コマンド>
```

`statusLine` の `~/.claude/statusline.py` は repo 管理（`ai/claude/statusline.py` を
`[dotfiles]` が template で実体として書き出す）だが、同じく `run-if-present` で包む。
`mise bootstrap` をまだ流していないマシンでは配布先にファイルが無く、素通しだと
statusline のたびに「ファイルが無い」エラーが出続けるため。実体を配る方式なので、
`ai/claude/statusline.py` を直したら `mise bootstrap dotfiles apply` で配り直すまで
`~/.claude/statusline.py` には反映されない。

`run-if-present` が飲み込むのは「依存が無い」ケースだけで、コマンド自体の失敗は
そのまま終了コードとして伝播する。存在チェック自体が失敗した場合（権限エラーなど）、
旧ラッパーは無音だったが、`run-if-present` は 1 行の診断を出して終了コード 1 で終了する。

## その他

- **apm** — `[tools]` の `pipx:apm-cli` で導入。Agent Package Manager。
  ユーザースコープの `~/.apm/apm.yml` は `ai/apm/apm.yml` から symlink 配布し、
  `mise run bootstrap` の `apm update -g --yes` が宣言どおりに規範スキルを
  `~/.claude/skills` と `~/.agents/skills` に最新化する。依存は自分のリポジトリ
  （規範の `ba0918/agentic-rules`、workflow の `ba0918/agentic-workflow` 等）なので pin せず
  main を追従する。`apm install -g` は
  `apm.lock.yaml` の commit に留まるため、追従させたいときは update を使う。
  プロジェクト単位の `apm.yml` はそれぞれのリポジトリで管理する
- **ripgrep** — `[tools]` の `ripgrep`。旧 apt 版から mise 管理へ移行済み
- **ollama** — `[tools]` の `ollama`（aqua）。公式 installer は使わず
  `ollama serve` で手動起動
- **tea** — `[tools]` の `go:gitea.dev/tea`。Gitea / Forgejo の CLI
- **ブラウザ自動化の依存** — agent-browser と Playwright が使う Chromium の
  共有ライブラリと CJK / 絵文字フォントを `[bootstrap.packages]` で宣言

## サプライチェーン対策

3 層構成でパッケージの導入リスクを軽減する:

1. **mise `minimum_release_age = "7d"`** — ツールバイナリの導入をリリースから
   7 日以上経過したものに制限。ツール単位で待たない（0d）例外がある。
   例外の対象と理由は [mise/config.toml](../mise/config.toml) の `[tools]` を参照。
   aqua と github backend では検証方式が異なるため、同じ 0d でも導入元を確認する。
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

## sshd（Windows ホストから WSL へ接続）

`ssh/install.sh` が sshd の hardening drop-in・`openssh-server`・ssh.socket の
待受アドレス drop-in・`~/.ssh/authorized_keys`・`/etc/wsl.conf` の `systemd=true`
を冪等に整える。Windows 側の公開鍵は `wslvar USERPROFILE`（wslu、
`[bootstrap.packages]` 済み）で `%USERPROFILE%\.ssh\id_ed25519.pub` を探す。

`openssh-server` を `[bootstrap.packages]` に入れないのは、apt がインストール直後に
リスナーを起動するため、hardening が先に置かれていないと初回起動がパスワード認証
有効のまま外に出るから。スクリプトは drop-in を置いてからパッケージを入れる。

Ubuntu の sshd は socket activation（`ssh.socket`）で起動するため、`sshd_config` の
`Port` / `ListenAddress` は効かず、待受アドレスは `ssh.socket.d/` の drop-in で持つ。
WSL の mirrored networking では 0.0.0.0 待受が Windows ホスト経由で LAN からも
届くので、loopback（127.0.0.1 / ::1）だけに絞っている。LAN から使いたくなったら
`ssh/ssh.socket.d/10-dotfiles.conf` の `ListenStream` を広げる。

[AikidoSec/safe-chain]: https://github.com/AikidoSec/safe-chain
[ba0918/clipboard2path-wsl]: https://github.com/ba0918/clipboard2path-wsl
