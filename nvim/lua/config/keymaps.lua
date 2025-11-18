-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local map = vim.keymap.set

-- Window navigation with Ctrl + arrow keys
map("n", "<C-Left>", "<C-w>h", { desc = "Go to left window" })
map("n", "<C-Down>", "<C-w>j", { desc = "Go to lower window" })
map("n", "<C-Up>", "<C-w>k", { desc = "Go to upper window" })
map("n", "<C-Right>", "<C-w>l", { desc = "Go to right window" })

-- Buffer management
map("n", "zz", "<cmd>bp<bar>sp<bar>bn<bar>bd<CR>", { desc = "Close buffer without closing window" })

-- Perl: Format with perltidy on F9
map("n", "<F9>", function()
  if vim.bo.filetype == "perl" then
    local line = vim.fn.line(".")
    vim.cmd("%!perltidy")
    vim.fn.cursor(line, 0)
  end
end, { desc = "Format Perl with perltidy" })
