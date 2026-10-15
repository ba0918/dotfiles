-- 保存時: 末尾空白の除去（markdown の意味のある空白行は preserve）
local save_group = vim.api.nvim_create_augroup("lazyvim_save", { clear = true })
vim.api.nvim_create_autocmd("BufWritePre", {
  group = save_group,
  callback = function()
    local preserve = vim.bo.filetype == "markdown" or vim.bo.filetype == "text"
    if not preserve then
      local win = vim.fn.winsaveview()
      vim.cmd([[keeppatterns %s/\s\+$//e]])
      vim.fn.winrestview(win)
    end
  end,
})
