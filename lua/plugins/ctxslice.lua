-- Local module registration for greg/ctxslice — deterministic context
-- distillation for LLM code review. Loaded eagerly (like filament-scope) so its
-- keymaps and :CtxSlice / :FilamentSlice commands are available immediately.
return {
  {
    dir = vim.fn.stdpath("config"),
    name = "ctxslice",
    lazy = false,
    config = function()
      require("greg.ctxslice").setup()
    end,
  },
}
