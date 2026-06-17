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
      },
    })
  end,
}
