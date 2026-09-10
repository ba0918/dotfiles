# Safe Chain を Claude Code の Bash ツールとフックに効かせる 仕様

Status: Draft

置き場所: dotfiles の `docs/spec/safe-chain-path.md`。実装は `process-wrap-shim` から切った短命の
ブランチで行い、マージ先は `process-wrap-shim`（`main` は会社 PC が使うので触らない）。

## 1. 結果

Claude Code の Bash ツールとフックが起動する `npm` / `pnpm` / `bun` / `pip` などのパッケージ
マネージャは、Aikido Safe Chain（`~/.safe-chain/`、dotfiles 管轄外）のラッパーを必ず通る。

今はそうなっていない。Bash ツールとフックの PATH は `~/.claude/settings.json` の `env.PATH` が
決める（正本は `ai/claude/conf.d/40-env.json`。`build-settings` が `$HOME`、`$DOTFILES_ROOT`、
末尾の `$PATH` を実行時の値に展開して書き出す。フックにもこの `env` が渡ることは、Claude Code が
settings の `env` をプロセス環境に取り込む実装を 2026-09-08 に読んだ結果からの推論で、Bash ツール
側は同日実測）。正本の直書きの要素に Safe Chain のシムのディレクトリが無く、末尾の `$PATH`
経由で入る出現は mise の shims より後ろになるので、`npm` は mise の shims に解決されて素通りする
（同日実測: Bash ツールから `npm safe-chain-verify` が `Unknown command`）。対話 fish と非対話
fish は既に Safe Chain を通っている（同日、クリーン環境で実測: どちらも `npm` は関数で、Safe
Chain のシムが mise の shims より前）。

もう 1 つ、シムだけでは足りない。Safe Chain のシムは本体 `safe-chain` を `command -v` で探し、
見つからなければ標準エラーに警告を 1 行出して素の `npm` に落ちる。本体のディレクトリ
`~/.safe-chain/bin` を PATH に載せているのは fish の `init-fish.fish` だけなので、fish を通らない
PATH では保護が黙って外れる（同日実測）。この機械で Safe Chain のシムを前置して試したときに
verify が通ったのは、fish から起動した `claude` の継承 PATH の末尾に `~/.safe-chain/bin` が
入っていたからで、要求した性質ではない。新しい機械では `bootstrap.sh` が `mise bootstrap`
（`build-settings` を含む）の後に Safe Chain を導入するので、初回の settings.json には本体の
ディレクトリが入らない。

成功の観測条件: Claude Code の Bash ツールから `npm safe-chain-verify` を実行すると
`OK: Safe-chain works!` が返る。反例: `Unknown command: "safe-chain-verify"` が返る、または
「safe-chain is not available」の警告の後に素の `npm` が動く。

## 2. 用語

### Safe Chain のシム

`~/.safe-chain/shims/` にある実行ファイル群（2026-09-08 時点で 18 個: bun bunx npm npx pdm
pip pip3 pipx pnpm pnpx poetry python python3 rush rushx uv uvx yarn）。各シムは自分の
ディレクトリを PATH から外してから `safe-chain <コマンド>` を exec し、Safe Chain は PATH の
次に見つかる本体（このマシンでは mise の shims）を実行する。したがって mise で固定した版を
覆さない（実測: シム経由でも `npm --version` は 11.19.0 のまま。`python3` の実体もシム経由と
直接で同じ `/usr/bin/python3`）。

### Safe Chain の本体

`~/.safe-chain/bin/safe-chain`。シムが exec する先。PATH に無いとシムは警告を出して素の
コマンドに落ちる。2026-09-08 時点でこのディレクトリにある実行ファイルは `safe-chain` だけ。

「シム」と言うときは kakoi のシム（`ai/kakoi/shim/codex`）と区別する。本仕様では
前者を「Safe Chain のシム」、後者を「kakoi のシム」と書く。

### 直書きの要素

