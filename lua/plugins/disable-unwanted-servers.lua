-- Servers that LazyVim's PHP extra would start but we don't want.
-- Setting false here prevents lspconfig from registering the FileType
-- autocmd that would launch them.
-- marksman is disabled globally: md-doc uses [[field]] syntax that marksman
-- misreads as wiki-links, causing false "Link to non-existent document" errors.
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        laravel_ls = false,
        phpactor   = false,
        marksman   = false,
      },
    },
  },
}
