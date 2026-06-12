-- lua/config/options.lua
local opt = vim.opt

opt.number = true
opt.relativenumber = true
opt.wrap = false
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.updatetime = 250
opt.timeoutlen = 300
opt.splitbelow = true
opt.splitright = true
opt.ignorecase = true
opt.smartcase = true
opt.cursorline = true
opt.signcolumn = "yes"
opt.termguicolors = true
opt.clipboard = "unnamedplus"
opt.completeopt = "menu,menuone,noselect,popup"
opt.pumheight = 12
opt.undofile = true
opt.confirm = true
opt.smoothscroll = true
opt.expandtab = true
opt.tabstop = 4
opt.softtabstop = 4
opt.shiftwidth = 4
opt.smartindent = true
opt.autoindent = true
opt.shiftround = true
opt.breakindent = true
opt.linebreak = true
opt.formatoptions:remove({ "c", "r", "o" })
