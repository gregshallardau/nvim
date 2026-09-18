local Store = {}
Store.__index = Store

local function file_fingerprint(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then return nil end

  local mtime = stat.mtime or {}
  return table.concat({
    tostring(stat.size or 0),
    tostring(mtime.sec or 0),
    tostring(mtime.nsec or 0),
  }, ":")
end

local function read_json(path)
  local f = io.open(path, "r")
  if not f then return nil end

  local content = f:read("*a")
  f:close()

  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" then return nil end
  return decoded
end

local function write_json_atomic(path, value)
  local parent = vim.fs.dirname(path)
  vim.fn.mkdir(parent, "p")

  local ok, encoded = pcall(vim.json.encode, value)
  if not ok then return false, encoded end

  local tmp = path .. ".tmp"
  local f, err = io.open(tmp, "w")
  if not f then return false, err end

  f:write(encoded)
  f:close()

  local renamed, rename_err = os.rename(tmp, path)
  if not renamed then
    os.remove(tmp)
    return false, rename_err
  end

  return true
end

function Store.new(opts)
  assert(type(opts) == "table", "project-intel Store.new requires opts")
  assert(type(opts.id) == "string", "project-intel store requires id")
  assert(type(opts.cache_path) == "string", "project-intel store requires cache_path")
  assert(type(opts.parse_path) == "function", "project-intel store requires parse_path")
  assert(type(opts.build_view) == "function", "project-intel store requires build_view")

  local self = setmetatable({}, Store)
  self.id = opts.id
  self.version = opts.version or 1
  self.cache_path = opts.cache_path
  self.parse_path = opts.parse_path
  self.build_view = opts.build_view
  self.state = {
    version = self.version,
    files = {},
    view = {},
  }
  self.loaded_from_disk = false
  self.last_stats = {
    changed = 0,
    removed = 0,
    unchanged = 0,
  }
  return self
end

function Store:load()
  local decoded = read_json(self.cache_path)
  if not decoded or decoded.version ~= self.version or type(decoded.files) ~= "table" then
    return false
  end

  self.state = decoded
  self.state.view = self.state.view or self.build_view(self.state.files)
  self.loaded_from_disk = true
  return true
end

function Store:save()
  self.state.version = self.version
  return write_json_atomic(self.cache_path, self.state)
end

function Store:rebuild_view()
  self.state.view = self.build_view(self.state.files)
  return self.state.view
end

function Store:get_view()
  return self.state.view
end

function Store:get_file(path)
  return self.state.files[path]
end

function Store:update_file(path, defer_save)
  local fingerprint = file_fingerprint(path)
  if not fingerprint then
    return self:remove_file(path, defer_save)
  end

  local data, err = self.parse_path(path)
  if data == nil then
    return false, err or ("parse failed: " .. path)
  end

  self.state.files[path] = {
    fingerprint = fingerprint,
    data = data,
  }

  self:rebuild_view()
  if not defer_save then self:save() end
  return true
end

function Store:remove_file(path, defer_save)
  if self.state.files[path] == nil then return false end

  self.state.files[path] = nil
  self:rebuild_view()
  if not defer_save then self:save() end
  return true
end

function Store:reconcile(paths)
  local wanted = {}
  local changed, removed, unchanged = 0, 0, 0

  for _, path in ipairs(paths) do
    if path ~= "" then
      wanted[path] = true
      local fingerprint = file_fingerprint(path)
      local existing = self.state.files[path]

      if fingerprint and existing and existing.fingerprint == fingerprint then
        unchanged = unchanged + 1
      elseif fingerprint then
        local data = self.parse_path(path)
        if data ~= nil then
          self.state.files[path] = {
            fingerprint = fingerprint,
            data = data,
          }
          changed = changed + 1
        end
      end
    end
  end

  for path in pairs(self.state.files) do
    if not wanted[path] then
      self.state.files[path] = nil
      removed = removed + 1
    end
  end

  if changed > 0 or removed > 0 then
    self:rebuild_view()
    self:save()
  end

  self.last_stats = {
    changed = changed,
    removed = removed,
    unchanged = unchanged,
  }

  return self.last_stats
end

function Store:status()
  local count = 0
  for _ in pairs(self.state.files) do count = count + 1 end

  return {
    id = self.id,
    version = self.version,
    files = count,
    loaded_from_disk = self.loaded_from_disk,
    cache_path = self.cache_path,
    last_stats = self.last_stats,
  }
end

return Store
