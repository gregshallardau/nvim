local M = {}

M._cache = {}     -- { Component = { method = { top_arg, count } } }
M._raw = {}       -- { Component = { method = { arg_string = count } } }

-- Parse an array of PHP source lines and return raw frequency table.
-- Returns: { ComponentName = { methodName = { arg_string = count } } }
function M.parse_file(lines)
  local result = {}
  local current_component = nil
  local i = 1

  while i <= #lines do
    local line = lines[i]

    -- Detect component start: UpperCaseClass::make(
    local component = line:match("(%u%w+)::make%s*%(")
    if component then
      current_component = component
      -- Count ::make() occurrences for container-scope frequency
      if not result[current_component] then result[current_component] = {} end
      if not result[current_component]["make"] then result[current_component]["make"] = {} end
      result[current_component]["make"][""] = (result[current_component]["make"][""] or 0) + 1
    end

    -- Detect method call on current chain: ->methodName(args)
    if current_component then
      -- Capture everything after the opening paren (greedy), then strip the
      -- outer closing paren plus any trailing , or ; to handle nested parens
      -- like ->options(Helper::GetFoo()),
      local method, rest = line:match("%->(%w+)%s*%((.*)$")
      if method then
        local stripped = (rest or ""):gsub("[,;%s]*$", ""):gsub("%)$", "")
        -- Normalise args: trim whitespace
        local args = stripped:gsub("^%s*(.-)%s*$", "%1")
        if not result[current_component] then
          result[current_component] = {}
        end
        if not result[current_component][method] then
          result[current_component][method] = {}
        end
        local tbl = result[current_component][method]
        tbl[args] = (tbl[args] or 0) + 1
      end

      -- End of chain: any line ending with ; terminates the statement
      if line:match(";%s*$") then
        current_component = nil
      end
    end

    i = i + 1
  end

  return result
end

-- Given a table of { arg_string = count }, return the dominant arg (>50% share)
-- or "" if none dominates. Also returns the count of the top arg.
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

-- Return cached frequency data for a component/method pair.
-- Returns: { top_arg: string, count: number }
function M.get(component, method)
  local comp = M._cache[component]
  if not comp then return { top_arg = "", count = 0 } end
  return comp[method] or { top_arg = "", count = 0 }
end

-- Build the collapsed cache from raw frequency data.
local function build_cache(raw)
  local cache = {}
  for component, methods in pairs(raw) do
    cache[component] = {}
    for method, arg_counts in pairs(methods) do
      local top_arg, count = M.compute_top_arg(arg_counts)
      cache[component][method] = { top_arg = top_arg, count = count }
    end
  end
  return cache
end

-- Merge raw data from one file's parse result into the global raw table.
local function merge_raw(global_raw, file_raw)
  for component, methods in pairs(file_raw) do
    if not global_raw[component] then global_raw[component] = {} end
    for method, arg_counts in pairs(methods) do
      if not global_raw[component][method] then global_raw[component][method] = {} end
      for arg, count in pairs(arg_counts) do
        local tbl = global_raw[component][method]
        tbl[arg] = (tbl[arg] or 0) + count
      end
    end
  end
end

-- Write the cache to .nvim/filament-index.json in project_root.
local function write_cache(project_root, cache)
  local dir = project_root .. "/.nvim"
  vim.fn.mkdir(dir, "p")
  local path = dir .. "/filament-index.json"
  local ok, encoded = pcall(vim.fn.json_encode, cache)
  if not ok then return end
  local f = io.open(path, "w")
  if f then f:write(encoded); f:close() end
end

-- Load existing cache from .nvim/filament-index.json.
local function load_cache(project_root)
  local path = project_root .. "/.nvim/filament-index.json"
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  local ok, decoded = pcall(vim.fn.json_decode, content)
  if ok and type(decoded) == "table" then return decoded end
  return nil
end

-- Run a full async index of app/Filament/ under project_root.
function M.run_async(project_root)
  local filament_dir = project_root .. "/app/Filament"
  if vim.fn.isdirectory(filament_dir) == 0 then return end

  vim.system(
    { "rg", "--type", "php", "--files", filament_dir },
    { text = true },
    function(result)
      if result.code ~= 0 or not result.stdout then return end
      local files = vim.split(result.stdout, "\n", { trimempty = true })
      local global_raw = {}

      local pending = #files
      if pending == 0 then return end

      for _, filepath in ipairs(files) do
        vim.system({ "cat", filepath }, { text = true }, function(r)
          if r.code == 0 and r.stdout then
            local lines = vim.split(r.stdout, "\n")
            local file_raw = M.parse_file(lines)
            merge_raw(global_raw, file_raw)
          end
          pending = pending - 1
          if pending == 0 then
            -- All files processed — build and persist cache
            local cache = build_cache(global_raw)
            M._raw = global_raw
            M._cache = cache
            write_cache(project_root, cache)
          end
        end)
      end
    end
  )
end

-- Load the on-disk cache into memory (called on startup).
function M.load(project_root)
  local cached = load_cache(project_root)
  if cached then
    M._cache = cached
  end
end

return M
