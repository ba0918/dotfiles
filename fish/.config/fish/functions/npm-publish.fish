function npm-publish --description 'npm publish with the token from ~/.config/npm/publish-token'
    # ~/.npmrc は repo の npm/.npmrc へのリンクなので、npm login で書かせると
    # トークンが repo の作業ツリーに残る。~/.npmrc は ${NPM_TOKEN?} を参照するだけにして、
    # トークンはこのファイルからこの 1 回の実行にだけ渡す
    set -l token_file ~/.config/npm/publish-token
    if not test -s $token_file
        echo "npm-publish: $token_file not found or empty" >&2
        return 1
    end
    NPM_TOKEN=(string trim < $token_file) npm publish $argv
end
