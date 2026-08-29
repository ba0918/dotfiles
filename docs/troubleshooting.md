# トラブルシューティング

| 症状 | 原因と対処 |
|------|-----------|
| `mise bootstrap dotfiles apply` で "refusing to overwrite existing files" | `$HOME` 側に実ファイルがある。内容を確認して `--force` で置換するか退避する |
| `git` 実行時に `delta: command not found` | delta 未導入。`mise bootstrap` で入れるか一時的に `git -c core.pager=less ...` で回避 |
| `git commit` が `[pre-commit] secretlint is not installed` で拒否される | `git/.config/secretlint/node_modules` が無い。`mise run bootstrap`（または `npm ci --prefix ~/.config/secretlint`）で入れる |
| `~/.gitconfig` に突然大量の差分 | `gcm configure` などツールが symlink 先に書き込んだ可能性。差分を確認して整理する |
| dotfiles apply で repo 内ファイルが symlink 化する | `[dotfiles]` がディレクトリ symlink を指す場合に起きる。file-level 宣言でなくディレクトリ単位で宣言する |
| Windows 側でコピーしたファイルに `:Zone.Identifier` が付く | global ignore（`~/.config/git/ignore`）で除外済み |
| `clipboard2path-wsl` が起動しない / `command not found` | aqua カスタムレジストリは `mise/config.toml` の `[settings] aqua.registries` で設定済み。導入は `mise bootstrap`、手動再起動は `systemctl --user restart clipboard2path` |
| `mise x clipboard2path-wsl` で "not found in tool registry" | ショート名解決が効かない。`aqua:ba0918/clipboard2path-wsl` のフル名を指定する。shim 経由では問題ない |
| `herdr/.config/herdr/config.toml` に意図しない差分 | herdr が実行時に config.toml を書き戻す（write-through）。差分を確認して整理する |
| herdr plugin の keybinding が効かない | プラグイン未導入。`herdr plugin install smarzban/herdr-file-viewer` で再現する |
| codex の security hook が効かない | フック未 trust の可能性。`codex /hooks` で trust する。または symlink が未適用（`mise bootstrap dotfiles status` で確認） |
| `~/.codex/hooks` の apply が "refusing to overwrite" | 旧方式のディレクトリ symlink が残っている。`rm ~/.codex/hooks`（symlink 自体を消す）してから `mise bootstrap dotfiles apply` でファイル単位に張り直す |
| hook が `ModuleNotFoundError: hook_input` で落ちる | 配布先ディレクトリに `hook_input.py` が無い。`mise bootstrap dotfiles status` で確認 |
| `generate-deny.sh` が "deny pattern extraction is incomplete" | deny-patterns.yaml に足したカテゴリが `ALL_CATEGORIES` に未登録。スクリプト側にも追加する |
| `devbox global shellenv` が "environment may be out of date" 警告 | 新規マシンでは `bootstrap.sh` が自動で再生成する。手動変更後は `devbox global shellenv --init-hook -r \| source` で環境を再生成 |
| statusline が空 / 通知が飛ばない | 参照先が未導入。`run-optional.sh` が無音でスキップしている。導入すればそのまま有効になる |
