local M = {}

local function get_display(entry, index_data)
  local count_str = index_data.count > 0
    and string.format(" [×%d]", index_data.count)
    or ""
  local arg_str = index_data.top_arg ~= ""
    and "   " .. index_data.top_arg
    or ""

  if entry.method then
    return string.format("->%s()%s%s", entry.method, count_str, arg_str)
  else
    return string.format("%s%s%s", entry.name, count_str, arg_str)
  end
end

-- Open the Filament scope picker.
-- ctx: { scope: string, component: string|nil }
function M.open(ctx)
  local ok_telescope, pickers    = pcall(require, "telescope.pickers")
  local ok_finders,  finders     = pcall(require, "telescope.finders")
  local ok_conf,     conf_mod    = pcall(require, "telescope.config")
  local ok_actions,  actions     = pcall(require, "telescope.actions")
  local ok_state,    action_state = pcall(require, "telescope.actions.state")
  local ok_prev,     previewers  = pcall(require, "telescope.previewers")

  if not (ok_telescope and ok_finders and ok_conf and ok_actions and ok_state and ok_prev) then
    vim.notify("filament-scope: Telescope not available", vim.log.levels.ERROR)
    return
  end

  local conf    = conf_mod.values
  local registry = require("filament-scope.registry")
  local indexer  = require("filament-scope.indexer")
  local inserter = require("filament-scope.inserter")

  local scope = ctx.scope
  local component = ctx.component

  if scope == "unknown" then
    vim.notify("filament-scope: cursor not inside a recognised Filament scope", vim.log.levels.WARN)
    return
  end

  -- Build entry list from registry
  local registry_entries = registry.get(scope, component)

  if #registry_entries == 0 then
    vim.notify("filament-scope: no entries for scope: " .. scope, vim.log.levels.WARN)
    return
  end

  -- Attach index data and sort: highest count first, then alphabetical
  local enriched = {}
  for _, entry in ipairs(registry_entries) do
    local key = entry.method or entry.name or ""
    local index_data = indexer.get(component or scope, key)
    table.insert(enriched, {
      entry      = entry,
      index_data = index_data,
      display    = get_display(entry, index_data),
      ordinal    = string.format("%08d_%s", 99999999 - index_data.count, key),
    })
  end

  table.sort(enriched, function(a, b) return a.ordinal < b.ordinal end)

  local title = scope == "component"
    and ("Filament: " .. (component or "Component") .. " methods")
    or  ("Filament: " .. scope:gsub("_", " "))

  pickers.new({}, {
    prompt_title = title,
    finder = finders.new_table({
      results = enriched,
      entry_maker = function(e)
        return {
          value   = e,
          display = e.display,
          ordinal = e.ordinal,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    previewer = previewers.new_buffer_previewer({
      title = "Details",
      define_preview = function(self, entry)
        local e    = entry.value.entry
        local idata = entry.value.index_data
        local lines = {}
        if e.desc then
          table.insert(lines, e.desc)
          table.insert(lines, "")
        end
        if idata.count > 0 then
          table.insert(lines, string.format("Used %d time(s) in your codebase", idata.count))
          if idata.top_arg ~= "" then
            table.insert(lines, "Most common arg: " .. idata.top_arg)
          end
          table.insert(lines, "")
        end
        local preview_text = inserter.build_insert_text(e, idata)
        table.insert(lines, "Will insert:")
        table.insert(lines, preview_text)
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      end,
    }),
    attach_mappings = function(prompt_bufnr, _)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if selection then
          local e     = selection.value.entry
          local idata = selection.value.index_data
          local text  = inserter.build_insert_text(e, idata)
          inserter.insert(text)
        end
      end)
      return true
    end,
  }):find()
end

return M