`40-env.json` の `env.PATH`（conf.d の合成後の値）を `:` で分割した要素のうち、末尾の `$PATH`
という字句を除き、残りの `$HOME` と `$DOTFILES_ROOT` だけを絶対パスに展開した列。`$PATH` の
展開で入る要素（継承した PATH）は含まない。`build-settings` が今 3 つの変数を 1 回の jq で
同時に展開している（2026-09-08 に読んで確認）ことに依らず、この列は「合成後の値から `$PATH`
の字句を除いて 2 変数を展開する」操作で作れる。

## 3. 要件

### 3.1 Bash ツールとフックの PATH の順序

`40-env.json` の `env.PATH` の直書きの要素は、先頭から次の順序で始まる。

1. kakoi のシムのディレクトリ（`$DOTFILES_ROOT/ai/kakoi/shim`）
2. Safe Chain のシムのディレクトリ（`$HOME/.safe-chain/shims`）
3. mise の shims（`$HOME/.local/share/mise/shims`）
4. Safe Chain の本体のディレクトリ（`$HOME/.safe-chain/bin`）

5 番目以降は現状のまま（pnpm、cargo、bun、`.local/bin`、末尾に継承した `$PATH`）。

順序の理由（`docs/dependencies.md` にも書く。3.4）:

- kakoi のシムが先頭: 「ホストが直接実行するシムは PATH の先頭」という既存の原則を
  崩さない。codex は Safe Chain の対象ではないので、1 と 2 の順序は動作に影響しない。
- Safe Chain のシムが mise の shims より前: 後ろだと素通りする（実測）。
- 本体のディレクトリが mise の shims より後ろ: 本体は `command -v safe-chain` で見つかりさえ
  すればよく、前に置く理由が無い。前に置くと、将来このディレクトリに実行ファイルが増えたとき
  mise で固定した版を覆う。`~/.safe-chain` は dotfiles 管轄外で、その状態を dotfiles 側が
  保てないので、依存を作らない。

成功の観測条件: `jq -r .env.PATH ~/.claude/settings.json` を `:` で分割したとき、先頭の
4 要素が上の順序で並ぶ（`$HOME` と `$DOTFILES_ROOT` は展開済みの絶対パス）。反例: Safe Chain
のシムか本体のディレクトリが先頭 4 要素に無い、または Safe Chain のシムが mise の shims より
後ろにある。

### 3.2 生成物の不変条件検査

`ai/claude/build-settings` は、直書きの要素（2 章）の先頭 4 要素が 3.1 の 4 つのディレクトリと
順序どおり一致することを検査し、崩れていれば標準エラーに理由を出して非 0 で終わり、
`~/.claude/settings.json` を書かない。`--dry-run` でも検査し、崩れていれば標準出力に
settings.json の中身を出さない。`--status` は settings.json を書かないので検査しない。

検査対象を直書きの要素に限るのは、継承した `$PATH` が起動元のシェルで変わるためである。fish
から起動した機械では継承 PATH の末尾に Safe Chain のシムと本体が入っている（2026-09-08 実測:
展開後の列で本体が 106 番目と 107 番目に重複）ので、展開後の列全体を見ると、正本から要素を
外しても崩れとして検出できない。直書きの要素だけを見れば、dotfiles が宣言した順序そのものを
起動元に依らず検査できる。

突き合わせは展開後の絶対パスの完全一致で行う。部分一致や正規化はしない: `$HOME/.local/share/mise/shims`
以外の「mise」を含むパス（例: Windows 側の `/mnt/c/.../mise/shims`）は mise の shims では
ない。先頭 4 要素のどれかが欠けている、余分な要素が割り込んでいる、順序が違う、のどれも崩れと
みなす。ディレクトリの実在は検査しない。新しい機械では Safe Chain も mise も未導入のことがあり、
PATH に存在しないディレクトリが並ぶのは無害だからである（3.5）。

「先頭 4 要素の完全一致」にするのは、相対比較（Safe Chain のシムが mise の shims より前、本体が
どこかにある）では 3.1 が宣言した順序より弱く、本体が mise の shims より前にある並びや、Safe
Chain のシムが pnpm の後ろにある並びを通してしまうためである。

この検査を置く理由は、dotfiles の規則「生成物は空でも成功させない」（AGENTS.md 7）。
`40-env.json` は JSON でコメントを書けないので、順序の理由はこの検査のそばのコメントと
`docs/dependencies.md` に置く（3.4）。

