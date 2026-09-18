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

local function register_project_intel(indexer, root)
  require("project-intel").register({
    id = "filament-scope",
    status = indexer.status,
    refresh = function()
      indexer.reconcile_async(root)
    end,
  })
end

function M.setup(_opts)
  local context = require("filament-scope.context")
  local picker = require("filament-scope.picker")
  local indexer = require("filament-scope.indexer")

  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      local root = project_root()
      if not root then return end

      -- Hot-start from persisted state immediately, then reconcile only files
      -- whose fingerprints changed while Neovim was closed.
      indexer.load(root)
      register_project_intel(indexer, root)
      indexer.reconcile_async(root)
    end,
  })

  -- A save is a file-level delta, not a reason to rescan app/Filament.
  vim.api.nvim_create_autocmd({ "BufWritePost", "FileChangedShellPost" }, {
    pattern = "*.php",
    callback = function(args)
      local root = project_root()
      if not root then return end

      local path = vim.api.nvim_buf_get_name(args.buf)
      if path ~= "" then
        indexer.update_file(root, path)
      end
    end,
  })

  vim.keymap.set("n", "<leader>fp", function()
    picker.open(context.detect())
  end, { desc = "Filament picker" })

  vim.keymap.set("i", "<leader>fp", function()
    picker.open(context.detect())
  end, { desc = "Filament picker" })

  vim.api.nvim_create_user_command("FilamentIndex", function()
    local root = project_root()
    if not root then
      vim.notify("filament-scope: no Laravel project root found", vim.log.levels.WARN)
      return
    end

    indexer.reconcile_async(root, function(stats, err)
      if err then
        vim.notify("filament-scope: " .. tostring(err), vim.log.levels.ERROR)
        return
      end

      vim.notify(
        string.format(
          "filament-scope: %d changed, %d removed, %d unchanged",
          stats.changed,
          stats.removed,
          stats.unchanged
        ),
        vim.log.levels.INFO
      )
    end)
  end, { desc = "Reconcile filament-scope index" })

  vim.api.nvim_create_user_command("FilamentIndexStatus", function()
    vim.notify(vim.inspect(indexer.status()), vim.log.levels.INFO)
  end, { desc = "Show filament-scope index status" })
end

return M
