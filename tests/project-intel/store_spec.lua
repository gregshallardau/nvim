local Store = require("project-intel.store")

describe("project-intel store", function()
  local root
  local cache

  before_each(function()
    root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    cache = root .. "/cache.json"
  end)

  after_each(function()
    vim.fn.delete(root, "rf")
  end)

  local function write(path, content)
    local f = assert(io.open(path, "w"))
    f:write(content)
    f:close()
  end

  it("reuses unchanged per-file state and reparses only changed files", function()
    local a = root .. "/a.txt"
    local b = root .. "/b.txt"
    write(a, "one")
    write(b, "two")

    local parses = 0
    local store = Store.new({
      id = "test",
      cache_path = cache,
      parse_path = function(path)
        parses = parses + 1
        local f = assert(io.open(path, "r"))
        local value = f:read("*a")
        f:close()
        return value
      end,
      build_view = function(files)
        local values = {}
        for path, record in pairs(files) do
          values[path] = record.data
        end
        return values
      end,
    })

    local first = store:reconcile({ a, b })
    assert.equal(2, first.changed)
    assert.equal(2, parses)

    local second = store:reconcile({ a, b })
    assert.equal(2, second.unchanged)
    assert.equal(2, parses)

    vim.wait(10)
    write(a, "changed")

    local third = store:reconcile({ a, b })
    assert.equal(1, third.changed)
    assert.equal(1, third.unchanged)
    assert.equal(3, parses)
    assert.equal("changed", store:get_view()[a])
  end)

  it("removes files that disappear from the reconciled set", function()
    local a = root .. "/a.txt"
    local b = root .. "/b.txt"
    write(a, "one")
    write(b, "two")

    local store = Store.new({
      id = "test",
      cache_path = cache,
      parse_path = function(path)
        local f = assert(io.open(path, "r"))
        local value = f:read("*a")
        f:close()
        return value
      end,
      build_view = function(files)
        return files
      end,
    })

    store:reconcile({ a, b })
    local stats = store:reconcile({ a })

    assert.equal(1, stats.removed)
    assert.is_nil(store:get_file(b))
  end)

  it("hot-loads persisted state", function()
    local a = root .. "/a.txt"
    write(a, "one")

    local opts = {
      id = "test",
      cache_path = cache,
      parse_path = function(path)
        local f = assert(io.open(path, "r"))
        local value = f:read("*a")
        f:close()
        return value
      end,
      build_view = function(files)
        return files
      end,
    }

    local first = Store.new(opts)
    first:reconcile({ a })

    local second = Store.new(opts)
    assert.is_true(second:load())
    assert.is_true(second:status().loaded_from_disk)
    assert.truthy(second:get_file(a))
  end)
end)
