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
      assert.truthy(result["Select"]["multiple"])
      assert.equal(1, result["Select"]["multiple"][""])
      assert.truthy(result["Select"]["badge"])
      assert.equal(1, result["Select"]["badge"]["false"])
      assert.truthy(result["Select"]["options"])
      assert.equal(1, result["Select"]["options"]["Helper::GetStatusOptions()"])
    end)

    it("handles multiple components in same file", function()
      local lines = {
        "TextInput::make('name')",
        "    ->required()",
        "    ->maxLength(255),",
        "Select::make('role')",
        "    ->options(Helper::GetRoleOptions()),",
      }
      local result = indexer.parse_file(lines)
      assert.truthy(result["TextInput"])
      assert.truthy(result["TextInput"]["required"])
      assert.truthy(result["Select"])
      assert.truthy(result["Select"]["options"])
    end)

    it("returns empty table for non-Filament PHP", function()
      local lines = {
        "public function boot()",
        "{",
        "    $this->loadRoutes();",
        "}",
      }
      local result = indexer.parse_file(lines)
      assert.same({}, result)
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
      -- schema should NOT be attributed to Select
      assert.falsy(result["Select"] and result["Select"]["schema"])
      -- TextInput should be parsed correctly
      assert.truthy(result["TextInput"])
      assert.truthy(result["TextInput"]["required"])
    end)
  end)

  describe("compute_top_arg", function()
    it("returns dominant arg when over 50%", function()
      local counts = { ["false"] = 8, ["true"] = 2 }
      local top_arg, count = indexer.compute_top_arg(counts)
      assert.equal("false", top_arg)
      assert.equal(8, count)
    end)

    it("returns empty string when no arg dominates", function()
      local counts = { ["false"] = 5, ["true"] = 5 }
      local top_arg, _ = indexer.compute_top_arg(counts)
      assert.equal("", top_arg)
    end)

    it("returns arg when it is the only one used", function()
      local counts = { ["Helper::GetUserOptions()"] = 6 }
      local top_arg, count = indexer.compute_top_arg(counts)
      assert.equal("Helper::GetUserOptions()", top_arg)
      assert.equal(6, count)
    end)

    it("returns empty string for empty counts", function()
      local top_arg, count = indexer.compute_top_arg({})
      assert.equal("", top_arg)
      assert.equal(0, count)
    end)
  end)

  describe("get", function()
    before_each(function()
      indexer._cache = {}
    end)

    it("returns zero count entry for unknown component/method", function()
      indexer._cache = {}
      local result = indexer.get("Select", "badge")
      assert.equal("", result.top_arg)
      assert.equal(0, result.count)
    end)

    it("returns cached data when available", function()
      indexer._cache = {
        Select = { badge = { top_arg = "false", count = 12 } }
      }
      local result = indexer.get("Select", "badge")
      assert.equal("false", result.top_arg)
      assert.equal(12, result.count)
    end)
  end)
end)
