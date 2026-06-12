return {
  {
    dir = vim.fn.expand("~/md-doc-pipeline/nvim-plugin/"),
    ft = "markdown",
    config = function()
      require("md-doc").setup({
        disable_marksman = true,
      })
    end,
  },
}
