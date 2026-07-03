-- greg/ctxslice.lua — thin editor layer over the ctxslice engine.
--
-- The engine (bin/ctxslice.sh, bin/filament-slice.sh, bin/*.php) does all the
-- deterministic retrieval on the CPU. This module only:
--   * picks the symbol (<cword> or a visual/command argument),
--   * finds the project root,
--   * runs the engine async via vim.system so the ctags/index pass never
--     freezes the editor,
--   * forks the result to one of two consumers:
--       buffer    → a scratch markdown window, review inside nvim   (<leader>cr, <leader>cf)
--       clipboard → the + register, paste into ChatGPT/Copilot      (<leader>cc)
--
-- Kept a LOCAL module on purpose. Extract to ctxslice.nvim only once it earns
-- config-driven-per-project surface (see docs/superpowers/specs).

local M = {}

local config = {
  -- Directory holding the engine CLIs. Defaults to <config>/bin.
  bin_dir = vim.fn.stdpath("config") .. "/bin",
  -- Root markers, nearest wins (walked upward from the current file).
  root_markers = { "artisan", "composer.json", ".git" },
  keymaps = {
    slice_buffer    = "<leader>cr", -- function slice → scratch buffer
    slice_clipboard = "<leader>cc", -- function slice → + register
    filament_buffer = "<leader>cf", -- filament structural slice → scratch buffer
  },
}

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

local function notify(msg, level)
  vim.notify("ctxslice: " .. msg, level or vim.log.levels.INFO)
end

-- Nearest ancestor directory containing a root marker; falls back to cwd.
local function project_root()
  local file = vim.api.nvim_buf_get_name(0)
  local start = file ~= "" and vim.fn.fnamemodify(file, ":p:h") or vim.uv.cwd()
  local found = vim.fs.find(config.root_markers, { path = start, upward = true })
  if found and #found > 0 then
    return vim.fn.fnamemodify(found[1], ":h")
  end
  return vim.uv.cwd()
end

-- Open the slice text in a scratch, markdown-filetype window (reused if present).
local function show_in_buffer(text, title)
  local lines = vim.split(text, "\n", { trimempty = false })
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  pcall(vim.api.nvim_buf_set_name, buf, title)

  -- Open in a right-hand vertical split so the source stays visible.
  vim.cmd("vsplit")
  vim.api.nvim_win_set_buf(0, buf)
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true, desc = "Close slice" })
end

-- Run one engine script async and route stdout to `dest`.
--   script  : absolute path to a *.sh engine entry point
--   target  : the SYMBOL / class / file argument
--   dest    : "buffer" | "clipboard"
--   title   : buffer name / notification label
local function run(script, target, dest, title)
  if vim.fn.executable("bash") == 0 then
    notify("bash not found on PATH", vim.log.levels.ERROR)
    return
  end
  if vim.fn.filereadable(script) == 0 then
    notify("engine script missing: " .. script, vim.log.levels.ERROR)
    return
  end

  local root = project_root()
  local cmd = { "bash", script, target, "--root", root }
  notify("slicing `" .. target .. "` …")

  vim.system(cmd, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        local err = (res.stderr or ""):gsub("%s+$", "")
        notify("failed: " .. (err ~= "" and err or ("exit " .. res.code)), vim.log.levels.ERROR)
        return
      end
      local out = res.stdout or ""
      if out:gsub("%s+", "") == "" then
        notify("empty slice for `" .. target .. "` (try :checkhealth greg.ctxslice)", vim.log.levels.WARN)
        return
      end
      if dest == "clipboard" then
        vim.fn.setreg("+", out)
        local kb = math.floor(#out / 1024 + 0.5)
        notify(("copied slice for `%s` to clipboard (~%dKB)"):format(target, kb))
      else
        show_in_buffer(out, title or ("ctxslice: " .. target))
      end
    end)
  end)
end

-- Resolve the target symbol: explicit arg wins, else the word under the cursor.
local function resolve_target(arg)
  if arg and arg ~= "" then
    return arg
  end
  local cword = vim.fn.expand("<cword>")
  if cword == "" then
    notify("no symbol: place the cursor on one or pass an argument", vim.log.levels.WARN)
    return nil
  end
  return cword
end

-- ---------------------------------------------------------------------------
-- public API (also the command/keymap handlers)
-- ---------------------------------------------------------------------------

--- Function (call-graph) slice → scratch buffer.
function M.slice_buffer(arg)
  local t = resolve_target(arg)
  if t then run(config.bin_dir .. "/ctxslice.sh", t, "buffer", "ctxslice: " .. t) end
end

--- Function (call-graph) slice → clipboard.
function M.slice_clipboard(arg)
  local t = resolve_target(arg)
  if t then run(config.bin_dir .. "/ctxslice.sh", t, "clipboard") end
end

--- Filament (structural) slice → scratch buffer.
function M.filament_buffer(arg)
  -- Default the Filament target to the current file when no arg is given, since
  -- Resources are usually sliced while the file is open.
  local t = arg
  if not t or t == "" then
    local file = vim.api.nvim_buf_get_name(0)
    t = file ~= "" and file or resolve_target(nil)
  end
  if t and t ~= "" then run(config.bin_dir .. "/filament-slice.sh", t, "buffer", "filament: " .. vim.fn.fnamemodify(t, ":t:r")) end
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})

  local km = config.keymaps
  if km.slice_buffer then
    vim.keymap.set("n", km.slice_buffer, function() M.slice_buffer() end,
      { desc = "ctxslice: function slice → buffer" })
  end
  if km.slice_clipboard then
    vim.keymap.set("n", km.slice_clipboard, function() M.slice_clipboard() end,
      { desc = "ctxslice: function slice → clipboard" })
  end
  if km.filament_buffer then
    vim.keymap.set("n", km.filament_buffer, function() M.filament_buffer() end,
      { desc = "ctxslice: filament slice → buffer" })
  end

  vim.api.nvim_create_user_command("CtxSlice", function(a) M.slice_buffer(a.args) end,
    { nargs = "?", desc = "Function context slice → buffer" })
  vim.api.nvim_create_user_command("CtxSliceClip", function(a) M.slice_clipboard(a.args) end,
    { nargs = "?", desc = "Function context slice → clipboard" })
  vim.api.nvim_create_user_command("FilamentSlice", function(a) M.filament_buffer(a.args) end,
    { nargs = "?", complete = "file", desc = "Filament structural slice → buffer" })
end

return M
