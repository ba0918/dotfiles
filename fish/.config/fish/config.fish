# PATH
fish_add_path ~/.bun/bin
fish_add_path ~/.local/bin

if status is-interactive
    # alias
    alias cat 'batcat --paging=never'
    alias bat batcat
    alias fd fdfind
    alias clip 'powershell.exe -noprofile -command "Set-Clipboard"'

    abbr ls 'eza --icons --grid --group-directories-first'
    abbr ll 'eza --icons -m --long --all --git --time-style=long-iso --group-directories-first'
    abbr lt 'eza --icons --tree --level=2'

    # auto ls
    function __auto_ls --on-variable PWD
        if status --is-interactive
            eza --icons --grid --group-directories-first
        end
    end

    #
    function fe
        fzf --preview '
	    if test -d {}
	        eza --tree --icons --color=always --level=2 {}
            else
	        batcat --color=always --style=numbers {} 2>/dev/null; or cat {}
            end
	'
    end

    # zoxide setting
    set -gx _ZO_FZF_OPTS "
        --no-sort
	--height 40%
	--layout reverse
	--border
	--preview 'eza --icons --tree --color=always --level=1 {2..}'
    "
    zoxide init fish | source

end

# mise setting
# repo 内の config をグローバル config として使用。
# 新規マシンの初回のみ ./bootstrap.sh が設定する（ここは対話シェル用）。
set -gx MISE_GLOBAL_CONFIG_FILE ~/develop/dotfiles/mise/config.toml
if status is-interactive
    mise activate fish | source
else
    mise activate fish --shims | source
end

# for Playwright tests...
export DBUS_SESSION_BUS_ADDRESS=/dev/null

# opencode
fish_add_path /home/mizumi/.opencode/bin
