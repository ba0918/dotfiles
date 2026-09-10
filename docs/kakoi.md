# kakoi の運用と保護範囲

`codex` は kakoi（<https://github.com/ba0918/kakoi>）の隔離の中で起動する。
境界を組み立てるのは kakoi 本体で、dotfiles 側が持つのは起動シム・プロファイル・
代替コマンドの 3 つ。

## 導入

`mise/config.toml` の `[tools]`（`github:ba0918/kakoi`）で導入する。
自分がリリースするので `minimum_release_age` は per-tool で 0d。run-if-present と同じく
github backend なので、aqua registry を通る AI CLI と違い cosign / Attestations 検証は無い。
clone から `cargo install` した版が `~/.cargo/bin` に残っていると fish では先に当たる
（fish の PATH は `~/.cargo/bin` が mise の installs ディレクトリより前。
`ai/claude/conf.d/40-env.json` の `env.PATH` は逆で mise の shims が先）。
`cargo uninstall kakoi` で消す。mount namespace を組む `bwrap` は
`[bootstrap.packages]` の `apt:bubblewrap` で導入する。入れる前に `codex` を打つと、
シムは最終行の `exec kakoi` に届いて `not found` の終了コード 127 で落ちる
（シムは本体の不在を自分では見ない）。

### 旧名 process-wrap からの移行

kakoi は 0.2.0 で process-wrap から改名した。旧名との互換は無く、環境変数
`PROCESS_WRAP` / `PROCESS_WRAP_SHIM_OFF`、設定ディレクトリ `~/.config/process-wrap/`、
共有ディレクトリ `/tmp/process-wrap` はどれも読まれない。旧名の頃に apply 済みのマシンでは、
`mise install` と `mise bootstrap dotfiles apply` で新しい名前の側がそろった後も、次が残る。

- `~/.config/process-wrap/secrets/gh-token`: 下の「GitHub トークン」の手順で
  `~/.config/kakoi/secrets/` へ移す。移すまで隔離の中に token は入らない
- `~/.config/process-wrap/profile/default.toml` と `~/.local/lib/process-wrap/`:
  もう読まれない配布物。`[dotfiles]` の宣言から外れたので unapply では消えず、手で消す
- mise が入れた旧ツール `github:ba0918/process-wrap`: `[tools]` から外れても自動では消えない。
  `mise uninstall --all github:ba0918/process-wrap` で消す（`mise prune` は無関係の
  ツールまで消すので使わない）
- fish のユニバーサル変数 `fish_user_paths` に残る旧シムのディレクトリ
  （`config.fish` の `fish_add_path` が足したもの）: 実在しないので害は無いが、
  `set -U fish_user_paths (string match -v -- '*/ai/process-wrap/shim' $fish_user_paths)` で外す
- `/tmp/process-wrap`: 何も読まないので放置してよい

## 起動経路と PATH

`codex` は `ai/kakoi/shim/codex` を経由して起動する。
この起動シムを mise 管理の codex 本体より前に置く方法は、起動元によって異なる。

| 起動元 | 設定箇所 | 理由 |
|---|---|---|
| 対話 fish | `mise/config.toml` の `env._.path` | mise が PATH を組み直しても起動シムを先頭に保つ |
| 非対話 fish | `config.fish` の `fish_add_path` と `mise activate fish --shims` | 対話用 hook-env が走らない経路でも起動シムとツールを解決する |
| Claude Code の Bash tool / hook / statusLine | `ai/claude/conf.d/40-env.json` → `build-settings` → settings.json | fish を通らないため、生成済みの `env.PATH` を使う |
| 隔離内の Codex / hook | 起動元の PATH とプロファイルの `env.path-prepend` | PATH を継承し、画像ペースト用の代替コマンドの場所だけを追加する |

Claude Code 用 PATH の先頭は、次の順序に固定する。

```text
$DOTFILES_ROOT/ai/kakoi/shim
$HOME/.safe-chain/shims
$HOME/.local/share/mise/shims
$HOME/.safe-chain/bin
```

起動シムが mise より後ろなら Codex が隔離を、Safe Chain の shims が後ろなら
パッケージマネージャが検査を素通りする。Safe Chain 本体が PATH に無い場合も、
シムは警告して未保護のコマンドへ進む。本体を mise より後ろに置くのは、
そのディレクトリに増えた実行ファイルで mise 管理の版を覆わないため。
`build-settings` は順序が崩れていれば書き込まずに失敗する。
検査対象の定義は [Safe Chain の仕様](spec/safe-chain-path.md)を参照。

