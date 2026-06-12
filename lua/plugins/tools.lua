-- lua/plugins/tools.lua
return {
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      -- LazyVim's markdown extra adds marksman; the md-doc plugin handles
      -- Markdown LSP differently so we don't want it auto-installed.
      opts.ensure_installed = vim.tbl_filter(function(v)
        return v ~= "marksman"
      end, opts.ensure_installed)
      vim.list_extend(opts.ensure_installed, {
        "blade-formatter",
        "intelephense",
        "jq",
        "lua-language-server",
        "pint",
        "pyright",
        "ruff",
        "shfmt",
        "stylua",
        "yaml-language-server",
        "yamlfmt",
      })
    end,
  },
  {
    "mason-org/mason-lspconfig.nvim",
    opts = {
      -- Don't auto-call vim.lsp.enable() for every installed server.
      -- Servers are enabled explicitly (intelephense via lsp.lua FileType
      -- autocmd; others via LazyVim extras).
      automatic_enable = false,
    },
  },
}
