-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

local opt = vim.opt

-- Better editor experience
opt.relativenumber = true -- Relative line numbers
opt.scrolloff = 8 -- Keep 8 lines above/below cursor
opt.sidescrolloff = 8 -- Keep 8 columns left/right of cursor
opt.wrap = false -- No line wrap by default
opt.cursorline = true -- Highlight current line
opt.colorcolumn = "80,120" -- Show column guides

-- Better search
opt.ignorecase = true -- Ignore case in search
opt.smartcase = true -- Unless uppercase is used

-- Better editing
opt.undofile = true -- Persistent undo
opt.undolevels = 10000
opt.updatetime = 200 -- Faster completion
opt.timeoutlen = 300 -- Faster key sequence completion

-- Better splits
opt.splitright = true -- Put new windows right of current
opt.splitbelow = true -- Put new windows below current

-- Better clipboard
opt.clipboard = "unnamedplus" -- Sync with system clipboard
