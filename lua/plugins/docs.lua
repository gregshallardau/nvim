-- Documentation browser
-- Installed offline: php, laravel~11, tailwindcss, lua~5.4, composer
-- Filament PHP: vendor markdown search (offline) + browser fallback
-- Laravel 13, Livewire, Alpine.js: browser only (not on DevDocs)
-- Rendering: render-markdown.nvim covers all markdown + devdocs buffers

-- Three-level DevDocs picker: doc set → section → entry → open in float.
-- Reads nvim-devdocs internals directly so navigation is fully hierarchical.

local function telescope_pick(opts)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf    = require("telescope.config").values
  local actions = require("telescope.actions")
  local astate  = require("telescope.actions.state")

  pickers.new({}, {
    prompt_title    = opts.title,
    finder          = finders.new_table({
      results     = opts.items,
      entry_maker = opts.entry_maker,
    }),
    sorter          = conf.generic_sorter({}),
    previewer       = false,
    layout_config   = opts.layout or { width = 0.5, height = 0.6 },
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local sel = astate.get_selected_entry()
        actions.close(prompt_bufnr)
        if sel then opts.on_select(sel.value) end
      end)
      return true
    end,
  }):find()
end

-- Build full entry objects (with next_path) from a doc set's raw index entries.
local function build_full_entries(alias)
  local fs    = require("nvim-devdocs.fs")
  local index = fs.read_index()
  if not index or not index[alias] then return {} end
  local raw = index[alias].entries
  local out = {}
  for i, e in ipairs(raw) do
    out[i] = {
      name      = e.name,
      path      = e.path,
      link      = e.link,
      type      = e.type,
      alias     = alias,
      next_path = i < #raw and raw[i + 1].path or nil,
    }
  end
  return out
end

-- Level 3: pick an entry within a section and open it.
local function pick_entry(alias, section_name, all_entries)
  local filtered = vim.tbl_filter(function(e) return e.type == section_name end, all_entries)
  if #filtered == 0 then
    vim.notify("No entries for section: " .. section_name, vim.log.levels.WARN)
    return
  end

  telescope_pick({
    title  = section_name .. "  (" .. alias .. ")",
    items  = filtered,
    layout = { width = 0.6, height = 0.8 },
    entry_maker = function(e)
      return { value = e, display = e.name, ordinal = e.name }
    end,
    on_select = function(entry)
      local ops   = require("nvim-devdocs.operations")
      local bufnr = vim.api.nvim_create_buf(false, true)
      local lines = ops.read_entry(entry)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      ops.open(entry, bufnr, true)
    end,
  })
end

-- Level 2: pick a section within a doc set.
local function pick_section(alias, set_name)
  local fs    = require("nvim-devdocs.fs")
  local index = fs.read_index()
  if not index or not index[alias] then
    vim.notify("DevDocs: index not found for " .. alias, vim.log.levels.WARN)
    return
  end

  local types = index[alias].types or {}
  table.sort(types, function(a, b) return a.name < b.name end)

  -- Pre-build entries once so each section pick doesn't re-read the index.
  local all_entries = build_full_entries(alias)

  telescope_pick({
    title  = set_name .. " — sections",
    items  = types,
    entry_maker = function(t)
      local label = string.format("%-40s  %d entries", t.name, t.count)
      return { value = t.name, display = label, ordinal = t.name }
    end,
    on_select = function(section_name)
      pick_entry(alias, section_name, all_entries)
    end,
  })
end

-- Level 1: pick a doc set.
local function devdocs_picker()
  local lock_path = vim.fn.stdpath("data") .. "/devdocs/docs-lock.json"
  if vim.fn.filereadable(lock_path) == 0 then
    vim.notify("No DevDocs installed. Run :DevdocsInstall first.", vim.log.levels.WARN)
    return
  end

  local ok, raw = pcall(vim.fn.readfile, lock_path)
  if not ok then return end
  local lockfile = vim.fn.json_decode(table.concat(raw, "\n"))

  local sets = {}
  for alias, info in pairs(lockfile) do
    table.insert(sets, { alias = alias, name = info.name or alias })
  end
  table.sort(sets, function(a, b) return a.name < b.name end)

  telescope_pick({
    title  = "DevDocs — doc set",
    items  = sets,
    layout = { width = 0.4, height = 0.5 },
    entry_maker = function(e)
      return { value = e, display = e.name, ordinal = e.name }
    end,
    on_select = function(e)
      pick_section(e.alias, e.name)
    end,
  })
end

local function find_project_root()
  local file = vim.api.nvim_buf_get_name(0)
  local start = file ~= "" and vim.fn.fnamemodify(file, ":p:h") or vim.uv.cwd()
  local found = vim.fs.find({ "artisan" }, { path = start, upward = true })
  if found and #found > 0 then
    return vim.fn.fnamemodify(found[1], ":h")
  end
  return nil
end

