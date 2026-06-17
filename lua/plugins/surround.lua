return {
  "kylechui/nvim-surround",
  version = "*",
  event = "VeryLazy",
  keys = {
    { "ys",  "<Plug>(nvim-surround-normal)",      desc = "Surround" },
    { "yss", "<Plug>(nvim-surround-normal-line)",  desc = "Surround line" },
    { "gS",  "<Plug>(nvim-surround-visual)",       mode = "x", desc = "Surround visual" },
    { "ds",  "<Plug>(nvim-surround-delete)",       desc = "Delete surround" },
    { "cs",  "<Plug>(nvim-surround-change)",       desc = "Change surround" },
  },
  config = function()
    require("nvim-surround").setup({
      surrounds = {
        -- * = markdown bold: **text**
        ["*"] = {
          add = { "**", "**" },
          find = "%*%*.-[^%*]%*%*",
          delete = "^(%*%*)().-([^%*]%*%*)()$",
        },
        -- _ = markdown italic: _text_
        ["_"] = {
          add = { "_", "_" },
          find = "_.-_",
          delete = "^(_)().-(_)()$",
        },
      },
    })
  end,
}
