-- Minimal Neovim init for headless test runs.
-- Adds the nvim config lua dir to runtimepath so require() works.
vim.opt.runtimepath:append(vim.fn.stdpath("config"))
vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/lazy/plenary.nvim")