Codex の hook で `run-if-present` を使うには、起動元の PATH で解決できる必要がある。
kakoi 自体は mise のディレクトリを追加しない。
`which codex` が mise の installs ディレクトリを返したら起動シムを経由していない。
具体的な確認・復旧手順は [トラブル対応](troubleshooting.md#claude-path)を参照。

Safe Chain の `~/.safe-chain/certs` は `hide` で隔離専用の書ける一時領域にする。
短命な CA の更新を可能にし、ホストの証明書・秘密鍵は共有しない。
本体とシムは既定の読み取り専用を維持する。隔離を終了すると一時証明書は消える。
DB キャッシュの保存先はこの例外に含まれず、保存できない場合は再取得の警告が出ることがある。

## 起動シムと保護の限界

このシムディレクトリはプロファイルの `ro` にも載せてあるので、dotfiles をワークスペースに
して起動しても隔離の中からその場で書き換えられない（守りは部分的で、祖先ディレクトリの
改名による差し替えは残る。仕様 5.6 節）。
ただし dotfiles をワークスペースにすると、ホストが起動のたびに読む `mise/config.toml`
（シムを PATH の先頭に置く `env._.path` を持つ）と `fish/.config/fish/config.fish`、
ホストの Claude Code が `~/.claude/rules` / `~/.claude/agents` / `~/.claude/output-styles`
のリンク越しに読む指示文書（リンク先は `ai/shared/` と `ai/claude/` 配下）も `rw` の中に
入り、隔離の中から書き換えられる。この checkout の実体までプロファイルの `ro` に
載せるのは、ホストが人の目を通さず実行するコード（シムと `ai/shared/hooks`）だけで、
これらを `ro` にするとそれらのファイルを編集する作業ができなくなるので塞いでいない。
防波堤は、apply や新しいシェルを開く前に `git diff` を見ること。
シムは kakoi 同梱の雛形（`examples/shim/codex`）の写し。取り込みは、導入した版のタグの
雛形と 1 バイトも違わない写しから始める（`v0.2.0` は導入した版に読み替える）。

```bash
curl -fsSL https://raw.githubusercontent.com/ba0918/kakoi/v0.2.0/examples/shim/codex |
  cmp - ai/kakoi/shim/codex
```

それ以後に手を入れてよいのは冒頭のツール節にある
2 つの一覧（下の「素通しは許可リストだけ」）だけで、本体はいつでも雛形と一致させたまま
にする。雛形が更新されたら写し直したうえで、その 2 つの一覧を入れ直す。

## 素通しは許可リストだけ

既定ではすべての呼び出しが隔離に入る。`--help` も `--version`
も例外ではなく、サブコマンドを見て隔離の要否を決める分岐も無い。外れるのは
`KAKOI_SHIM_OFF=1` を付けたときと、シム冒頭の許可リストに名前を足したときだけで、
許可リストとフラグ無しの一覧はどちらも空で配っている。`app-server` / `mcp-server`
（Claude Code の codex plugin 経由の実行）も同じく隔離に入る。壊れたときにどちらの一覧へ
名前を足すか、あるいはどちらでもなくプロファイルを直すかは、シムのヘッダーにある表に従う。

## プロファイル

境界の中身（`rw` / `rw-file` / `ro` / `hide`、`.env` の走査、
ネットワーク、環境変数、秘密、git の URL 書き換え）はプロファイルが持つ。正本は
`ai/kakoi/profile/default.toml` で、`mise bootstrap dotfiles apply` が
`~/.config/kakoi/profile/default.toml` に実体として書き出す（template モード）。
symlink で配らないのは、設定ディレクトリのファイルが `rw` の中を通る symlink だと、
dotfiles をワークスペースにした起動が仕様 5.6 節の検査で止まるため。直したら apply し直す。
`kakoi init` は使わない（配布後は `profile/default.toml` が既にあるので、
仕様 4.1 節どおり `init` は種類 `path` の診断で止まる）。プロファイルが `ro` に載せる
`~/.claude/CLAUDE.md`・`~/.claude/statusline.py`・
`~/.codex/hooks.json` の 3 つも `[dotfiles]` から template で実体を配る（`ro` が効くのは
symlink を解決した実体なので、`rw` の `~/.claude` / `~/.codex` の直下に残るリンクの名前は
隔離の中から消して通常ファイルに差し替えられる。仕様 5.6 節・6.2 節）。
`statusline.py` はホスト側で実行されるため、書き換えられると隔離の外でコードが動く。
hooks は個別リンクで配るが、配布先の親ディレクトリとリンク先 `ai/shared/hooks` を
両方 `ro` にする。前者はリンクの差し替え、後者はリンク越しの書き換えを防ぐ。
rules / agents / output-styles のリンク先は `ro` に含めず、上の保護の限界として扱う。

既に apply 済みのマシンでは、この 3 つが旧方式の symlink のまま残っていることがある。
apply の後に実体へ置き換わったかを確かめる手順と、リンクが残ったときの直し方は
[トラブル対応](troubleshooting.md#regular-files) を参照。

## GitHub トークン

`gh auth login` の認証情報（`~/.config/gh`、全リポジトリ +
workflow + gist に届く OAuth token）はプロファイルが隠す。代わりに
`~/.config/kakoi/secrets/gh-token` に置いた **fine-grained PAT** を、プロファイルの
`[secrets]` の `GH_TOKEN` が隔離の中へ渡す。置き場所は `init` を使えないので手で作る:

```bash
mise bootstrap dotfiles apply                  # 先にプロファイルを配る
mkdir -m 700 ~/.config/kakoi/secrets
# 旧名 process-wrap の頃に置いた token があれば移す（無ければ新しい PAT をここに置く）
mv ~/.config/process-wrap/secrets/gh-token ~/.config/kakoi/secrets/gh-token
```

`~/.config/gh` を意図的に un-hide する手段は用意していない。箱の中では環境変数も
本物の `gh` バイナリも見えるので、中に入った token を中で絞ることはできない。
境界は **token に GitHub 側が付ける権限**そのもので、Free プランの private
リポジトリは ruleset を張れないため、main への直 push / force push も通る。
`gh` / `git` から見える権限の実測は次の通り（2026-08-31 時点、
個人所有の private リポジトリで確認）:

| 操作 | 結果 | 止めているもの |
|---|---|---|
| ブランチ push、`gh pr create` / `view` / `merge`、`gh issue create` / `comment` / `close` | 通る | — |
| main への force push | 通る | なし（ruleset は Free の private では使えない） |
| `gh issue delete` | 通る | なし（所有者は admin 扱い） |
| `.github/workflows/` を含む push | 拒否 | token に Workflows 権限が無い |
| リポジトリ設定の変更（`gh api -X PATCH repos/...`） | 拒否 | token に Administration 権限が無い |
| gist 作成 | 拒否 | token に gist 権限が無い |
| `gh pr checks` | 失敗 | fine-grained PAT には Checks 権限自体が存在しない（`gh run list` / `gh run view --log` で代替） |

token ファイルが無ければ警告が 1 行出るだけで、GitHub の認証情報は一切入らない。
中身が空なら起動を拒否する。ホストのシェルに `GH_TOKEN` / `GITHUB_TOKEN` が
設定されていても箱には入らない（プロファイルの `env.unset` が名前で落とし、秘密の
段が同名の変数を先に消す）。token を入れるときは `~/.ssh` が隠れているため、
`git@github.com:` / `ssh://git@github.com/` の remote をプロファイルの
`[git.instead-of]` で HTTPS に読み替える（ホストの `.gitconfig` は触らない）。token は
`gh auth git-credential`（`.gitconfig` の credential helper）経由で git にも渡る。

推奨する token の権限（All repositories）: Contents / Issues / Pull requests を
Read and write、Actions / Commit statuses を Read。Workflows と Administration は
付けない。有効期限が切れたら同じファイルに置き直す。

## WSL の interop

`.exe` を実行すると binfmt_misc が `/init` を呼び、`/run/WSL` の
ソケット経由で **Windows 側にプロセスを起動する**。生まれたプロセスは隔離の
外で動き、`\\wsl$` 経由で distro 全体を読めるので、ドライブを隠すだけでは
（`.exe` を持ち込めば）抜けられる。そのためプロファイルは `/run/WSL` も隠して
interop 自体を切っている。

## 画像ペースト

codex の画像ペースト（Ctrl+V）は WSL ではこの interop に依存している。
codex のプロセス内クリップボード読み出しは WSLg では成功せず（compositor が出すのは
`image/bmp` で codex は `image/png` を要求する）、`powershell.exe` に
`Get-Clipboard -Format Image` を実行させて `C:\...` を `/mnt/c/...` に読み替える
フォールバックへ必ず落ちる。隔離の中ではその要求だけを
`~/.local/lib/kakoi/bin/powershell.exe` が肩代わりする。正本は
`ai/kakoi/bin/powershell.exe` で、プロファイルと同じく template で実体を配り、
プロファイルの `env.path-prepend`（`~/.local/lib/kakoi/bin`）が隔離の中でだけ
PATH の先頭に足す。apply したら
`test -x ~/.local/lib/kakoi/bin/powershell.exe` で実行ビットを確かめ、
落ちていれば `chmod +x` する。clipboard2path-wsl のデーモンが
`$XDG_RUNTIME_DIR/clipboard2path/latest.png` に保存した画像を、`hide` で空の書ける
ディレクトリに差し替わっている `/mnt/c` 配下へコピーし、codex が期待する `C:\` 形式の
パスを返す。`/run/user` は隠しているので、読み出し元だけプロファイルの `ro` に
`/run/user/1000/clipboard2path` として名指しで戻してある。
`Get-Clipboard -Format Image` 以外の PowerShell 呼び出しは拒否する。

## 検証

境界の検証は kakoi 側のテスト（kakoi の checkout で `cargo test`）。
dotfiles 側にハーネスは持たない。シムの写しを本物の codex を動かさずに確かめる手順は、
シムのヘッダーに書いてある（PATH の先頭に stand-in を 2 つ置き、シムが何を決めたかを
印字させる）。
