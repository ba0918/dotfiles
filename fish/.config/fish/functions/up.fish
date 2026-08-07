function up
    # 現在ディレクトリからルートまでのパスを取得し、1行ずつ出力
    set -l target (string split -r -m 1 / $PWD)[1]

    # 親ディレクトリを順にリスト化して fzf に渡す
    set -l destination (begin
    while test "$target" != ""
      echo "$target"
      set target (string split -r -m 1 / $target)[1]
    end
    echo "/"
  end | fzf --height 40% --reverse --prompt="Jump to parent > ")

    # 選択されたら移動
    if test -n "$destination"
        cd "$destination"
    end
end
