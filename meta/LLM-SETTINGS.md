# LLM エージェント設定の conf.d 分割管理と統一配布

Claude Code / OpenCode の設定ファイルを宣言的に管理する仕組みの仕様書。

## 概要

```
deny-patterns.yaml（正本）
        │
        ▼
generate-deny.sh（純粋変換器）
        │
   ┌────┴────┐
   ▼         ▼
Claude     OpenCode
20-deny    opencode-apply
 .json     (in-place patch)
   │
   ▼
conf.d/*.json（分割設定）
   │ 番号順 deep merge
   ▼
build-settings
   │ + runtime allow 保持
   ▼
~/.claude/settings.json
```

## deny-patterns.yaml

`ai/shared/deny-patterns.yaml` は LLM に読ませたくないファイルパターンの唯一の正本。
カテゴリはグルーピングのためだけに存在し、生成時にフラットに展開される。

### パターンの種類

| 記法 | 意味 | 例 |
|------|------|-----|
| `"file.ext"` | ファイルパターン | `"credentials.json"` |
| `"*.ext"` | ワイルドカード | `"*.pem"` |
| `".dir/**"` | ディレクトリツリー（$HOME 相対） | `".ssh/**"` |
| `"//$HOME/path"` | 絶対パス deny | `"//$HOME/Documents/**"` |

### カテゴリ一覧

| カテゴリ | 用途 | ツール |
|----------|------|--------|
| credentials | 認証情報ファイル | Claude / OpenCode |
| keys | 鍵ファイル | Claude / OpenCode |
| ssh | SSH 関連ファイル | Claude / OpenCode |
| environment | 環境変数ファイル | Claude / OpenCode |
| package_manager | パッケージマネージャ設定 | Claude / OpenCode |
| database | DB 接続情報 | Claude / OpenCode |
| network | ネットワーク認証 | Claude / OpenCode |
| directories | $HOME 以下の除外ディレクトリ | Claude / OpenCode |
| history | シェル/エディタ履歴 | Claude / OpenCode |
| personal_directories | 個人ディレクトリ（Documents 等） | Claude のみ |
| write_deny | 書き込み禁止パターン | Claude のみ |
| read_shortform | 短縮形 Read deny | Claude のみ |
| bash_destructive | 破壊コマンド deny（`rm` / `rmdir` は含めない。場所で判定する `block_dangerous_command.py` の担当） | Claude のみ |

### パターンを追加する手順

1. `ai/shared/deny-patterns.yaml` の適切なカテゴリにパターンを追加
2. `ai/claude/build-settings` を実行（`~/.claude/settings.json` に反映）
3. `scripts/generate-deny.sh opencode-apply` を実行（`~/.opencode/opencode.json` に反映）
4. `mise bootstrap` 実行時は post-dotfiles hook が自動で 2, 3 を実行

## generate-deny.sh

`scripts/generate-deny.sh` は deny-patterns.yaml を各ツールの形式に変換する
**純粋変換器**。パターンは 1 つも持たない。

### カバレッジ検査（必ず通る前提）

変換前に、yaml 内の全パターン行数とカテゴリ経由で抽出できた件数を突き合わせ、
一致しなければ異常終了する。これは次の 2 つの「静かな失敗」を防ぐためにある。

- **パーサの破損** — 以前は抽出正規表現が GNU awk 専用の `\s` を使っていたため、
  Debian/Ubuntu 既定の mawk では 1 件も抽出できなかった。それでも終了コードは 0 で
  JSON も妥当だったので、**deny が空の settings.json** が黙って書かれていた
- **カテゴリの登録漏れ** — yaml に新カテゴリを足しても、スクリプト側の
  `CATEGORIES` 表に足さなければ丸ごと無視される

カテゴリは「カテゴリ名:エミッタ」形式の 1 つの表（`CATEGORIES`）で管理し、
カバレッジ検査・claude 出力・opencode 出力のすべてがこの表から駆動される。
これにより「検査には登録したが出力ブランチに足し忘れる」という不一致が
構造的に起きない。

新しいカテゴリを追加するときは、yaml と `CATEGORIES` 表の**両方**に追加すること
（エミッタ: `file` = 両ツール / `directory` = 両ツール・home スコープ /
`read` `write` `bash` = Claude 専用。忘れた場合は検査が落として教えてくれる）。

なお抽出の正規表現は **POSIX 互換に保つこと**。`\s` や `\d` のような GNU 拡張は
mawk で無言に一致しなくなる。

### サブコマンド

| コマンド | 出力 |
|----------|------|
| `claude` | Claude Code 形式の JSON を stdout に出力 |
| `opencode` | OpenCode 形式の JSON を stdout に出力 |
| `opencode-apply` | `~/.opencode/opencode.json` の deny を in-place 更新 |

### 変換ルール

**Claude Code 形式:**
- ファイルパターン → `Read(**/pattern)`
- ディレクトリ → `Read(~/.dir/**)` + `Read(//$HOME/.dir/**)`
- Write deny → `Write(pattern)`
- Bash deny → `Bash(command)`

