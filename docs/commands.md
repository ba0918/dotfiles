# コマンドリファレンス

## セットアップ

```bash
# 新マシンでの一括適用（config 場所解決 + trust + apt 設定込み）
./bootstrap.sh

# mise で一括適用（2 回目以降 / fish 経由）
mise bootstrap
mise bootstrap --dry-run            # 何が起きるか確認
mise bootstrap --skip packages      # 一部スキップ
```

## dotfiles の管理

```bash
mise bootstrap dotfiles status      # 適用状態（applied/missing/differs）
mise bootstrap dotfiles status --missing
mise bootstrap packages status --missing
mise bootstrap dotfiles apply --dry-run
mise bootstrap dotfiles unapply --dry-run
```

## 認証

```bash
gh auth setup-git                   # GitHub の credential helper に gh を登録
glab auth login                     # GitLab のブラウザ認証 + SSH 鍵発行・登録
```

## LLM 設定の管理

settings.json は `ai/claude/conf.d/` で分割管理し、`build-settings` で合成する。
パイプラインの詳細は [meta/LLM-SETTINGS.md](../meta/LLM-SETTINGS.md) を参照。

```bash
ai/claude/build-settings            # conf.d/ を合成して ~/.claude/settings.json に書き込み
ai/claude/build-settings --dry-run  # 書き込まず stdout に出力
ai/claude/build-settings --clean    # runtime allow をリセットしてベースラインに戻す
ai/claude/build-settings --status   # managed vs runtime allow の内訳を表示
scripts/generate-deny.sh claude     # deny-patterns.yaml → Claude Code 形式で stdout
scripts/generate-deny.sh opencode   # deny-patterns.yaml → OpenCode 形式で stdout
scripts/generate-deny.sh opencode-apply  # ~/.opencode/opencode.json の deny を上書き
apm update -g --yes                 # ~/.apm/apm.yml の規範スキルを最新に更新（bootstrap でも実行。install は lock に留まる）
```

## テスト

GitHub Actions（`.github/workflows/ci.yml`）が main への push で全テスト・shellcheck・
secret スキャン（gitleaks + secretlint）を回す。PR 運用ではないので CI は入った後の
検知器であり、push 前に手元で回すのが基本。

```bash
mise run test                              # 全テスト（scripts/run-tests.sh。CI と同じ入口）
mise run lint                              # 追跡中の bash スクリプト全部に shellcheck（scripts/lint.sh）
```

個別に回すとき:

```bash
pytest ai/shared/hooks/tests               # security hooks（[tools] の pipx:pytest。python3 -m pytest は不可）
bash scripts/test_generate_deny.sh         # deny 生成スクリプト
bash scripts/test_run_optional.sh          # 外部依存ラッパのスキップ挙動
bash scripts/test_codex_jail.sh            # codex jail の mount 検証
bash scripts/test_docker_install.sh        # Docker 導入スクリプト
bash scripts/test_run_tests.sh             # テスト入口（run-tests.sh）自身
bash scripts/test_lint.sh                  # lint 入口（lint.sh）自身
bash scripts/test_pre_commit.sh            # git template の pre-commit hook（secretlint。要 mise run bootstrap）
```

## clipboard2path-wsl

クリップボードの画像をファイル保存してパスを返す daemon（自作ツール）。
binary は mise の `[tools]` で導入し、systemd unit は `init` で生成する。

```bash
mise bootstrap                      # [tools] の aqua:ba0918/clipboard2path-wsl が入る
clipboard2path-wsl init --no-hook   # unit / wl-paste wrapper を生成（destructive）
clipboard2path-wsl status           # service / hook / wrapper の状態
systemctl --user restart clipboard2path  # 手動再起動
```

## devbox / PHP

PHP ツールチェーン（php / xdebug / pcov / composer）は mise ではなく devbox
（nix ベース）で管理する。グローバル宣言は `devbox/global/`、
レガシープロジェクト用の timecop 付き php は `devbox/flake/`。

```bash
devbox global list                            # グローバル導入パッケージの一覧
devbox global add <pkg>                       # 追加（devbox.json を更新）
devbox global shellenv --init-hook -r | source  # 環境を再生成して source する
devbox run -- php -v                          # プロジェクト環境でコマンド実行
devbox services start|stop php-fpm            # php-fpm サービス（ポート 8082）
```

レガシープロジェクトで timecop を使う場合:

```bash
devbox init
# devbox.json の packages に追加:
#   "path:/home/mizumi/develop/dotfiles/devbox/flake"
#   "path:/home/mizumi/develop/dotfiles/devbox/flake#composer"
devbox generate direnv                        # .envrc を生成
direnv allow                                  # cd した瞬間に timecop 付き php が有効
```

## herdr

config.toml のみ dotfiles 管理。プラグインは手動導入。

```bash
herdr plugin install smarzban/herdr-file-viewer
herdr plugin list
```

## Docker（WSL 内ネイティブ）

Docker Desktop 環境では使わない。opt-in の導入スクリプト。

```bash
~/develop/dotfiles/docker/install.sh --dry-run   # 計画を確認
~/develop/dotfiles/docker/install.sh             # 適用（sudo）
```

## サプライチェーン対策の確認

```bash
npm safe-chain-verify               # safe-chain が有効か確認（pnpm / bun / pip でも可）
safe-chain --version                 # safe-chain のバージョン確認
```