成功の観測条件（人が 1 回ずつ手で試す。どの起動元のシェルからでも同じ結果になる）:

- 入れ替え: `40-env.json` の `env.PATH` の先頭 2 要素を一時的に入れ替えて `build-settings --dry-run`
  を実行すると、非 0 で終わり、標準エラーに理由が出て、標準出力に JSON が出ない。
- 欠落: `env.PATH` から `$HOME/.safe-chain/shims` を一時的に外して同じことをすると、同じ結果。
  `$HOME/.safe-chain/bin` を外しても同じ結果。
- 割り込み: 3 番目と 4 番目の間に `$HOME/.cargo/bin` を一時的に挿すと、同じ結果。
- 正常時: 変更後の `40-env.json` から `build-settings --dry-run` を実行すると 0 で終わり、JSON が
  出る。継承 PATH に同じディレクトリが重複していても結果は変わらない。
- 検査のそばに、順序の理由（3.1 の 3 つ）がコメントで書かれている。

反例: 崩れた入力でそのまま JSON が出力される、`settings.json` が書かれる、または正常な入力で
非 0 になる。

### 3.3 apply からの失敗の伝播

`mise/config.toml` の `[bootstrap.hooks.post-dotfiles]` は `build-settings` の後に
`generate-deny.sh opencode-apply` を続けて実行しており、`build-settings` が非 0 で終わっても
hook の終了コードは最後のコマンドのものになる（2026-09-08 に読んで確認）。3.2 の検査を「止まる」
にするため、hook は `build-settings` が非 0 で終わったらそこで非 0 で終わり、後続を実行しない。
後続は opencode の deny 設定の適用なので、検査が崩れている間は opencode 側も更新されない。
これは意図した結果で、正本を直して apply し直せば両方が適用される。

成功の観測条件: 3.2 の「欠落」の状態で `mise bootstrap dotfiles apply` を実行すると非 0 で終わり、
標準エラーに `build-settings` の理由が出る。反例: apply が成功と報告する。

### 3.4 docs の訂正

`docs/dependencies.md` の Safe Chain の項にある「非対話シェル（LLM エージェント等）へは mise の
PATH 経由で shim が渡る」は Claude Code の Bash ツールとフックについて誤りなので、次の内容に
直す。

- fish（対話・非対話とも）は `mise/config.toml` の `env._.path` と `init-fish.fish` の関数で
  Safe Chain を通る。
- Claude Code の Bash ツールとフックは fish を通らず、`~/.claude/settings.json` の `env.PATH`
  （正本 `ai/claude/conf.d/40-env.json`）が PATH を決める。そこに Safe Chain のシムと本体を
  置いている。順序は `build-settings` が検査し、崩れていれば apply が止まる。
- 順序の理由（3.1 の 3 つ）。
- 隔離（kakoi）の中でも同じ PATH を継承するので、codex が起動するパッケージマネージャも
  Safe Chain を通る（隔離の中で `npm safe-chain-verify` と実際の `npm install` が通ることは
  実測済み）。`~/.safe-chain` は隔離の中では読み取り専用で、マルウェア DB の更新はホスト側の
  実行に任せる（隔離の中で DB の更新が要る状態になったときの振る舞いは未検証）。
- Claude Code が起動する MCP サーバーも同じ `env.PATH` で起動すると考えられる（未検証）。
  今は `npx` / `uvx` で起動する MCP サーバーが無い（context7 は HTTP）ので影響は無い。
  browser-use プラグインを有効にすると `uvx` 起動なので Safe Chain のシムを通る。

同じ `docs/dependencies.md` の「hook の repo 外依存」の節にある「mise の shims ディレクトリを
2 番目に置き」は 3.1 の順序で偽になる（mise の shims は 3 番目）ので、3.1 の順序に合わせて直す。

`docs/troubleshooting.md` の「Claude Code の hook のたびに `run-if-present: command not found`」の
行にある判定「`jq -r .env.PATH` が kakoi の shim ディレクトリで始まり、次に
`~/.local/share/mise/shims` が来ていなければ `build-settings` を実行し直す」は、3.1 の順序では
常に「来ていない」になり、`build-settings` を何度実行しても解消しない誤診になる。判定を
3.1 の順序（先頭 4 要素）に合わせて直す。

