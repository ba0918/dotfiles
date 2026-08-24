function gc
    set -l ghq_root (ghq root)
    if test -z "$ghq_root"; or not test -d "$ghq_root"
        echo "ghq root not found" >&2
        return 1
    end

    set -l preview_cmd "
        set -l dir $ghq_root/{};
        echo '--- Remote ---';
        git -C \$dir remote get-url origin 2>/dev/null; or echo '(no remote)';
        echo;
        echo '--- Last Commit ---';
        git -C \$dir log -1 --format='%cd (%cr)' --date=short 2>/dev/null; or echo '(no commits)';
        echo;
        echo '--- Disk Usage ---';
        du -sh \$dir 2>/dev/null;
        echo;
        echo '--- Dirty ---';
        set -l dirty (git -C \$dir status --porcelain 2>/dev/null);
        if test -n \"\$dirty\";
            echo 'YES — uncommitted changes:';
            echo \$dirty | head -10;
        else;
            echo 'clean';
        end;
        echo;
        echo '--- Unpushed ---';
        set -l unpushed (git -C \$dir log --branches --not --remotes --oneline 2>/dev/null);
        if test -n \"\$unpushed\";
            echo 'YES — unpushed commits:';
            echo \$unpushed | head -5;
        else;
            echo 'none';
        end
    "

    set -l repos (ghq list | fzf --multi --header "TAB: select / ENTER: confirm" --preview "$preview_cmd")
    if test (count $repos) -eq 0
        return 0
    end

    echo ""
    echo "Delete the following repositories:"
    echo ""

    set -l has_warning false
    for repo in $repos
        set -l dir "$ghq_root/$repo"
        if not test -d "$dir"
            continue
        end

        set -l dirty (git -C "$dir" status --porcelain 2>/dev/null)
        set -l unpushed (git -C "$dir" log --branches --not --remotes --oneline 2>/dev/null)

        if test -n "$dirty"; or test -n "$unpushed"
            set has_warning true
            echo "  ⚠ $repo"
            test -n "$dirty"; and echo "      uncommitted changes"
            test -n "$unpushed"; and echo "      unpushed commits"
        else
            echo "  $repo"
        end
    end

    echo ""
    if test "$has_warning" = true
        echo "WARNING: some repositories have uncommitted changes or unpushed commits."
    end

    read -l -P "Proceed? [y/N] " confirm
    if test "$confirm" != y; and test "$confirm" != Y
        echo "Cancelled."
        return 0
    end

    for repo in $repos
        set -l dir "$ghq_root/$repo"
        if test -n "$repo"; and test -d "$dir"
            rm -rf "$dir"
            echo "Deleted: $repo"
        end
    end
end
