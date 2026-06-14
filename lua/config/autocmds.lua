-- lua/config/autocmds.lua
local augroup = vim.api.nvim_create_augroup("greg_clean_config", { clear = true })

-- Log all notifications to ~/.local/state/nvim/notify.log
do
  local log_path = vim.fn.stdpath("log") .. "/notify.log"
  local original_notify = vim.notify
  local levels = { [0] = "TRACE", "DEBUG", "INFO", "WARN", "ERROR" }
  vim.notify = function(msg, level, opts)
    local ok, f = pcall(io.open, log_path, "a")
    if ok and f then
      local ts = os.date("%Y-%m-%d %H:%M:%S")
      local lvl = levels[level or vim.log.levels.INFO] or "INFO"
      f:write(string.format("[%s] [%s] %s\n", ts, lvl, tostring(msg)))
      f:close()
    end
    return original_notify(msg, level, opts)
  end
end

vim.api.nvim_create_autocmd("FileType", {
  group = augroup,
  pattern = { "php", "blade", "phtml" },
  callback = function()
    vim.opt_local.expandtab = true
    vim.opt_local.tabstop = 4
    vim.opt_local.softtabstop = 4
    vim.opt_local.shiftwidth = 4
    vim.opt_local.smartindent = true
    vim.opt_local.autoindent = true
    vim.opt_local.cindent = false
    vim.opt_local.indentexpr = ""
    vim.opt_local.formatoptions:remove({ "c", "r", "o" })
  end,
})

vim.api.nvim_create_autocmd("TextYankPost", {
  group = augroup,
  callback = function()
    vim.highlight.on_yank()
  end,
})
