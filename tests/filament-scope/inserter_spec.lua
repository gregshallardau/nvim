local inserter = require("filament-scope.inserter")

describe("filament-scope inserter", function()
  describe("build_insert_text for component methods", function()
    it("inserts ->method() for no-arg simple method with no index data", function()
      local entry = { method = "multiple", args = "", complex = false }
      local index_data = { top_arg = "", count = 0 }
      local text = inserter.build_insert_text(entry, index_data)
      assert.equal("->multiple()", text)
    end)

    it("pre-fills dominant arg for simple method", function()
      local entry = { method = "badge", args = "", complex = false }
      local index_data = { top_arg = "false", count = 12 }
      local text = inserter.build_insert_text(entry, index_data)
      assert.equal("->badge(false)", text)
    end)

    it("inserts snippet placeholder when no dominant arg", function()
      local entry = { method = "maxLength", args = "(${1:255})", complex = false }
      local index_data = { top_arg = "", count = 5 }
      local text = inserter.build_insert_text(entry, index_data)
      assert.equal("->maxLength(${1:255})", text)
    end)

    it("pre-fills dominant arg even when args template has placeholder", function()
      local entry = { method = "maxLength", args = "(${1:255})", complex = false }
      local index_data = { top_arg = "100", count = 8 }
      local text = inserter.build_insert_text(entry, index_data)
      assert.equal("->maxLength(100)", text)
    end)

    it("returns args template unchanged for complex methods", function()
      local entry = {
        method = "getSearchResultsUsing",
        args = "(fn (string $search): array => Model::query()->limit(50)->all())",
        complex = true,
      }
      local index_data = { top_arg = "closure", count = 3 }
      local text = inserter.build_insert_text(entry, index_data)
      assert.equal("->getSearchResultsUsing" .. entry.args, text)
    end)
  end)

  describe("build_insert_text for container entries", function()
    it("returns snippet string for container entry", function()
      local entry = { name = "TextColumn", snippet = "TextColumn::make('${1:column}')", desc = "Plain text" }
      local text = inserter.build_insert_text(entry, { top_arg = "", count = 0 })
      assert.equal("TextColumn::make('${1:column}')", text)
    end)
  end)
end)
