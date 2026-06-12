-- Servers that LazyVim's PHP extra would start but we don't want.
-- Setting false here prevents lspconfig from registering the FileType
-- autocmd that would launch them.
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        laravel_ls = false,
        phpactor   = false,
      },
    },
  },
}
