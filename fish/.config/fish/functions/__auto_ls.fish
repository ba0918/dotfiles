function __auto_ls --on-variable PWD
    if status --is-interactive
        eza --icons --grid --group-directories-first
    end
end
