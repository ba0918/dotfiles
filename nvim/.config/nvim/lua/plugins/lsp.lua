-- LSP サーバーの追加（extras に含まれない言語）
-- extras で導入されるサーバーは lazyvim.plugins.extras.lang.* が ensure_installed に追加する。
-- ここでは extras が存在しない言語（Lua / Shell / HTML / CSS）のサーバーを Mason に自動導入させる。
-- 注: ensure_installed は mason.nvim のパッケージ名（lspconfig のサーバー名ではない）を指定する
return {
  {
    "mason-org/mason.nvim",
    opts_extend = { "ensure_installed" },
    opts = {
      ensure_installed = {
        "bash-language-server",
        "css-lsp",
        "html-lsp",
        "lua-language-server",
      },
    },
  },
}
