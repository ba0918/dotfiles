function gr
    set -l ghq_root (ghq root)
    ghq list | fzf --preview "eza --tree --icons --color=always --level=1 $ghq_root/{}" | read -l repo
    if test -n "$repo"
        cd "$ghq_root/$repo"
    end
end
