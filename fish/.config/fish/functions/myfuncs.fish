function myfuncs
    # List dotfiles-managed functions from the repo functions directory
    set -l repo_funcs (path dirname (path resolve (status filename)))
    if test -d "$repo_funcs"
        path basename -E "$repo_funcs"/*.fish
    end
end
