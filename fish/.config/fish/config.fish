# PATH
fish_add_path ~/.bun/bin
fish_add_path ~/.local/bin

# repo 配置を実体パスから導出（repo をどの場所に置いても self-contained）
# config.fish は symlink 経由で読まれるため realpath で実体に解決してから 4 段上る
set -l dotfiles_root (dirname (dirname (dirname (dirname (realpath (status filename))))))

# mise setting
# repo 内の config をグローバル config として使用。
# 新規マシンの初回のみ ./bootstrap.sh が設定する（ここは対話シェル用）。
set -gx MISE_GLOBAL_CONFIG_FILE "$dotfiles_root/mise/config.toml"
if status is-interactive
    mise activate fish | source
else
    mise activate fish --shims | source
end

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

    # __auto_ls: cd / ディレクトリ移動時に eza で自動表示
    function __auto_ls --on-variable PWD
        if status --is-interactive
            eza --icons --grid --group-directories-first
        end
    end

    # fe: fzf でファイル/ディレクトリを選択し、プレビュー表示
    function fe
        fzf --preview '
	    if test -d {}
	        eza --tree --icons --color=always --level=2 {}
            else
	        batcat --color=always --style=numbers {} 2>/dev/null; or cat {}
            end
	'
    end

    # ghq リポジトリ一覧から fzf で選択して移動
    function gr
        set -l ghq_root (ghq root)
        ghq list | fzf --preview "eza --tree --icons --color=always --level=1 $ghq_root/{}" | read -l repo
        if test -n "$repo"
            cd "$ghq_root/$repo"
        end
    end

    # git worktree 一覧から fzf で選択して移動
    function gwt
        git worktree list --porcelain | sed -n 's/^worktree //p' | fzf --preview '
	if test -d {}
	    eza --tree --icons --color=always --level=1 {}
	end
' | read -l wt
        if test -n "$wt"
            cd "$wt"
        end
    end

    # ya: yazi で操作し、終了時は最後にいたディレクトリへ cd する
    function ya
        set -l tmp (mktemp -t "yazi-cwd.XXXXXX")
        yazi "$argv" --cwd-file "$tmp"
        set -l cwd (command cat -- "$tmp")
        if test -n "$cwd"; and test -d "$cwd"
            cd -- "$cwd"
        end
        rm -f -- "$tmp"
    end

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

end

# for Playwright tests...
export DBUS_SESSION_BUS_ADDRESS=/dev/null
