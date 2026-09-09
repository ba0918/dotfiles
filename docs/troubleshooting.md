# トラブルシューティング

| 症状 | 原因と対処 |
|------|-----------|
| `mise bootstrap dotfiles apply` で "refusing to overwrite existing files" | `$HOME` 側に実ファイルがある。内容を確認して `--force` で置換するか退避する |
| `git` 実行時に `delta: command not found` | delta 未導入。`mise bootstrap` で入れるか一時的に `git -c core.pager=less ...` で回避 |
| `git commit` が `[pre-commit] secretlint is not installed` で拒否される | `git/.config/secretlint/node_modules` が無い。`mise run bootstrap`（または `npm ci --prefix ~/.config/secretlint`）で入れる |
| `~/.gitconfig` に突然大量の差分 | `gcm configure` などツールが symlink 先に書き込んだ可能性。差分を確認して整理する |
| dotfiles apply で repo 内ファイルが symlink 化する | `[dotfiles]` がディレクトリ symlink を指す場合に起きる。file-level 宣言でなくディレクトリ単位で宣言する |
| Windows 側でコピーしたファイルに `:Zone.Identifier` が付く | global ignore（`~/.config/git/ignore`）で除外済み |
| `clipboard2path-wsl` が起動しない / `command not found` | `github:ba0918/clipboard2path-wsl` の導入とサービスの再生成を確認する。[導入・移行手順](commands.md#clipboard2path-wsl)を参照 |
| `mise x clipboard2path-wsl` で "not found in tool registry" | ショート名解決が効かない。`github:ba0918/clipboard2path-wsl` のフル名を指定する。shim 経由では問題ない |
| `herdr/.config/herdr/config.toml` に意図しない差分 | herdr が実行時に config.toml を書き戻す（write-through）。差分を確認して整理する |
| herdr plugin の keybinding が効かない | プラグイン未導入。`herdr plugin install smarzban/herdr-file-viewer` で再現する |
| codex の security hook が効かない | フック未 trust の可能性。`codex /hooks` で trust する。または symlink が未適用（`mise bootstrap dotfiles status` で確認） |
| `~/.codex/hooks` の apply が "refusing to overwrite" | 旧方式のディレクトリ symlink が残っている。`rm ~/.codex/hooks`（symlink 自体を消す）してから `mise bootstrap dotfiles apply` でファイル単位に張り直す |
| apply しても `~/.claude/CLAUDE.md` などが symlink のまま残る | [確認と復旧手順](#regular-files) |
| `[dotfiles]` から外した配布先にリンク切れ symlink が残る（例: `~/.claude/hooks/run-optional.sh`） | `mise bootstrap` は宣言から消えたリンクを回収せず、`dotfiles status` にも出ない。`find ~/.claude ~/.codex -maxdepth 2 -xtype l` で探して `rm` する。宣言を外す前なら `mise bootstrap dotfiles unapply <配布先パス>` で回収できる |
| apply しても `~/.claude/bash-env.sh` が残る | [確認と復旧手順](#legacy-bash-env) |
| hook が `ModuleNotFoundError: hook_input` で落ちる | 配布先ディレクトリに `hook_input.py` が無い。`mise bootstrap dotfiles status` で確認 |
| `generate-deny.sh` が "deny pattern extraction is incomplete" | deny-patterns.yaml に足したカテゴリが `CATEGORIES` に未登録。スクリプト側にも追加する |
| `devbox global shellenv` が "environment may be out of date" 警告 | 新規マシンでは `bootstrap.sh` が自動で再生成する。手動変更後は `devbox global shellenv --init-hook -r \| source` で環境を再生成 |
| statusline が空 / 通知が飛ばない（hook のエラー出力は無い） | 参照先が未導入。`run-if-present` が無音でスキップしている。導入すればそのまま有効になる |
| Claude Code の hook のたびに `run-if-present: command not found`（exit 127）が出る / statusline が空 | [確認と復旧手順](#claude-path) |
| `codex` が `exec: process-wrap: not found`（exit 127）で落ちる | process-wrap 未導入。シムは最終行で `exec process-wrap` するだけで本体の不在を自分では見ないので、PATH に無ければここで落ちる。`mise install`（`mise bootstrap` でも可）で `[tools]` の `github:ba0918/process-wrap` を入れる。急ぐときは `PROCESS_WRAP_SHIM_OFF=1 codex ...` で隔離を素通しできる |
| codex の hook のたびに `run-if-present: command not found`（exit 127）が出る | process-wrap のシムは起動したシェルの PATH をそのまま渡すので、そのシェルで `command -v run-if-present` を確認する。無ければ `mise install` で入れ、`config.fish` の `mise activate`（対話シェルは installs ディレクトリ、非対話シェルは `--shims` で shims ディレクトリを PATH に置く）が効いているか確認する。ただし Claude Code の Bash tool と hook は fish を通らないので、そこから起動した `codex` の PATH は `config.fish` ではなく `~/.claude/settings.json` の `env.PATH`（`ai/claude/conf.d/40-env.json` が正本）が決める |

<a id="regular-files"></a>

## 実体配布へ切り替えたファイルの確認

旧方式の symlink が残っていないか、apply 後に確認する。

```bash
for file in ~/.claude/CLAUDE.md ~/.claude/statusline.py ~/.codex/hooks.json; do
  if test -f "$file" && test ! -L "$file"; then
    printf 'OK: %s\n' "$file"
  else
    printf 'CHECK: %s\n' "$file"
  fi
done
```

`-f` だけでは symlink も通るため、`! -L` と併せて確認する。
`CHECK` が出た対象は、次のように対処する。

- symlink が残っている場合: リンクであることを確認してそのリンクだけを削除し、
  `mise bootstrap dotfiles apply` を再実行する。repo 側の実体は削除しない。
- ファイルが不在の場合: apply のエラーを解消してから再実行する。

これらを実体で配るのは、隔離の中からリンクを別ファイルに差し替える経路を塞ぐため。
保護の仕組みは [process-wrap の説明](process-wrap.md)を参照。

<a id="legacy-bash-env"></a>

## 旧 bash-env.sh の撤去

`~/.claude/bash-env.sh` は過去に template で配った通常ファイル。
宣言から外しても自動回収されず、リンク切れの検索にも出ない。

apply 後も残っていれば、他の作業より先に旧ファイルを撤去する。
このファイルは現在の隔離プロファイルの保護対象から外れている。

```bash
rm ~/.claude/bash-env.sh
jq -r '.env.BASH_ENV // "null"' ~/.claude/settings.json
```

`null` なら旧ファイルへの参照もなくなっている。値が残っている場合は、
post-dotfiles hook が失敗して設定更新が完了していない可能性がある。
apply の出力を確認し、失敗を解消してから再適用する。

<a id="claude-path"></a>

## Claude Code から起動するコマンドの PATH

Claude Code の Bash tool と hook は、生成済み settings.json の `env.PATH` を使う。
起動元シェルの PATH だけを直しても、この設定は更新されない。

1. `~/.local/share/mise/shims/run-if-present` の有無を確認する。
   なければ `mise install` で導入する。
2. 配布された PATH を確認する。

   ```bash
   jq -r .env.PATH ~/.claude/settings.json
   ```

3. 先頭4要素が次の順序か、先頭のディレクトリが実在するかを確認する。
   `$HOME` と `$DOTFILES_ROOT` は、出力では絶対パスに展開されている。

   ```text
   $DOTFILES_ROOT/ai/process-wrap/shim
   $HOME/.safe-chain/shims
   $HOME/.local/share/mise/shims
   $HOME/.safe-chain/bin
   ```

4. 不一致・不在があれば、正本の checkout で `ai/claude/build-settings` を実行し直す。
   `mise bootstrap dotfiles apply` でも同じ生成処理が走る。

`build-settings` は順序の不一致を検出すると、書き込まずに失敗する。
ただし、先頭が削除済みの一時 worktree を指す場合など、ディレクトリの実在は別途確認が必要。
そのままでは `codex` が process-wrap の起動シムを飛ばし、隔離なしで動く可能性がある。
生成元の正本は `MISE_GLOBAL_CONFIG_ROOT` が指す checkout。
設定の背景は [process-wrap の説明](process-wrap.md)を参照。
