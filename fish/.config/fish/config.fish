# PATH
fish_add_path ~/.bun/bin
fish_add_path ~/.local/bin

# repo 配置を実体パスから導出（repo をどの場所に置いても self-contained）
# config.fish は symlink 経由で読まれるため realpath で実体に解決してから 4 段上る
set -l dotfiles_root (dirname (dirname (dirname (dirname (realpath (status filename))))))

# mise setting
# repo 内の config をグローバル config として使用。
# 新規マシンの初回のみ ./bootstrap.sh が設定する（ここは対話シェル用）。
# MISE_GLOBAL_CONFIG_ROOT は {{ config_root }} を repo ルートへ解決し、
# dotfiles の template レンダリング（opencode.json の instructions）で使われる。
set -gx MISE_GLOBAL_CONFIG_FILE "$dotfiles_root/mise/config.toml"
set -gx MISE_GLOBAL_CONFIG_ROOT "$dotfiles_root"
if status is-interactive
    mise activate fish | source
    # direnv: ディレクトリごとの環境自動切替（.envrc / devbox 連携）
    direnv hook fish | source
else
    mise activate fish --shims | source
end

# Codex jail shim（ai/codex/bin/codex）。対話シェルでは mise/config.toml の
# env._.path が hook-env のたびに shim を tool の bin より前へ置き直すので、
# ここでの prepend は hook-env が走らない非対話シェル（--shims 側）のための保険。
# ここだけに頼ると、hook-env が PATH を組み直した時点で mise 管理の codex 本体に負ける。
fish_add_path --prepend --move "$dotfiles_root/ai/codex/bin"

# devbox global（php / xdebug / pcov のツールチェーン。nix store ベースでホストを汚さない）
# devbox は $SHELL で出力の構文を決めるので、bash などから起動された fish
# （エージェントの Bash ツール、cron、herdr）では bash 構文が流れてきて
# source が構文エラーになる。shell 指定フラグは無いため $SHELL を fish に固定する
SHELL=(status fish-path) devbox global shellenv --init-hook | source

# environment
set -gx EDITOR nvim
set -gx BROWSER powershell.exe
set -gx PAGER 'less -R'
set -gx BAT_THEME OneHalfDark

# fish greeting 抑止（tide がプロンプトを描くため起動挨拶は不要）
set -g fish_greeting

if status is-interactive
    # alias
    alias cat 'batcat --paging=never'
    alias bat batcat
    alias fd fdfind
    # WSL → Windows クリップボード (UTF-8 → UTF-16LE + BOM 変換で文字化け回避)
    alias clip 'iconv -t utf16 | clip.exe'

    # config 再読込（設定変更を即時反映）
    alias reload 'source ~/.config/fish/config.fish'
    # 完全リスタート（環境変数・関数を全部作り直し）
    alias reshell 'exec fish'

    abbr ls 'eza --icons --grid --group-directories-first'
    abbr ll 'eza --icons -m --long --all --git --time-style=long-iso --group-directories-first'
    abbr lt 'eza --icons --tree --level=2'

    # git
    abbr gst 'git status'
    abbr gco 'git checkout'
    abbr gbr 'git branch -vv'
    abbr gl 'git log --oneline --graph --decorate -20'
    abbr gd 'git diff'
    abbr ga 'git add'
    abbr gcm 'git commit -m'
    abbr gp 'git push'
    abbr gpl 'git pull'
    abbr gcb 'git checkout -b'
    abbr gdst 'git diff --stat'
    abbr gpsup 'git push --set-upstream origin HEAD'
    abbr gap 'git add -p'
    abbr gls 'git log --oneline --grep'

    # mise
    abbr mui 'mise up --interactive'

    # AI usage ledger（bunx で実行。たまにしか使わないため install はしない）
    abbr ccul 'bunx ccusage-ledger'

    # fzf default (zoxide の _ZO_FZF_OPTS とは独立)
    set -gx FZF_DEFAULT_OPTS "
        --height 40%
	--layout reverse
	--border
	--info inline
	--preview-window right:60%:border-rounded
    "

    # zoxide setting（共通の高さ・レイアウト・枠は FZF_DEFAULT_OPTS が適用済み）
    set -gx _ZO_FZF_OPTS "
        --no-sort
	--preview 'eza --icons --tree --color=always --level=1 {2..}'
    "
    zoxide init fish | source

    # atuin: fish 履歴を atuin DB に置き換え（Ctrl-R で高速履歴検索）
    atuin init fish | source

end

# for Playwright tests...
export DBUS_SESSION_BUS_ADDRESS=/dev/null
# Safe-chain: 導入済み環境でのみロード（未導入マシンでは無視）
if test -f "$HOME/.safe-chain/scripts/init-fish.fish"
    source "$HOME/.safe-chain/scripts/init-fish.fish"
end
