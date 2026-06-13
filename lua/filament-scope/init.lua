local M = {}

local function project_root()
  local file = vim.api.nvim_buf_get_name(0)
  local start = file ~= "" and vim.fn.fnamemodify(file, ":p:h") or vim.uv.cwd()
  local found = vim.fs.find({ "artisan" }, { path = start, upward = true })
  if found and #found > 0 then
    return vim.fn.fnamemodify(found[1], ":h")
  end
  return nil
end

local _debounce_timer = nil

local function trigger_index(root)
  if _debounce_timer then
    _debounce_timer:stop()
    _debounce_timer:close()
  end
  _debounce_timer = vim.uv.new_timer()
  _debounce_timer:start(2000, 0, vim.schedule_wrap(function()
    require("filament-scope.indexer").run_async(root)
    _debounce_timer = nil
  end))
end

function M.setup(opts)
  local context  = require("filament-scope.context")
  local picker   = require("filament-scope.picker")
  local indexer  = require("filament-scope.indexer")

  -- Load on-disk index immediately (non-blocking read from JSON)
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      local root = project_root()
      if root then
        indexer.load(root)
        indexer.run_async(root)
      end
    end,
  })

  -- Re-index on PHP file save (debounced 2s)
  vim.api.nvim_create_autocmd("BufWritePost", {
    pattern = "*.php",
    callback = function()
      local root = project_root()
      if root then trigger_index(root) end
    end,
  })

  -- Picker trigger: normal mode
  vim.keymap.set("n", "<leader>fp", function()
    local ctx = context.detect()
    picker.open(ctx)
  end, { desc = "Filament picker" })

  -- Picker trigger: insert mode (returns to insert after selection)
  vim.keymap.set("i", "<leader>fp", function()
    local ctx = context.detect()
    picker.open(ctx)
  end, { desc = "Filament picker" })

  -- :FilamentIndex — manual full re-index
  vim.api.nvim_create_user_command("FilamentIndex", function()
    local root = project_root()
    if not root then
      vim.notify("filament-scope: no Laravel project root found (artisan not found)", vim.log.levels.WARN)
      return
    end
    vim.notify("filament-scope: indexing " .. root .. "/app/Filament ...", vim.log.levels.INFO)
    indexer.run_async(root)
  end, { desc = "Rebuild filament-scope index" })

  -- :FilamentIndexStatus — show last index stats
  vim.api.nvim_create_user_command("FilamentIndexStatus", function()
    local cache = indexer._cache or {}
    local component_count = 0
    local method_count = 0
    for _, methods in pairs(cache) do
      component_count = component_count + 1
      for _ in pairs(methods) do method_count = method_count + 1 end
    end
    vim.notify(
      string.format("filament-scope index: %d components, %d method entries",
        component_count, method_count),
      vim.log.levels.INFO
    )
  end, { desc = "Show filament-scope index status" })
end

return M
