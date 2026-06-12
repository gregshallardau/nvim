-- init.lua
-- Minimal entrypoint for a clean LazyVim-based config.
vim.loader.enable()
vim.g.lazyvim_php_lsp = "intelephense"
require("config.lazy")
require("config.lsp")
