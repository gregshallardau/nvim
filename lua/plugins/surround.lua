return {
  "kylechui/nvim-surround",
  version = "*",
  event = "VeryLazy",
  config = function()
    require("nvim-surround").setup({
      surrounds = {
        -- b = markdown bold: **text**
        ["b"] = {
          add = { "**", "**" },
          find = "%*%*.-[^%*]%*%*",
          delete = "^(%*%*)().-([^%*]%*%*)()$",
        },
      },
    })
  end,
}