**OpenCode 形式:**
- ファイルパターン → `"**/pattern": "deny"`（JSON オブジェクト）
- ディレクトリパターン → `"~/pattern": "deny"`（`~` は opencode がホーム展開する）。
  `**/` 前置にすると repo 自身の `fish/.config/` 等まで deny されてしまうため、
  deny-patterns.yaml の `$HOME` 相対の宣言に合わせて home スコープにする

## conf.d 分割管理

`ai/claude/conf.d/` に Claude Code の settings.json を関心ごとに分割して管理する。

### ファイル一覧

| ファイル | 内容 | 管理方式 |
|----------|------|----------|
| `10-base.json` | model / effort / language / outputStyle 等 | 手動 |
| `20-deny.json` | permissions.deny | **生成物**（generate-deny.sh が生成、gitignore 済み）|
| `25-allow.json` | permissions.allow / ask ベースライン | 手動 |
| `30-hooks.json` | hooks 設定 | 手動 |
| `40-env.json` | env 設定 | 手動 |
| `50-sandbox.json` | sandbox 設定 | 手動 |
| `60-plugins.json` | enabledPlugins / extraKnownMarketplaces | 手動 |

### 設計ルール

- **番号順 deep merge**: ファイル名の番号順にソートし、jq の `*` で deep merge
- **1 キー 1 ファイル**: jq の `*` は配列を置換する（append しない）ため、
  同じ配列キー（例: `permissions.allow`）は 1 つのファイルにしか書かない
- **$HOME 変数**: パスは `$HOME` で記述し、build-settings が build 時に展開する。
  `//` プレフィックス内の `$HOME`（`//$HOME/...`）は先に処理して `///` 化を防ぐ

## build-settings

`ai/claude/build-settings` は conf.d を合成して `~/.claude/settings.json` に書き出す。

### 処理フロー

```
1. generate-deny.sh claude → conf.d/20-deny.json を生成
2. conf.d/*.json を番号順に deep merge → base
3. $HOME を展開（//$HOME/ は //home/user/ に正しく変換）
4. 既存 settings.json があれば runtime allow/ask を抽出して base に追加
5. 結果を ~/.claude/settings.json に書き出し
```

### 管理キー vs 非管理キー

| 種別 | キー | build の挙動 |
|------|------|-------------|
| 管理キー | deny / hooks / env / model / sandbox / plugins 等 | build が上書き |
| 非管理キー | `permissions.allow` / `permissions.ask` | 既存値を保持（runtime 追記分を引き継ぐ）|

### permissions.allow の二層構造

| 層 | 出典 | 用途 |
|----|------|------|
| ベースライン | `conf.d/25-allow.json` | 定番の allow（git / rg / cargo 等）|
| runtime 追記 | 既存 `~/.claude/settings.json` | Claude Code が対話中に蓄積した allow |

`--clean` フラグで runtime 追記をリセットし、ベースラインのみにできる。

### サブコマンド

| フラグ | 動作 |
|--------|------|
| (なし) | build + runtime allow 保持 + 書き込み |
| `--dry-run` | build + stdout に出力（書き込まない）|
| `--clean` | runtime allow をリセットしてベースラインのみ |
| `--status` | managed vs runtime allow の内訳を表示 |

## mise bootstrap との統合

```toml
[bootstrap.hooks.post-dotfiles]
run = """
REPO_ROOT="$(dirname "$(dirname "${MISE_GLOBAL_CONFIG_FILE}")")"
bash "$REPO_ROOT/ai/claude/build-settings"
bash "$REPO_ROOT/scripts/generate-deny.sh" opencode-apply
"""
```

`mise bootstrap` の処理順:

1. **packages** — apt:jq 等を導入
2. **pre-dotfiles** — MISE_GLOBAL_CONFIG_ROOT の整合性検証
3. **dotfiles** — symlink / template 配布（opencode.json 含む）
4. **post-dotfiles** — build-settings + opencode-apply（deny 正本から設定を合成）
5. **tools** — バイナリ導入

Claude Code の settings.json は `[dotfiles]` 管轄外。runtime 追記との merge が
必要なため、post-dotfiles hook で build-settings が直接書き込む。

## OpenCode の deny 管理

OpenCode の `opencode.json` は mise template で配布される。deny パターンは
2 段階で適用される:

1. **template 配布** — `mise bootstrap dotfiles apply` が template をレンダリング
2. **post-dotfiles** — `generate-deny.sh opencode-apply` が deny-patterns.yaml から
   `permission.read` と `permission.external_directory` の deny を上書き

`opencode-apply` は既存の allow エントリ（`*.env.example` 等）を保持しつつ、
deny エントリだけを正本で置換する。

そのため repo 内の `ai/opencode/opencode.json` は
`permission.read` / `permission.external_directory` に **deny を一切書かない**。
書いても post-dotfiles で必ず捨てられるので、リテラルを残すと正本から静かに
乖離するだけになる（実際に `.docker/**` や履歴ファイル系がズレていた）。
`scripts/test_generate_deny.sh` がこの不変条件を検査する。

一方 `permission.bash` の deny（`sudo *` 等）は生成対象外。yaml の
`bash_destructive` は Claude 専用カテゴリなので、こちらは手書きのまま残す。
