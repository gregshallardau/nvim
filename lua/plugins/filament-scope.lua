return {
  {
    dir = vim.fn.stdpath("config"),
    name = "filament-scope",
    lazy = false,
    config = function()
      require("filament-scope").setup()
    end,
  },
}
