local Store = require("project-intel.store")

local M = {}

M._cache = {}
M._raw = {}
M._store = nil
M._root = nil

function M.parse_file(lines)
  local result = {}
  local current_component = nil
  local i = 1

  while i <= #lines do
    local line = lines[i]

    local component = line:match("(%u%w+)::make%s*%(")
    if component then
      current_component = component
      if not result[current_component] then result[current_component] = {} end
      if not result[current_component]["make"] then result[current_component]["make"] = {} end
      result[current_component]["make"][""] = (result[current_component]["make"][""] or 0) + 1
    end

    if current_component then
      local method, rest = line:match("%->(%w+)%s*%((.*)$")
      if method then
        local stripped = (rest or ""):gsub("[,;%s]*$", ""):gsub("%)$", "")
        local args = stripped:gsub("^%s*(.-)%s*$", "%1")

        if not result[current_component] then result[current_component] = {} end
        if not result[current_component][method] then result[current_component][method] = {} end

        local tbl = result[current_component][method]
        tbl[args] = (tbl[args] or 0) + 1
      end

      if line:match(";%s*$") then
        current_component = nil
      end
    end

    i = i + 1
  end

  return result
end

function M.compute_top_arg(arg_counts)
  local total = 0
  local top_arg, top_count = "", 0

  for arg, count in pairs(arg_counts) do
    total = total + count
    if count > top_count then
      top_count = count
      top_arg = arg
    end
  end

  if total == 0 then return "", 0 end
  if top_count / total > 0.5 then
    return top_arg, top_count
  end
  return "", top_count
end

local function merge_raw(global_raw, file_raw)
  for component, methods in pairs(file_raw or {}) do
    if not global_raw[component] then global_raw[component] = {} end

    for method, arg_counts in pairs(methods) do
      if not global_raw[component][method] then
        global_raw[component][method] = {}
      end

      for arg, count in pairs(arg_counts) do
        local target = global_raw[component][method]
        target[arg] = (target[arg] or 0) + count
      end
    end
  end
end

local function build_cache(raw)
  local cache = {}

  for component, methods in pairs(raw) do
    cache[component] = {}

    for method, arg_counts in pairs(methods) do
      local top_arg, count = M.compute_top_arg(arg_counts)
      cache[component][method] = {
        top_arg = top_arg,
        count = count,
      }
    end
  end

  return cache
end

function M.build_view(files)
  local raw = {}

  for _, record in pairs(files or {}) do
    merge_raw(raw, record.data)
  end

  return {
    raw = raw,
    cache = build_cache(raw),
  }
end

local function parse_path(path)
  local f = io.open(path, "r")
  if not f then return nil, "unable to read " .. path end

  local content = f:read("*a")
  f:close()

  return M.parse_file(vim.split(content, "\n", { plain = true }))
end

local function sync_public_state()
  if not M._store then
    M._raw = {}
    M._cache = {}
    return
  end

  local view = M._store:get_view() or {}
  M._raw = view.raw or {}
  M._cache = view.cache or {}
end

local function ensure_store(project_root)
  if M._store and M._root == project_root then
    return M._store
  end

  M._root = project_root
  M._store = Store.new({
    id = "filament-scope",
    version = 2,
    cache_path = project_root .. "/.nvim/project-intel/filament-scope.json",
    parse_path = parse_path,
    build_view = M.build_view,
  })

  return M._store
end

local function filament_dir(project_root)
  return project_root .. "/app/Filament"
end

local function in_filament_tree(project_root, path)
  local prefix = filament_dir(project_root) .. "/"
  return path:sub(1, #prefix) == prefix
end

function M.load(project_root)
  local store = ensure_store(project_root)
  store:load()
  sync_public_state()
  return store:status()
end

function M.reconcile_async(project_root, callback)
  local store = ensure_store(project_root)
  local dir = filament_dir(project_root)

  if vim.fn.isdirectory(dir) == 0 then
    if callback then callback({ changed = 0, removed = 0, unchanged = 0 }) end
    return
  end

  vim.system(
    { "rg", "--type", "php", "--files", dir },
    { text = true },
    function(result)
      if result.code ~= 0 or not result.stdout then
        if callback then
          vim.schedule(function()
            callback(nil, result.stderr or "rg failed")
          end)
        end
        return
      end

      local paths = vim.split(result.stdout, "\n", { trimempty = true })

      vim.schedule(function()
        local stats = store:reconcile(paths)
        sync_public_state()
        if callback then callback(stats) end
      end)
    end
  )
end

function M.update_file(project_root, path)
  if not in_filament_tree(project_root, path) then
    return false
  end

  local store = ensure_store(project_root)
  local changed, err = store:update_file(path)
  sync_public_state()
  return changed, err
end

function M.remove_file(project_root, path)
  local store = ensure_store(project_root)
  local changed = store:remove_file(path)
  sync_public_state()
  return changed
end

function M.run_async(project_root)
  return M.reconcile_async(project_root)
end

function M.get(component, method)
  local comp = M._cache[component]
  if not comp then return { top_arg = "", count = 0 } end
  return comp[method] or { top_arg = "", count = 0 }
end

function M.status()
  if not M._store then
    return {
      ready = false,
      components = 0,
      methods = 0,
    }
  end

  local components, methods = 0, 0
  for _, entries in pairs(M._cache) do
    components = components + 1
    for _ in pairs(entries) do methods = methods + 1 end
  end

  local status = M._store:status()
  status.ready = true
  status.components = components
  status.methods = methods
  status.project_root = M._root
  return status
end

return M
