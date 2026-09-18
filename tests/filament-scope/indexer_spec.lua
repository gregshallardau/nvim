local indexer = require("filament-scope.indexer")

describe("filament-scope indexer", function()
  describe("parse_file", function()
    it("extracts component method calls and args", function()
      local lines = {
        "Select::make('status')",
        "    ->multiple()",
        "    ->badge(false)",
        "    ->options(Helper::GetStatusOptions()),",
      }

      local result = indexer.parse_file(lines)
      assert.truthy(result["Select"])
      assert.equal(1, result["Select"]["multiple"][""])
      assert.equal(1, result["Select"]["badge"]["false"])
      assert.equal(1, result["Select"]["options"]["Helper::GetStatusOptions()"])
    end)

    it("does not attribute methods after a completed chain to the previous component", function()
      local lines = {
        "Select::make('status')",
        "    ->multiple()",
        "    ->badge(false);",
        "$form->schema([",
        "    TextInput::make('name')",
        "        ->required(),",
        "])",
      }

      local result = indexer.parse_file(lines)
      assert.falsy(result["Select"] and result["Select"]["schema"])
      assert.truthy(result["TextInput"])
      assert.truthy(result["TextInput"]["required"])
    end)
  end)

  describe("derived cache", function()
    it("aggregates independent per-file contributions", function()
      local view = indexer.build_view({
        ["a.php"] = {
          data = {
            Select = {
              badge = { ["false"] = 3 },
            },
          },
        },
        ["b.php"] = {
          data = {
            Select = {
              badge = { ["false"] = 2, ["true"] = 1 },
            },
          },
        },
      })

      assert.equal(6, view.cache.Select.badge.count)
      assert.equal("false", view.cache.Select.badge.top_arg)
    end)

    it("naturally drops a removed file from the derived view", function()
      local files = {
        ["a.php"] = {
          data = { Select = { badge = { ["false"] = 3 } } },
        },
        ["b.php"] = {
          data = { Select = { badge = { ["true"] = 4 } } },
        },
      }

      local both = indexer.build_view(files)
      assert.equal(4, both.cache.Select.badge.count)
      assert.equal("true", both.cache.Select.badge.top_arg)

      files["b.php"] = nil
      local after = indexer.build_view(files)
      assert.equal(3, after.cache.Select.badge.count)
      assert.equal("false", after.cache.Select.badge.top_arg)
    end)
  end)

  describe("compute_top_arg", function()
    it("returns dominant arg when over 50%", function()
      local top_arg, count = indexer.compute_top_arg({ ["false"] = 8, ["true"] = 2 })
      assert.equal("false", top_arg)
      assert.equal(8, count)
    end)

    it("returns empty string when no arg dominates", function()
      local top_arg = indexer.compute_top_arg({ ["false"] = 5, ["true"] = 5 })
      assert.equal("", top_arg)
    end)
  end)
end)
