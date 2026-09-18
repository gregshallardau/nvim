return {
  {
    dir = vim.fn.stdpath("config"),
    name = "project-intel",
    lazy = false,
    config = function()
      require("project-intel").setup()
    end,
  },
}
