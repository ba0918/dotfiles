# 既存設定の取り込みチートシート

新しいマシンで `mise bootstrap` を走らせる用ではなく、**今このマシンにあるリアル設定を** リポジトリに取り込みたい時の手順。

基本ポリシー:
- `$HOME` 側の実ファイルをリポジトリ側に `mv` してから `[dotfiles]` で symlink し直す
- credentials / session / cache / sqlite は絶対コピーしない（`.gitignore` でブロック済みだが、そもそも移動しない）
- 移動前に `cp -a` でバックアップを取る

## 例: fish config を取り込む

fish は tide/fzf/z などプラグイン由来のファイルが大量に生成されるため、
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
