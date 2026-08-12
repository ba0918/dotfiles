function ya
    set -l tmp (mktemp -t "yazi-cwd.XXXXXX")
    yazi "$argv" --cwd-file "$tmp"
    set -l cwd (command cat -- "$tmp")
    if test -n "$cwd"; and test -d "$cwd"
        cd -- "$cwd"
    end
    rm -f -- "$tmp"
end
