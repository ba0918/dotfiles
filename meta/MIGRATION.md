# 既存設定の取り込みチートシート

新しいマシンで `mise bootstrap` を走らせる用ではなく、**今このマシンにあるリアル設定を** リポジトリに取り込みたい時の手順。

基本ポリシー:
- `$HOME` 側の実ファイルをリポジトリ側に `mv` してから `[dotfiles]` で symlink し直す
- credentials / session / cache / sqlite は絶対コピーしない（`.gitignore` でブロック済みだが、そもそも移動しない）
- 移動前に `cp -a` でバックアップを取る

## 例: fish config を取り込む

fish は tide/fzf などプラグイン由来のファイルが大量に生成されるため、
**手動管理ファイルだけを取り込む**（ディレクトリ丸ごと symlink にすると
プラグイン生成物が repo に混入する）。

```fish
# バックアップ
cp -a ~/.config/fish ~/.config/fish.bak.(date +%Y%m%d)

# リポジトリ側に移動（手動管理ファイルのみ！ プラグイン生成物は移さない）
mv ~/.config/fish/config.fish                  ~/develop/dotfiles/fish/.config/fish/
mv ~/.config/fish/fish_plugins                 ~/develop/dotfiles/fish/.config/fish/
mv ~/.config/fish/functions/up.fish            ~/develop/dotfiles/fish/.config/fish/functions/
mv ~/.config/fish/conf.d/clipboard2path.fish   ~/develop/dotfiles/fish/.config/fish/conf.d/

# fish は symlink-each + manifest = "git" で配布する。
# 取り込んだファイルだけを index に登録する（未追跡ファイルは配布されない）。
git -C ~/develop/dotfiles add fish/.config/fish/config.fish fish/.config/fish/fish_plugins
git -C ~/develop/dotfiles add fish/.config/fish/functions/up.fish fish/.config/fish/conf.d/clipboard2path.fish
mise bootstrap dotfiles apply --dry-run   # 衝突確認
mise bootstrap dotfiles apply             # 適用（実ファイルは移動済みなので置換不要）
```

## z から zoxide への統一

`fish_plugins` から `jethrokuan/z` を外しても、既存環境のプラグインは残る。
旧 z が読み込まれている fish で、履歴を統合してから削除する。
履歴の保存先を変更している場合、バックアップ先の指定も合わせる。

```fish
cp -a ~/.local/share/zoxide ~/.local/share/zoxide.bak.(date +%Y%m%d%H%M%S)
env _Z_DATA="$Z_DATA" zoxide import --merge z
```

取り込みが成功したら、次を実行する。旧 z の履歴ファイルは削除しない。

```fish
fisher remove jethrokuan/z
exec fish
```

zoxide の import は既定で `~/.z` を読むため、fish プラグインの履歴パスを
`_Z_DATA` に明示する（[実装](https://github.com/ajeetdsouza/zoxide/blob/main/src/import/z.rs)）。
再起動後は `z` / `zi` で移動できることを確認する。
旧 z の `zo` や固有オプションは引き継がれない。

## 例: Claude Code の設定を取り込む

`~/.claude/` は secret と runtime artifact が混在してるので、**取り込む対象を厳選**する:

`~/.claude/settings.json` は生成物なので、そのまま取り込まない。
残したい設定だけを `ai/claude/conf.d/` の対応するファイルへ移す。
対話中に追加された allow/ask は通常の build で保持される。
設定の分類は [LLM 設定の管理](LLM-SETTINGS.md)を参照。

取り込んでOK:
- `~/.claude/CLAUDE.md`
- `~/.claude/keybindings.json`
- `~/.claude/commands/`
- `~/.claude/hooks/`（ただし secret が埋め込まれてないか確認）
- `~/.claude/skills/`
- `~/.claude/rules/`
- `~/.claude/output-styles/`（ローカル style がある場合。ただし repo の受け皿は
  `ai/shared/persona/gal.md`（output-styles/gal.md の symlink 実体）のみ。追加の
  style を取り込む場合は `ai/shared/persona/` 等に置いて symlink を張る）

絶対取り込まない:
- `~/.claude/.credentials.json`
- `~/.claude/auth.json`（存在するなら）
- `~/.claude/history.jsonl`
- `~/.claude/sessions/`
- `~/.claude/file-history/`
- `~/.claude/shell_snapshots/`
- `~/.claude/logs_*.sqlite*`
- `~/.claude/state_*.sqlite*`
- `~/.claude/cache/`
- `~/.claude.json`（MCP トークンとかガッツリ入ってる）

## 衝突したら

`mise bootstrap dotfiles apply` は既存の実ファイルがある場所には symlink を張らない（安全）。
衝突したら:

```bash
mise bootstrap dotfiles status            # まず何が衝突してるか確認 (differs)
mv ~/.conflicting-file dotfiles/<package>/path/to/file  # 取り込み
mise bootstrap dotfiles apply --dry-run   # 再チャレンジ（先に dry-run）
mise bootstrap dotfiles apply --force     # 置換が必要なときだけ明示的に
```

注意: ディレクトリが既に symlink の場合、file-level の宣言を追加すると repo 内ファイルが
symlink 化される事故がある。ディレクトリ単位で宣言すること（secretlint の例）。

## 空の Neovim keymaps.lua の撤去

初期案内コメントだけだった `lua/config/keymaps.lua` は配布対象から外した。
LazyVim はこのファイルがなくても既定のキーマップを読み込む。

`symlink-each` で記録済みのリンクは次回 apply で回収される。
旧方式の個別リンクを配った後、一度も `symlink-each` を適用していないマシンでは
未管理のリンクとして残る場合がある。次で確認する。

```bash
readlink ~/.config/nvim/lua/config/keymaps.lua
```

削除した repo 内の `nvim/.config/nvim/lua/config/keymaps.lua` を指すリンクなら、
`unlink ~/.config/nvim/lua/config/keymaps.lua` でリンクだけを撤去する。
通常ファイルや別の参照先なら、独自設定の可能性があるので残す。
