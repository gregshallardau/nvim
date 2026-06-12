-- lua/config/autocmds.lua
local augroup = vim.api.nvim_create_augroup("greg_clean_config", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
  group = augroup,
  pattern = { "php", "blade", "phtml" },
  callback = function()
    vim.opt_local.expandtab = true
    vim.opt_local.tabstop = 4
    vim.opt_local.softtabstop = 4
    vim.opt_local.shiftwidth = 4
    vim.opt_local.smartindent = true
    vim.opt_local.autoindent = true
    vim.opt_local.cindent = false
    vim.opt_local.indentexpr = ""
    vim.opt_local.formatoptions:remove({ "c", "r", "o" })
  end,
})

vim.api.nvim_create_autocmd("TextYankPost", {
  group = augroup,
  callback = function()
    vim.highlight.on_yank()
  end,
})
