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
        -- Disable markdown: prettier reformats table separators (|---|---|
        -- becomes |-----------|) which breaks md-doc's [[field]] table rows.
        markdown = {},
      },
    },
  },
}
