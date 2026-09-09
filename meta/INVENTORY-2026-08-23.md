# 棚卸し 2026-08-23: この WSL に入っているが dotfiles が宣言していなかったもの

これは 2026-08-23 時点の判断記録で、現在の削除手順ではない。
削除の実行完了は未確認。再利用前に現状の用途・導入元を確認し、全項目の処置が
完了していればこの記録を削除する。現在の構成は [依存一覧](../docs/dependencies.md) と
[mise の宣言](../mise/config.toml) を参照。

## 処置済み（dotfiles に取り込んだ）

| 対象 | 取り込み先 |
|---|---|
| clipboard2path の依存 `wl-clipboard` `wslu` | `[bootstrap.packages]` |
| ブラウザ自動化（agent-browser / Playwright）の依存 `libnss3` `libnspr4` `libasound2t64` + CJK/絵文字フォント 9 個 | `[bootstrap.packages]`（`playwright install-deps chromium` の一覧を宣言で固定） |
| 汎用アーカイブ `zip` `unzip` `zstd` | `[bootstrap.packages]` |
| `ollama` | `[tools]`（aqua）。公式 installer 版は削除対象 |
| `tea`（Gitea / Forgejo CLI） | `[tools]`（`go:gitea.dev/tea`、明示ピン）。`~/.local/bin/tea` は削除対象 |
| `uv` / `uvx` | `[tools]`（aqua）。`~/.local/bin/uv` `uvx` は削除対象 |
| uv tools `pytest` `skills-ref`（`agentskills`） | `[tools]` の `pipx:` backend。`uv tool` 側は削除対象 |
| `dotenvx` | `[tools]`（aqua）。`~/.local/bin/dotenvx` は削除対象 |
| `similarity-rs` / `similarity-ts` | `[tools]` の `cargo:` backend。`~/.cargo/bin` の手動版は削除対象 |
| `rustup` | **二重ではなかった**。mise の `rust` は内部で rustup を使う（`mise which cargo` → `~/.cargo/bin/rustup`）。残す。古い toolchain 1.95 は mise の旧 latest、nightly は手動追加 |
| apt リポジトリ docker / gierens / mise、Docker ネイティブ導入 | 同日の別コミット |

## 当時の削除候補（実行完了は未確認）

一括削除コマンドは掲載しない。各候補について、現在も不要か、mise 管理の実体と
重ならないかを確認してから処置する。過去のコマンドは Git 履歴に残っている。

| 候補 | 当時の理由・再確認する点 |
|---|---|
| Tauri の依存 | `webkit2gtk-driver`、`libwebkit2gtk-4.1-dev`、`libayatana-appindicator3-dev`、`xorg-dev`、`xvfb`、`gcc-mingw-w64-x86-64`、`nasm`、`tauri-driver`。他の開発用途がないか確認 |
| PHP の手動ビルド環境 | mise の PHP と `libbz2-dev`、`libgd-dev`、`libonig-dev`、`libreadline-dev`、`libyaml-dev`、`libzip-dev`、`autoconf`、`bison`、`re2c`。PHP は Devbox/Nix へ移行したが、共有ライブラリの他用途は再確認 |
| git-credential-manager | `gcm` と `/usr/local/bin/git-credential-manager`。当時は gh へ移行 |
| ollama の公式 installer 版 | `/usr/local/bin/ollama`、systemd unit、専用ユーザー。mise 管理版と区別する |
| 手動導入した CLI | `/usr/local/bin/apm`、`~/.local/bin/` の `tea`、`uv`、`uvx`、`dotenvx`、`pytest`、`py.test`、`agentskills`、`bat`。現在のコマンド解決先を確認 |
| uv / cargo の手動導入 | uv tools の `pytest`・`skills-ref`、cargo の `similarity-rs`・`similarity-ts`。mise 管理版と区別する |
| 古い Rust toolchain | `1.95.0-x86_64-unknown-linux-gnu`、`nightly-x86_64-unknown-linux-gnu`。プロジェクトごとの利用を確認 |
| その他の旧バージョン・apt の未使用依存 | 現在の依存関係を確認して個別に判断 |

`openssh-server` の削除判断は撤回。現在は Windows ホストから WSL に接続する用途があり、
[SSH の導入手順](../ssh/install.sh)で任意導入する。利用中の環境からは削除しない。

残す判断にした dev ライブラリ: `libpq-dev` `libsqlite3-dev` `libcurl4-openssl-dev` `libssl-dev`
`libxml2-dev` `zlib1g-dev`（PHP 以外の Rust / Node ネイティブ依存も使い得る。消すならリンク
エラーが出たときに戻す前提で）。

## dotfiles には入れない（プロジェクト側の依存として扱う）

- `sshpass` → `inv`（ssh/scp/rsync アップローダ）が使う。inv の README に書く
- `libvips-tools` → `diet-manager`（sharp）
- `socat` `whois` `gfortran` `lcov` → 使い手が特定できず。入れたままにして、次の新規マシンで困ったら足す
- mise に入っているがグローバル未宣言: `aws-sam-cli` `flutter` `lefthook` `python 3.14` 旧版 `node` / `deno` / `cargo-*` →
  各プロジェクトの `mise.toml` 由来。clone すれば戻る

## 未決

2026-08-23 時点では全件判断済み。ただし、上の削除候補の実行完了はこの記録から確認できない。

## 走査に使った観点

`apt-mark showmanual` と Ubuntu 公式 WSL イメージ（noble/current）の manifest の差 / snap /
`/opt` / `/usr/local/bin` / `~/.local/bin` / `~/.cargo/bin` / `~/.bun/bin` / `~/go/bin` /
`npm -g` / `pipx` / `uv tool list` / `mise ls` の source 列 / fisher / systemd（system, user）/
crontab / `/etc/sysctl.d` / `/etc/profile.d` / `/etc/wsl.conf`。`~/.codex` `~/.config` 配下は見ていない。
