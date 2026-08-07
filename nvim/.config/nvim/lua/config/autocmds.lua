-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- IME (WSL2 + Google 日本語入力): 挿入モード切替時に im-select.exe で入力切替
-- ノーマルモードで日本語入力が残る事故を防ぐ
local function set_ime(mode)
  if vim.fn.executable("im-select.exe") == 1 then
    vim.fn.system({ "im-select.exe", mode })
  end
end

vim.api.nvim_create_autocmd("InsertEnter", {
  callback = function()
    set_ime("1041")
  end,
})

vim.api.nvim_create_autocmd({ "InsertLeave", "CmdlineLeave" }, {
  callback = function()
    set_ime("1033")
  end,
})

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