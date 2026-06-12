-- lua/plugins/formatting.lua
return {
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        php = { "pint" },
        blade = { "blade-formatter" },
        lua = { "stylua" },
        sh = { "shfmt" },
        python = { "ruff_format" },
        json = { "jq" },
        yaml = { "yamlfmt" },
      },
    },
  },
}
