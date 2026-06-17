return {
  "kylechui/nvim-surround",
  version = "*",
  event = "VeryLazy",
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