local function filament_vendor_docs(mode)
  local root = find_project_root()
  if not root then
    vim.notify("filament-docs: no Laravel project found, opening browser", vim.log.levels.WARN)
    vim.fn.jobstart({ "xdg-open", "https://filamentphp.com/docs" }, { detach = true })
    return
  end

  local vendor_path = root .. "/vendor/filament"
  if vim.fn.isdirectory(vendor_path) == 0 then
    vim.notify("filament-docs: vendor/filament not found in " .. root, vim.log.levels.WARN)
    vim.fn.jobstart({ "xdg-open", "https://filamentphp.com/docs" }, { detach = true })
    return
  end

  if mode == "grep" then
    require("telescope.builtin").live_grep({
      cwd = vendor_path,
      prompt_title = "Search Filament Docs",
      additional_args = { "--glob", "*.md" },
    })
  else
    require("telescope.builtin").find_files({
      cwd = vendor_path,
      prompt_title = "Filament Docs (vendor)",
      find_command = { "find", ".", "-name", "*.md", "-not", "-path", "*/node_modules/*" },
    })
  end
end

-- Register :DevdocsPicker so the dashboard and other callers can reach the two-level picker
vim.api.nvim_create_user_command("DevdocsPicker", devdocs_picker, { desc = "DevDocs two-level picker" })

return {
  -- Extend render-markdown.nvim to cover devdocs buffers
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = { file_types = { "markdown", "devdocs" } },
    ft  = { "markdown", "devdocs" },
  },

  {
    "luckasRanarison/nvim-devdocs",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    cmd = {
      "DevdocsOpen",
      "DevdocsOpenFloat",
      "DevdocsInstall",
      "DevdocsFetch",
      "DevdocsUninstall",
    },
    config = function(_, opts)
      require("nvim-devdocs").setup(opts)
      -- Patch transpiler AFTER setup so the module is fully loaded.
      -- Bug: to_yaml crashes when registry entry values are non-string (number/bool/userdata).
      vim.defer_fn(function()
        local ok, transpiler = pcall(require, "nvim-devdocs.transpiler")
        if ok then
          local original = transpiler.to_yaml
          transpiler.to_yaml = function(entry)
            local safe = {}
            for k, v in pairs(entry) do
              safe[k] = type(v) == "table" and vim.fn.json_encode(v) or tostring(v)
            end
            return original(safe)
          end
        end
      end, 0)
    end,
    opts = {
      float_win = {
        relative = "editor",
        height = 38,
        width = 130,
        border = "rounded",
      },
      wrap = true,
      -- previewer = false: prevents the metadata preview from crashing on non-string values
      telescope = {
        previewer = false,
        layout_config = { width = 0.6, height = 0.7 },
      },
    },
    keys = {
      -- Offline docs (run :DevdocsInstall php laravel~11 tailwindcss lua~5.4 composer to install)
      { "<leader>dd", devdocs_picker,                           desc = "DevDocs",              mode = "n" },
      { "<leader>dp", "<cmd>DevdocsOpenFloat php<cr>",         desc = "PHP docs",             mode = "n" },
      { "<leader>dl", "<cmd>DevdocsOpenFloat laravel~11<cr>",  desc = "Laravel docs",         mode = "n" },
      { "<leader>dt", "<cmd>DevdocsOpenFloat tailwindcss<cr>", desc = "Tailwind docs",        mode = "n" },
      { "<leader>dc", "<cmd>DevdocsOpenFloat composer<cr>",    desc = "Composer docs",        mode = "n" },
      { "<leader>dv", "<cmd>DevdocsOpenFloat lua~5.4<cr>",     desc = "Lua docs",             mode = "n" },
      -- Neovim + all installed plugin help
      { "<leader>dh", "<cmd>Telescope help_tags<cr>",          desc = "Neovim/plugin help",   mode = "n" },
      -- Filament: offline vendor search, browser fallback
      { "<leader>df", function() filament_vendor_docs("files") end, desc = "Filament docs (vendor)", mode = "n" },
      { "<leader>dF", function() filament_vendor_docs("grep")  end, desc = "Filament grep (vendor)", mode = "n" },
      -- Browser only
      { "<leader>dB", function()
          vim.fn.jobstart({ "xdg-open", "https://filamentphp.com/docs" }, { detach = true })
        end, desc = "Filament (browser)", mode = "n" },
      { "<leader>dL", function()
          vim.fn.jobstart({ "xdg-open", "https://laravel.com/docs/13.x" }, { detach = true })
        end, desc = "Laravel 13 (browser)", mode = "n" },
      { "<leader>dw", function()
          vim.fn.jobstart({ "xdg-open", "https://livewire.laravel.com/docs" }, { detach = true })
        end, desc = "Livewire (browser)", mode = "n" },
      { "<leader>da", function()
          vim.fn.jobstart({ "xdg-open", "https://alpinejs.dev/start-here" }, { detach = true })
        end, desc = "Alpine.js (browser)", mode = "n" },
    },
  },
}
