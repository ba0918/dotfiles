-- UI のカスタマイズ
-- LazyVim デフォルトの lualine は mode / branch / diff(git) / diagnostics / location を表示済み。
-- ここではデフォルトに無い「文字数(words)」を lualine_y に追加する。
return {
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      local function words()
        local bufnr = vim.api.nvim_get_current_buf()
        if not vim.api.nvim_buf_is_loaded(bufnr) then
          return ""
        end
        local words = vim.fn.wordcount()
        return vim.bo.buftype == "" and ("%d 語"):format(words.words or 0) or ""
      end
      -- lualine_y の末尾に words を追加（既存の progress / location を保持）
      opts.sections = opts.sections or {}
      opts.sections.lualine_y = opts.sections.lualine_y or {}
      vim.list_extend(opts.sections.lualine_y, { { words, padding = { left = 1, right = 0 } } })
    end,
  },
}
