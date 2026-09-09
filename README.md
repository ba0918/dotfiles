# dotfiles

`ba0918` の dotfiles。**mise** の `bootstrap` で管理する。

## セットアップ（新マシン / WSL 内）

前提: まっさらな WSL。Windows 側の環境構築は対象外。

```bash
# 1. repo を clone（場所は自由。repo 内の相対パスで解決される）
git clone https://github.com/ba0918/dotfiles.git ~/develop/dotfiles

# 2. mise を入れる（まだ無ければ）。導入スクリプトの GPG 署名を検証してから実行する
~/develop/dotfiles/mise/install.sh --dry-run   # 検証だけ試す
~/develop/dotfiles/mise/install.sh             # 検証して導入

# 3. 変更予定を確認して適用（config の場所解決・trust・apt 設定を含む）
~/develop/dotfiles/bootstrap.sh --dry-run
~/develop/dotfiles/bootstrap.sh

# 4. (opt-in) Docker Desktop を使わない機械だけ: WSL 内に dockerd を直接入れる
~/develop/dotfiles/docker/install.sh --dry-run   # 計画を確認
~/develop/dotfiles/docker/install.sh             # 適用（sudo。systemd 未有効なら wsl --shutdown が必要）

# 5. (opt-in) Windows 側の IDE / エージェントから WSL へ ssh する機械だけ
~/develop/dotfiles/ssh/install.sh --dry-run      # 計画を確認
~/develop/dotfiles/ssh/install.sh                # 適用（sudo。Windows 側に ssh-keygen 済みの鍵が要る）
```

`mise/install.sh` は、mise が配布する署名済みの導入スクリプト（`install.sh.sig`）を
`apt/mise.sources` に埋め込んだ鍵で検証してから実行する。鍵が repo にあるので
keyserver を引く必要がなく、鍵が差し替われば diff に出る。検証に失敗したときは
復号済みのスクリプトを残さずに終了する。

`bootstrap.sh` は配置場所を自動解決し、必要な apt リポジトリを登録する（sudo が必要）。
初回適用後は fish から `mise bootstrap` を使える。mise 本体は `auto_update` により
self-update で最新版へ追従する。apt で導入した環境では self-update が封じられるため、
その場合だけ `apt upgrade` で更新する。
clipboard2path / Devbox の補助初期化に失敗した場合は、エラーと警告を表示して続行する。
警告が出たら原因を解消して `bootstrap.sh` を再実行する。

## fish プラグイン

tide / fzf.fish は Fisher 管理。**初回 bootstrap 後に次の手順も実行する**。
Fisher 本体は bootstrap では導入されない。

まず `fish` を起動し、次を実行する。

```fish
curl -fsSL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher update
```

[公式の導入方法](https://github.com/jorgebucaran/fisher#installation)で Fisher 関数を読み込み、
`fisher update` で `fish_plugins` にある Fisher 本体・各プラグインを導入する。
成功後は `exec fish` で通常の設定を読み込む。関数・completions 等の生成物は repo に含めない。

ディレクトリ移動の `z` / `zi` は mise 管理の zoxide を使う。
旧 z プラグインを導入済みなら、[履歴の移行手順](meta/MIGRATION.md#z-から-zoxide-への統一)を一度実行する。

## よく使うコマンド

```bash
./bootstrap.sh                   # 新規マシンで一括適用
mise bootstrap --dry-run         # 変更予定を確認
mise bootstrap dotfiles diff     # 配布内容の差分
mise bootstrap                   # 適用（2回目以降）
mise bootstrap dotfiles status   # 適用状態
mise run test                    # 全テスト（CI と同じ入口）
gh auth setup-git                # GitHub の credential helper 登録
```

全コマンドは [docs/commands.md](docs/commands.md) を参照。

## 設定を変更するとき

編集先は [リポジトリ構成](docs/layout.md)、既存設定の取り込みは
[取り込み手順](meta/MIGRATION.md)を参照。symlink 経由の編集は repo の実体も変更する。
template 配布の設定は、編集後に再適用が必要。

適用前に dry-run と差分を確認する。symlink の競合置換には `--force` が必要だが、
template は実ファイルを上書きするため、同じ挙動ではない。
認証情報・履歴・キャッシュは取り込まない。
パッケージ導入時の保護は [サプライチェーン対策](docs/dependencies.md#サプライチェーン対策)を参照。

## 詳細リファレンス

- [docs/layout.md](docs/layout.md) — 構成・パッケージ詳細
- [docs/commands.md](docs/commands.md) — コマンドリファレンス
- [docs/dependencies.md](docs/dependencies.md) — 外部ツール依存
- [docs/troubleshooting.md](docs/troubleshooting.md) — トラブルシューティング
- [meta/LLM-SETTINGS.md](meta/LLM-SETTINGS.md) — LLM 設定パイプライン仕様書
- [meta/MIGRATION.md](meta/MIGRATION.md) — 既存設定の取り込み手順
