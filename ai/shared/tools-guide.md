# Development tools

This environment offers the following CLIs for code work.

* `rg` — text search
* `fdfind` — file discovery (the name `fd` runs under on Debian / Ubuntu)
* `jq` — JSON search and transformation
* `sg` (`ast-grep`) — code search and rewriting based on AST structure
* `tu` — some programs, such as htop, vim, mc, dialog-based installers, and ncurses-based UIs, need a real terminal to draw their interface. Piping stdin/stdout alone does not work.

  With `tu`, you can run those programs on a virtual terminal and take screenshots, send key input, and operate the mouse. Run `tu usage` before the first operation to see the full command reference.

Prefer `rg` for simple text search and `fdfind` for file discovery.

To search or change code by syntactic structure, use `sg`.
If usage or options are unclear, see each command's `--help`.
