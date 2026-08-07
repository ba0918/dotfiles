-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here.
-- 注意: LazyVim が既定で設定しているもの（number/relativenumber, clipboard,
-- shiftwidth=2, expandtab, smartcase, splitright, undofile, wrap=false 等）は
-- 再設定しない。差分だけを書く。

-- swap ファイル不要（undofile が有効のため）
vim.opt.swapfile = false