`docs/commands.md` の「サプライチェーン対策の確認」の項に、公開から 48 時間未満のパッケージが
弾かれたときの逃げ道として、Safe Chain の環境変数 `SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS` と
`SAFE_CHAIN_MINIMUM_PACKAGE_AGE_EXCLUSIONS`（npm 向けは
`SAFE_CHAIN_NPM_MINIMUM_PACKAGE_AGE_EXCLUSIONS`）を、そのコマンド 1 回だけに付ける使い方で
書く。Safe Chain 自体を外す手順は書かない。

成功の観測条件: 人が 3 ファイル（`dependencies.md` の 2 か所、`troubleshooting.md`、
`commands.md`）を読み、上の 5 点と逃げ道が書かれ、古い順序の記述が消えていること。反例:
「mise の PATH 経由で shim が渡る」の文が残っている、順序の理由が無い、mise の shims を
「2 番目」とする記述や「次に mise の shims が来ていなければ」という判定が残っている。

### 3.5 Safe Chain が無いマシンでの振る舞い

Safe Chain が未導入のマシンでは、`env.PATH` に存在しないディレクトリが並ぶだけで、コマンドの
解決はそのまま次の要素に進む。Safe Chain のシムだけあって本体が無い場合は、シム自身が警告を
出して本体無しの `npm` などに落ちる（シムの実装。2026-09-08 に、PATH から本体のディレクトリの
全部の出現を外して実測済み）。本仕様はこの振る舞いに何も足さず、受け入れの検証でも再計測しない
（Safe Chain 側の振る舞いで、この変更の対象ではない）。3.1 で本体のディレクトリを明示するのは、
本体が導入済みなのに PATH に無い状態（1 章の「黙って外れる」）を無くすためであり、未導入の
機械で保護を生む手段ではない。

## 4. 受け入れの検証

1. `mise bootstrap dotfiles apply`（post-dotfiles hook が `build-settings` を実行）の後、
   `claude` を完全に終了して起動し直す（`/clear` ではプロセスも Bash ツールの PATH も
   更新されない）。
2. Bash ツールから次を実行する。

   ```
   type -a npm | head -1        # /home/<user>/.safe-chain/shims/npm
   type -a python3 | head -1    # /home/<user>/.safe-chain/shims/python3
   npm safe-chain-verify        # OK: Safe-chain works!
   npm --version                # mise で固定した版のまま
   ```

3. フックがシムを通ることを、Bash ツールからフックのスクリプトを Claude と同じ形で起動して
   確かめる。`SAFE_CHAIN_LOGGING=1 SAFE_CHAIN_LOG_FILE=<一時ファイル>` を付けて
   `~/.claude/hooks/block_dangerous_command.py` に JSON を標準入力で渡し、ログに
   「Bypassing safe-chain for non-pip invocation: python3 …」が残り、終了コード 0。
   フックの PATH が Bash ツールと同じであることは 1 章の推論に依る。
4. 隔離の中でも通ることを、**Bash ツールから**確かめる（fish から起動すると変更前でも通るので
   判別にならない）。`kakoi --workspace <任意のリポジトリ> -- npm safe-chain-verify` が
   `OK: Safe-chain works!` を返す（`--policy-file` 無し、配布済みのプロファイルで）。
5. 3.2 の観測条件 5 つと 3.3 の観測条件を 1 回ずつ手で試す。

5 のような一時的な破壊を自動テストにはしない（6 章）。

## 5. 受け入れるコスト

実測（2026-09-08）に基づく。仕様の要件ではなく、判断の記録。

| 場面 | 変更前 | 変更後 |
|---|---|---|
| `python3` の起動 1 回（フック、statusline、通知も通る） | そのまま | +0.12 秒 |
| 同上、Safe Chain のサーバー不達・DNS 失敗 | そのまま | +0.12 秒（変わらない。passthrough では DB を取りに行かない） |
| `npm install`（キャッシュ済み） | 0.3 秒 | 約 2 秒 |
| 同上、Safe Chain のサーバー不達（URL を不達先に差し替えて模擬） | 0.3 秒 | 約 4 秒（キャッシュで検査し成功） |
| 同上、DNS 失敗（存在しないホスト名で模擬） | 0.3 秒 | 約 5 秒（同上） |
| 隔離の中の `npm install`（キャッシュ済み） | 素通り | 約 0.5 秒で成功 |

