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
