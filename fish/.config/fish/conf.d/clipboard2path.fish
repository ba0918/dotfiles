function __clipboard2path_paste
    set -l latest_path "$XDG_RUNTIME_DIR/clipboard2path/latest-path"
    if test -f "$latest_path"
        set -l path (string trim -- (cat "$latest_path"))
        if test -n "$path"
            commandline -i -- $path
            return
        end
    end
    commandline -i -- (wl-paste -n 2>/dev/null)
end

bind \ev '__clipboard2path_paste'
bind -M insert \ev '__clipboard2path_paste'
