# 棚卸し 2026-08-23: この WSL に入っているが dotfiles が宣言していなかったもの

自宅 WSL（Ubuntu 24.04）の実機を読み取り専用で走査し、`mise/config.toml`・`bootstrap.sh`・
`apt/*.sources`・`[dotfiles]` と突き合わせた差分と、その処置。処置が全部終わったら
このファイルは消してよい。

## 処置済み（dotfiles に取り込んだ）

| 対象 | 取り込み先 |
|---|---|
| clipboard2path の依存 `wl-clipboard` `wslu` | `[bootstrap.packages]` |
| ブラウザ自動化（agent-browser / Playwright）の依存 `libnss3` `libnspr4` `libasound2t64` + CJK/絵文字フォント 9 個 | `[bootstrap.packages]`（`playwright install-deps chromium` の一覧を宣言で固定） |
| 汎用アーカイブ `zip` `unzip` `zstd` | `[bootstrap.packages]` |
| `ollama` | `[tools]`（aqua）。公式 installer 版は削除対象 |
| apt リポジトリ docker / gierens / mise、Docker ネイティブ導入 | 同日の別コミット |

## 削除と決めたもの（実行は手動。sudo が要る）

```bash
# Tauri（今後は使わない）
sudo apt remove --purge webkit2gtk-driver libwebkit2gtk-4.1-dev libayatana-appindicator3-dev \
  xorg-dev xvfb gcc-mingw-w64-x86-64 nasm
cargo uninstall tauri-driver

# PHP のソースビルド依存（PHP は devbox/nix に寄せた）
sudo apt remove --purge libbz2-dev libgd-dev libonig-dev libreadline-dev libyaml-dev libzip-dev \
  autoconf bison re2c
mise uninstall php

# git-credential-manager（credential helper は gh）
sudo apt remove --purge gcm
sudo rm -f /usr/local/bin/git-credential-manager

# openssh-server（入れた記憶なし。Store 配布イメージの同梱品と推定。service は一度も enable されていない）
sudo apt remove --purge openssh-server

# ollama の公式 installer 版（mise 管理へ移行）
sudo systemctl disable --now ollama 2>/dev/null
sudo rm -f /etc/systemd/system/ollama.service /usr/local/bin/ollama
sudo userdel ollama 2>/dev/null

# 重複・残骸
sudo rm -f /usr/local/bin/apm      # [tools] の pipx:apm-cli と二重
rm -f ~/.local/bin/bat             # apt の batcat と二重

sudo apt autoremove --purge
mise prune                          # 旧版の deno / node / cargo-* 等
```

残す判断にした dev ライブラリ: `libpq-dev` `libsqlite3-dev` `libcurl4-openssl-dev` `libssl-dev`
`libxml2-dev` `zlib1g-dev`（PHP 以外の Rust / Node ネイティブ依存も使い得る。消すならリンク
エラーが出たときに戻す前提で）。

## dotfiles には入れない（プロジェクト側の依存として扱う）

- `sshpass` → `inv`（ssh/scp/rsync アップローダ）が使う。inv の README に書く
- `libvips-tools` → `diet-manager`（sharp）
- `socat` `whois` `gfortran` `lcov` → 使い手が特定できず。入れたままにして、次の新規マシンで困ったら足す
- mise に入っているがグローバル未宣言: `aws-sam-cli` `flutter` `lefthook` `python 3.14` 旧版 `node` / `deno` / `cargo-*` →
  各プロジェクトの `mise.toml` 由来。clone すれば戻る

## 未決（オタクくんの判断待ち）

| 対象 | 論点 |
|---|---|
| `uv` / `uvx` + uv tools（`pytest`, `skills-ref`） | `[tools]` に `uv = "latest"`（aqua あり）で入れるか。uv tools の再現は `uv tool install` を bootstrap.sh に書く必要がある |
| `dotenvx` | `[tools]` に `dotenvx = "latest"`（aqua あり）で入れるか |
| `tea`（Gitea CLI） | まだ使っているか |
| `similarity-rs` / `similarity-ts` | refactor-similarity スキルの依存。`cargo:` backend で `[tools]` に入れるか |
| `rustup`（stable ×2 + nightly） | `[tools]` の `rust` と二重。nightly が要るなら rustup を正にして `rust` を外す |

## 走査に使った観点

`apt-mark showmanual` と Ubuntu 公式 WSL イメージ（noble/current）の manifest の差 / snap /
`/opt` / `/usr/local/bin` / `~/.local/bin` / `~/.cargo/bin` / `~/.bun/bin` / `~/go/bin` /
`npm -g` / `pipx` / `uv tool list` / `mise ls` の source 列 / fisher / systemd（system, user）/
crontab / `/etc/sysctl.d` / `/etc/profile.d` / `/etc/wsl.conf`。`~/.codex` `~/.config` 配下は見ていない。
