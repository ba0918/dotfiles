# 既存設定の取り込みチートシート

新しいマシンで `install.sh` を走らせる用ではなく、**今このマシンにあるリアル設定を** リポジトリに取り込みたい時の手順。

基本ポリシー:
- `$HOME` 側の実ファイルをリポジトリ側に `mv` してから `stow` で symlink し直す
- credentials / session / cache / sqlite は絶対コピーしない（`.gitignore` でブロック済みだが、そもそも移動しない）
- 移動前に `cp -a` でバックアップを取る

## 例: fish config を取り込む

```fish
# バックアップ
cp -a ~/.config/fish ~/.config/fish.bak.(date +%Y%m%d)

# リポジトリ側に移動（取り込みたいファイルだけ！ history は不要）
mv ~/.config/fish/config.fish    ~/develop/dotfiles/fish/.config/fish/
mv ~/.config/fish/functions      ~/develop/dotfiles/fish/.config/fish/
mv ~/.config/fish/conf.d         ~/develop/dotfiles/fish/.config/fish/

# stow で symlink に置き換え
cd ~/develop/dotfiles
./install.sh fish
```

## 例: Claude Code の設定を取り込む

`~/.claude/` は secret と runtime artifact が混在してるので、**取り込む対象を厳選**する:

取り込んでOK:
- `~/.claude/CLAUDE.md`
- `~/.claude/settings.json`（secret を含まない方）
- `~/.claude/keybindings.json`
- `~/.claude/output-styles/`
- `~/.claude/commands/`
- `~/.claude/hooks/`（ただし secret が埋め込まれてないか確認）
- `~/.claude/skills/`
- `~/.claude/rules/`

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

`stow` は既存の実ファイルがある場所には symlink を張らない（安全）。
衝突したら:

```bash
./install.sh --dry-run  # まず何が衝突してるか確認
mv ~/.conflicting-file dotfiles/<package>/path/to/file  # 取り込み
./install.sh            # 再チャレンジ
```
