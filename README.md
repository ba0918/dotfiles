# dotfiles

`ba0918` の dotfiles。**mise** の `bootstrap` で管理する。

## セットアップ（新マシン / WSL 内）

前提: まっさらな WSL。Windows 側の環境構築は対象外。

```bash
# 1. mise を入れる (まだ無ければ)
curl https://mise.run | sh

# 2. repo を clone（場所は自由。repo 内の相対パスで解決される）
git clone <this-repo> ~/develop/dotfiles

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

`bootstrap.sh` は配置場所を自動解決し、必要な apt リポジトリを登録する（sudo が必要）。
初回適用後は fish から `mise bootstrap` を使える。mise を apt で導入した環境では
`apt upgrade` で更新する。

## fish プラグイン

tide / fzf.fish / z は fisher 管理。`fish_plugins` で宣言されているので
新規マシンでは `fisher install` で再現する（関数・completions 等の生成物は
repo に含めない）。

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