完全オフライン（ネットワーク自体が無い状態）は未計測。

Safe Chain のシムは `python` / `python3` も含むため、PATH で解決される `python3` の起動が全部
+0.12 秒になる。Claude Code のフック設定（`ai/claude/conf.d/30-hooks.json`、`10-base.json`）で
数えると、Bash ツール 1 回につき 1 本（PreToolUse）、Edit / Write 1 回につき 2 本（PostToolUse）、
statusline の更新ごとに 1 本、通知（permission_prompt / idle_prompt）と Stop ごとに 1 本
（`python3 -m claude_notify`）。引数・終了コード・標準入力（パイプ、ヒアドキュメント）は保たれる。
標準入力を閉じた非対話の `npm install` も確認待ちで止まらずに完了する（バイナリに対話プロンプトの
文字列も無い）。この遅延は「Safe Chain を bypass 不可にする」を優先して受け入れる。

隔離の中の codex は、これまで Safe Chain を素通りしていたので、公開 48 時間未満のパッケージが
弾かれる規則が新しく効き始める。これは狙いそのもので、逃げ道は 3.4 の環境変数。

## 6. 作らないもの

- `python` / `python3` を除いた選別版のシムのディレクトリ。`python3 -m pip install` が素通りに
  なり、bypass 不可の方針と矛盾する。
- cron や `sh` 系の非対話シェルへの対応。今の dotfiles に使い道が無い。
- kakoi のプロファイルで `~/.safe-chain` を書けるようにすること。隔離の中の LLM が
  シムや本体を書き換えて無効化できるようになる。
- `build-settings` 用のテストハーネス。不変条件検査（3.2）で足りる。

## 7. 却下した代替案

- `~/.safe-chain/shims` を mise の shims より後ろに置く: 素通りが直らない（実測）。
- `~/.safe-chain/bin` を mise の shims より前に置く: 前に置く理由が無く、bin の中身が
  `safe-chain` だけであることに依存する（3.1）。
- fish の関数（`init-fish.fish`）を Bash ツールにも読ませる: Bash ツールは `bash -c` で
  fish を通らず、`BASH_ENV` は廃止済み（2026-09-08）。
- 不変条件を展開後の PATH 全体に掛ける: 継承 PATH が同じディレクトリを持ち込む機械で崩れを
  検出できず、結果が起動元のシェルで変わる（3.2）。
- 不変条件を相対比較（シムが mise の shims より前、本体がどこかにある）にする: 3.1 の順序より
  弱く、宣言した順序に反する並びを通す（3.2）。
- 順序を自動テストで守る: `build-settings` は入力ディレクトリ（`conf.d`）と出力先が固定で
  差し替える口が無く、テストのために実物の `conf.d` を壊すか、その口を足すしかない。
  1 行の順序のためにその口を足すコストに見合わない。不変条件検査で同じ目的を達せる。

## 8. 未決

なし。

## 9. 委譲

- 不変条件検査のエラーメッセージの文面（中立な英語、AGENTS.md 3）と、検査を置く位置と
  直書きの要素の作り方（2 章の定義どおりの列が作れる位置ならどこでもよい。`build-settings` の
  今の 1 回の展開を 2 段に分けても、展開前の値を退避して `$PATH` の字句を除いてもよい。
  `--status` の分岐の後。3.2 の観測条件を満たせばよい）。
- post-dotfiles hook を失敗で止める書き方（`set -e` を置くか `&&` で繋ぐか）。理由: どちらでも
  3.3 の観測条件を満たす。
- `docs/dependencies.md`、`docs/troubleshooting.md`、`docs/commands.md` の文面。理由: 3.4 の
  5 点と逃げ道が入り、古い順序の記述が消えていればどの書き方でも観測条件を満たす。
