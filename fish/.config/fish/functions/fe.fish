function fe
    fzf --preview '
	if test -d {}
	    eza --tree --icons --color=always --level=2 {}
	else
	    batcat --color=always --style=numbers {} 2>/dev/null; or cat {}
	end
'
end
