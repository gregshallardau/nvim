# filament-scope Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a cursor-aware Filament v5 scaffolding picker that detects which builder scope the cursor is inside, shows frequency-ranked method options from your own codebase, and inserts smart snippets pre-filled with your most-used arguments.

**Architecture:** Six Lua modules in `lua/filament-scope/` — context detector (regex scan backwards from cursor), static registry (Filament v5 API), async ripgrep indexer (frequency table cached as JSON), Telescope picker (freq-sorted), and smart inserter (pre-filled snippets). Registered as a local lazy.nvim plugin.

**Tech Stack:** Lua, Neovim 0.10+, lazy.nvim, Telescope, plenary.nvim (tests), ripgrep, vim.snippet (simple inserts), LuaSnip (complex snippets)

---

## File Map

| File | Responsibility |
|---|---|
| `lua/filament-scope/init.lua` | `setup()`, keybindings, autocmds, user commands |
| `lua/filament-scope/context.lua` | `detect(bufnr, lnum)` → `{scope, component}` |
| `lua/filament-scope/registry.lua` | Static Filament v5 API data per scope |
| `lua/filament-scope/indexer.lua` | ripgrep runner, file parser, JSON cache |
| `lua/filament-scope/picker.lua` | Telescope custom picker |
| `lua/filament-scope/inserter.lua` | Snippet builder and inserter |
| `lua/plugins/filament-scope.lua` | lazy.nvim plugin spec |
| `tests/filament-scope/context_spec.lua` | Unit tests for context detection |
| `tests/filament-scope/indexer_spec.lua` | Unit tests for indexer parsing logic |
| `tests/filament-scope/inserter_spec.lua` | Unit tests for insertion logic |
| `tests/filament-scope/minimal_init.lua` | Minimal nvim init for headless test runs |

---

## Task 1: Scaffold

**Files:**
- Create: `lua/filament-scope/init.lua`
- Create: `lua/filament-scope/context.lua`
- Create: `lua/filament-scope/registry.lua`
- Create: `lua/filament-scope/indexer.lua`
- Create: `lua/filament-scope/picker.lua`
- Create: `lua/filament-scope/inserter.lua`
- Create: `lua/plugins/filament-scope.lua`
- Create: `tests/filament-scope/minimal_init.lua`

- [ ] **Step 1: Create module stubs**

`lua/filament-scope/context.lua`:
```lua
local M = {}
function M.detect(bufnr, lnum) return { scope = "unknown" } end
return M
```

`lua/filament-scope/registry.lua`:
```lua
local M = {}
M.containers = {}
M.methods = {}
function M.get(scope, component) return {} end
return M
```

`lua/filament-scope/indexer.lua`:
```lua
local M = {}
M._cache = {}
function M.parse_file(lines) return {} end
function M.compute_top_arg(arg_counts) return "", 0 end
function M.get(component, method) return { top_arg = "", count = 0 } end
function M.run_async(project_root) end
return M
```

`lua/filament-scope/picker.lua`:
```lua
local M = {}
function M.open(ctx) vim.notify("filament-scope: picker not yet implemented") end
return M
```

`lua/filament-scope/inserter.lua`:
```lua
local M = {}
function M.build_insert_text(entry, index_data) return "" end
function M.insert(text) end
return M
```

`lua/filament-scope/init.lua`:
```lua
local M = {}
function M.setup()
  vim.notify("filament-scope loaded", vim.log.levels.INFO)
end
return M
```

- [ ] **Step 2: Create lazy.nvim plugin spec**

`lua/plugins/filament-scope.lua`:
```lua
return {
  {
    dir = vim.fn.stdpath("config"),
    name = "filament-scope",
    lazy = false,
    config = function()
      require("filament-scope").setup()
    end,
  },
}
```

- [ ] **Step 3: Create minimal test init**

`tests/filament-scope/minimal_init.lua`:
```lua
-- Minimal Neovim init for headless test runs.
-- Adds the nvim config lua dir to runtimepath so require() works.
vim.opt.runtimepath:append(vim.fn.stdpath("config"))
vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/lazy/plenary.nvim")
```

- [ ] **Step 4: Start Neovim and verify it loads without errors**

```bash
nvim --headless -c "lua print(require('filament-scope') and 'OK' or 'FAIL')" -c "qa" 2>&1
```

Expected output: `OK`

- [ ] **Step 5: Commit**

```bash
git add lua/filament-scope/ lua/plugins/filament-scope.lua tests/filament-scope/minimal_init.lua
git commit -m "feat: scaffold filament-scope plugin structure"
```

---

## Task 2: Registry

**Files:**
- Modify: `lua/filament-scope/registry.lua`

- [ ] **Step 1: Write the full registry**

Replace `lua/filament-scope/registry.lua` with:

```lua
local M = {}

-- Container scopes: what to insert inside ->columns([...]) etc.
-- Each entry inserts ClassName::make(...) as a snippet.
M.containers = {
  table_columns = {
    { name = "TextColumn",      snippet = "TextColumn::make('${1:column}')",      desc = "Plain text" },
    { name = "BadgeColumn",     snippet = "BadgeColumn::make('${1:column}')",     desc = "Badge display" },
    { name = "IconColumn",      snippet = "IconColumn::make('${1:column}')",      desc = "Icon from value" },
    { name = "ImageColumn",     snippet = "ImageColumn::make('${1:column}')",     desc = "Image from path" },
    { name = "CheckboxColumn",  snippet = "CheckboxColumn::make('${1:column}')",  desc = "Inline editable checkbox" },
    { name = "ToggleColumn",    snippet = "ToggleColumn::make('${1:column}')",    desc = "Inline editable toggle" },
    { name = "ColorColumn",     snippet = "ColorColumn::make('${1:column}')",     desc = "Color swatch" },
    { name = "SelectColumn",    snippet = "SelectColumn::make('${1:column}')",    desc = "Inline editable select" },
    { name = "TagsColumn",      snippet = "TagsColumn::make('${1:column}')",      desc = "Tags from JSON/relation" },
    { name = "TextInputColumn", snippet = "TextInputColumn::make('${1:column}')", desc = "Inline editable text" },
  },
  form_fields = {
    { name = "TextInput",      snippet = "TextInput::make('${1:field}')",          desc = "Text input" },
    { name = "Select",         snippet = "Select::make('${1:field}')",             desc = "Select dropdown" },
    { name = "Toggle",         snippet = "Toggle::make('${1:field}')",             desc = "Boolean toggle" },
    { name = "DatePicker",     snippet = "DatePicker::make('${1:field}')",         desc = "Date picker" },
    { name = "DateTimePicker", snippet = "DateTimePicker::make('${1:field}')",     desc = "Date and time picker" },
    { name = "TimePicker",     snippet = "TimePicker::make('${1:field}')",         desc = "Time picker" },
    { name = "FileUpload",     snippet = "FileUpload::make('${1:field}')",         desc = "File / image upload" },
    { name = "RichEditor",     snippet = "RichEditor::make('${1:field}')",         desc = "Rich text editor" },
    { name = "MarkdownEditor", snippet = "MarkdownEditor::make('${1:field}')",     desc = "Markdown editor" },
    { name = "ColorPicker",    snippet = "ColorPicker::make('${1:field}')",        desc = "Color picker" },
    { name = "KeyValue",       snippet = "KeyValue::make('${1:field}')",           desc = "Key-value pairs" },
    { name = "TagsInput",      snippet = "TagsInput::make('${1:field}')",          desc = "Free-form tags" },
    { name = "Checkbox",       snippet = "Checkbox::make('${1:field}')",           desc = "Single checkbox" },
    { name = "Radio",          snippet = "Radio::make('${1:field}')\n    ->options([\n        ${2:}\n    ])", desc = "Radio buttons" },
    { name = "CheckboxList",   snippet = "CheckboxList::make('${1:field}')\n    ->options([\n        ${2:}\n    ])", desc = "Checkbox list" },
    { name = "Repeater",       snippet = "Repeater::make('${1:field}')\n    ->schema([\n        ${2:}\n    ])", desc = "Repeatable fields" },
    { name = "Fieldset",       snippet = "Fieldset::make('${1:label}')\n    ->schema([\n        ${2:}\n    ])", desc = "Fieldset group" },
    { name = "Section",        snippet = "Section::make('${1:label}')\n    ->schema([\n        ${2:}\n    ])", desc = "Collapsible section" },
    { name = "Grid",           snippet = "Grid::make(${1:2})\n    ->schema([\n        ${2:}\n    ])", desc = "Grid layout" },
    { name = "Tabs",           snippet = "Tabs::make()\n    ->tabs([\n        Tabs\\Tab::make('${1:Tab}')\n            ->schema([\n                ${2:}\n            ]),\n    ])", desc = "Tabbed layout" },
    { name = "Wizard",         snippet = "Wizard::make([\n    Wizard\\Step::make('${1:Step}')\n        ->schema([\n            ${2:}\n        ]),\n])", desc = "Multi-step wizard" },
  },
  infolist_entries = {
    { name = "TextEntry",       snippet = "TextEntry::make('${1:field}')",          desc = "Plain text" },
    { name = "BadgeEntry",      snippet = "BadgeEntry::make('${1:field}')",         desc = "Badge" },
    { name = "ImageEntry",      snippet = "ImageEntry::make('${1:field}')",         desc = "Image" },
    { name = "IconEntry",       snippet = "IconEntry::make('${1:field}')",          desc = "Icon" },
    { name = "ColorEntry",      snippet = "ColorEntry::make('${1:field}')",         desc = "Color swatch" },
    { name = "KeyValueEntry",   snippet = "KeyValueEntry::make('${1:field}')",      desc = "Key-value pairs" },
    { name = "RepeatableEntry", snippet = "RepeatableEntry::make('${1:field}')\n    ->schema([\n        ${2:}\n    ])", desc = "Repeatable entries" },
    { name = "Section",         snippet = "Section::make('${1:label}')\n    ->schema([\n        ${2:}\n    ])", desc = "Section group" },
    { name = "Fieldset",        snippet = "Fieldset::make('${1:label}')\n    ->schema([\n        ${2:}\n    ])", desc = "Fieldset group" },
    { name = "Grid",            snippet = "Grid::make(${1:2})\n    ->schema([\n        ${2:}\n    ])", desc = "Grid layout" },
    { name = "Tabs",            snippet = "Tabs::make()\n    ->tabs([\n        Tabs\\Tab::make('${1:Tab}')\n            ->schema([\n                ${2:}\n            ]),\n    ])", desc = "Tabbed layout" },
  },
  table_filters = {
    { name = "SelectFilter",  snippet = "SelectFilter::make('${1:field}')\n    ->options(${2:})", desc = "Select-based filter" },
    { name = "TernaryFilter", snippet = "TernaryFilter::make('${1:field}')",                      desc = "True / false / null filter" },
    { name = "Filter",        snippet = "Filter::make('${1:name}')\n    ->form([\n        ${2:}\n    ])\n    ->query(fn (Builder \\$query, array \\$data) => \\$query)", desc = "Custom filter with form" },
    { name = "QueryBuilder",  snippet = "QueryBuilder::make()\n    ->constraints([\n        ${2:}\n    ])", desc = "Advanced query builder" },
  },
  actions = {
    { name = "CreateAction",      snippet = "CreateAction::make()",       desc = "Create record" },
    { name = "EditAction",        snippet = "EditAction::make()",         desc = "Edit record" },
    { name = "DeleteAction",      snippet = "DeleteAction::make()",       desc = "Delete record" },
    { name = "ViewAction",        snippet = "ViewAction::make()",         desc = "View record" },
    { name = "ForceDeleteAction", snippet = "ForceDeleteAction::make()",  desc = "Force delete (soft delete)" },
    { name = "RestoreAction",     snippet = "RestoreAction::make()",      desc = "Restore soft deleted" },
    { name = "ExportAction",      snippet = "ExportAction::make()",       desc = "Export records" },
    { name = "ImportAction",      snippet = "ImportAction::make()",       desc = "Import records" },
    { name = "Action",            snippet = "Action::make('${1:name}')\n    ->label('${2:Label}')\n    ->action(fn (${3:Model} \\$record) => ${4:})", desc = "Custom action" },
    { name = "BulkAction",        snippet = "BulkAction::make('${1:name}')\n    ->label('${2:Label}')\n    ->action(fn (Collection \\$records) => ${3:})", desc = "Bulk action" },
  },
}

-- Component method scopes: what to chain on SomeClass::make(...)->
-- Each entry: { method, args (snippet for args portion), complex, desc }
-- args = "" means no args. args string is everything including parens.
M.methods = {
  common = {
    { method = "label",         args = "('${1:Label}')",      complex = false, desc = "Display label" },
    { method = "helperText",    args = "('${1:Help text}')",  complex = false, desc = "Helper text below field" },
    { method = "hint",          args = "('${1:Hint}')",       complex = false, desc = "Hint shown top-right" },
    { method = "hidden",        args = "(${1:true})",         complex = false, desc = "Hide field" },
    { method = "disabled",      args = "",                    complex = false, desc = "Disable interaction" },
    { method = "columnSpan",    args = "('full')",            complex = false, desc = "Span full grid width" },
    { method = "extraAttributes", args = "(['${1:}'])",       complex = false, desc = "Extra HTML attributes" },
  },
  Select = {
    { method = "multiple",              args = "",                                                                                   complex = false, desc = "Allow multiple selections" },
    { method = "searchable",            args = "",                                                                                   complex = false, desc = "Enable search input" },
    { method = "badge",                 args = "",                                                                                   complex = false, desc = "Display selections as badges" },
    { method = "preload",               args = "",                                                                                   complex = false, desc = "Preload all options on open" },
    { method = "native",                args = "(false)",                                                                            complex = false, desc = "Use custom select UI (not native)" },
    { method = "required",              args = "",                                                                                   complex = false, desc = "Mark as required" },
    { method = "options",               args = "(${1:options})",                                                                     complex = true,  desc = "Static array or callable of options" },
    { method = "relationship",          args = "('${1:relation}', '${2:titleColumn}')",                                              complex = true,  desc = "Populate from Eloquent relationship" },
    { method = "getSearchResultsUsing", args = "(fn (string \\$search): array => ${1:Model}::query()\n        ->where('${2:name}', 'like', \"%{\\$search}%\")\n        ->limit(50)\n        ->pluck('${2:name}', 'id')\n        ->all())",   complex = true, desc = "Dynamic async search closure" },
    { method = "getOptionLabelUsing",   args = "(fn (mixed \\$value): ?string => ${1:Model}::find(\\$value)?->${2:name})",           complex = true,  desc = "Custom label for a stored value" },
    { method = "getOptionLabelsUsing",  args = "(fn (array \\$values): array => ${1:Model}::whereIn('id', \\$values)->pluck('${2:name}', 'id')->all())", complex = true, desc = "Labels for multiple stored values" },
  },
  TextInput = {
    { method = "required",     args = "",                    complex = false, desc = "Mark as required" },
    { method = "email",        args = "",                    complex = false, desc = "Email validation" },
    { method = "numeric",      args = "",                    complex = false, desc = "Numeric keyboard hint" },
    { method = "password",     args = "",                    complex = false, desc = "Mask input" },
    { method = "maxLength",    args = "(${1:255})",           complex = false, desc = "Max character length" },
    { method = "minLength",    args = "(${1:3})",             complex = false, desc = "Min character length" },
    { method = "placeholder",  args = "('${1:}')",            complex = false, desc = "Placeholder text" },
    { method = "prefix",       args = "('${1:}')",            complex = false, desc = "Static prefix" },
    { method = "suffix",       args = "('${1:}')",            complex = false, desc = "Static suffix" },
    { method = "mask",         args = "('${1:}')",            complex = false, desc = "Input mask pattern" },
    { method = "unique",       args = "",                    complex = false, desc = "Unique validation" },
    { method = "rules",        args = "(['${1:}'])",          complex = true,  desc = "Custom validation rules" },
    { method = "autocomplete", args = "('${1:off}')",         complex = false, desc = "Autocomplete attribute" },
  },
  TextColumn = {
    { method = "sortable",         args = "",                     complex = false, desc = "Enable column sort" },
    { method = "searchable",       args = "",                     complex = false, desc = "Enable global search" },
    { method = "toggleable",       args = "",                     complex = false, desc = "User can hide column" },
    { method = "copyable",         args = "",                     complex = false, desc = "Copy to clipboard on click" },
    { method = "limit",            args = "(${1:50})",             complex = false, desc = "Truncate after N chars" },
    { method = "wrap",             args = "",                     complex = false, desc = "Wrap long text" },
    { method = "badge",            args = "",                     complex = false, desc = "Render as badge" },
    { method = "color",            args = "('${1:primary}')",      complex = false, desc = "Text color" },
    { method = "icon",             args = "('${1:heroicon-o-}')",  complex = false, desc = "Prefix icon" },
    { method = "money",            args = "('${1:AUD}')",          complex = false, desc = "Format as currency" },
    { method = "date",             args = "('${1:d/m/Y}')",        complex = false, desc = "Format as date" },
    { method = "dateTime",         args = "('${1:d/m/Y H:i}')",    complex = false, desc = "Format as datetime" },
    { method = "url",              args = "",                     complex = false, desc = "Render as hyperlink" },
    { method = "formatStateUsing", args = "(fn (${1:mixed} \\$state) => ${2:})", complex = true, desc = "Custom format closure" },
    { method = "state",            args = "(fn (${1:Model} \\$record) => ${2:})", complex = true, desc = "Derive value from record" },
  },
  BadgeColumn = {
    { method = "sortable",    args = "",                                                                               complex = false, desc = "Enable sort" },
    { method = "searchable",  args = "",                                                                               complex = false, desc = "Enable search" },
    { method = "colors",      args = "([\n        '${1:value}' => '${2:primary}',\n    ])",                             complex = true,  desc = "Value → color map" },
    { method = "icons",       args = "([\n        '${1:value}' => '${2:heroicon-o-}${3:}',\n    ])",                   complex = true,  desc = "Value → icon map" },
    { method = "formatStateUsing", args = "(fn (${1:mixed} \\$state) => ${2:})",                                       complex = true,  desc = "Custom format closure" },
  },
  Toggle = {
    { method = "required", args = "",                              complex = false, desc = "Mark as required" },
    { method = "inline",   args = "",                              complex = false, desc = "Inline label layout" },
    { method = "onIcon",   args = "('${1:heroicon-o-check}')",     complex = false, desc = "Icon when enabled" },
    { method = "offIcon",  args = "('${1:heroicon-o-x-mark}')",    complex = false, desc = "Icon when disabled" },
    { method = "onColor",  args = "('${1:success}')",              complex = false, desc = "Color when enabled" },
    { method = "offColor", args = "('${1:danger}')",               complex = false, desc = "Color when disabled" },
  },
  DatePicker = {
    { method = "required",          args = "",                   complex = false, desc = "Mark as required" },
    { method = "native",            args = "(false)",            complex = false, desc = "Use custom picker UI" },
    { method = "displayFormat",     args = "('${1:d/m/Y}')",     complex = false, desc = "Display date format" },
    { method = "format",            args = "('${1:Y-m-d}')",     complex = false, desc = "Storage format" },
    { method = "minDate",           args = "(now())",            complex = false, desc = "Minimum selectable date" },
    { method = "maxDate",           args = "(now())",            complex = false, desc = "Maximum selectable date" },
    { method = "weekStartsOnMonday", args = "",                  complex = false, desc = "Start week on Monday" },
  },
  FileUpload = {
    { method = "image",               args = "",                         complex = false, desc = "Image upload mode" },
    { method = "multiple",            args = "",                         complex = false, desc = "Allow multiple files" },
    { method = "disk",                args = "('${1:public}')",           complex = false, desc = "Storage disk" },
    { method = "directory",           args = "('${1:uploads}')",          complex = false, desc = "Upload directory" },
    { method = "maxSize",             args = "(${1:2048})",               complex = false, desc = "Max size in KB" },
    { method = "acceptedFileTypes",   args = "(['${1:image/*}'])",        complex = false, desc = "Accepted MIME types" },
    { method = "imagePreviewHeight",  args = "('${1:250}')",              complex = false, desc = "Preview height px" },
    { method = "downloadable",        args = "",                         complex = false, desc = "Show download button" },
    { method = "openable",            args = "",                         complex = false, desc = "Open in new tab" },
    { method = "reorderable",         args = "",                         complex = false, desc = "Drag to reorder" },
    { method = "deletable",           args = "(false)",                  complex = false, desc = "Allow file deletion" },
  },
  Repeater = {
    { method = "minItems",   args = "(${1:1})",   complex = false, desc = "Minimum items required" },
    { method = "maxItems",   args = "(${1:5})",   complex = false, desc = "Maximum items allowed" },
    { method = "reorderable", args = "",          complex = false, desc = "Allow drag reorder" },
    { method = "collapsible", args = "",          complex = false, desc = "Allow collapsing items" },
    { method = "collapsed",   args = "",          complex = false, desc = "Start collapsed" },
    { method = "addActionLabel", args = "('${1:Add item}')", complex = false, desc = "Custom add button label" },
    { method = "relationship", args = "('${1:relation}')",   complex = true,  desc = "Persist to relationship" },
  },
}

-- Return registry entries for a given scope.
-- For component scope, merges component-specific methods with common methods.
-- Common methods are appended after component-specific ones.
function M.get(scope, component)
  if scope == "component" and component then
    local entries = {}
    local specific = M.methods[component] or {}
    for _, e in ipairs(specific) do
      table.insert(entries, e)
    end
    for _, e in ipairs(M.methods.common) do
      -- Avoid duplicating methods the component already defines
      local found = false
      for _, existing in ipairs(specific) do
        if existing.method == e.method then found = true; break end
      end
      if not found then table.insert(entries, e) end
    end
    return entries
  end
  return M.containers[scope] or {}
end

return M
```

- [ ] **Step 2: Verify registry loads and returns data**

```bash
nvim --headless -c "lua local r = require('filament-scope.registry'); print(#r.get('table_columns', nil), #r.get('component', 'Select'))" -c "qa" 2>&1
```

Expected output: `10  17` (10 table columns, 17 Select methods including common ones)

- [ ] **Step 3: Commit**

```bash
git add lua/filament-scope/registry.lua
git commit -m "feat(filament-scope): add Filament v5 registry"
```

---

## Task 3: Context Detector

**Files:**
- Modify: `lua/filament-scope/context.lua`
- Create: `tests/filament-scope/context_spec.lua`

- [ ] **Step 1: Write failing tests**

`tests/filament-scope/context_spec.lua`:
```lua
local context = require("filament-scope.context")

local function make_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

describe("filament-scope context", function()
  it("returns table_columns when inside ->columns([", function()
    local buf = make_buf({
      "return $table",
      "    ->columns([",
      "        TextColumn::make('name'),",
      "    ",
    })
    local result = context.detect(buf, 4)
    assert.equal("table_columns", result.scope)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns table_filters when inside ->filters([", function()
    local buf = make_buf({
      "return $table",
      "    ->filters([",
      "    ",
    })
    local result = context.detect(buf, 3)
    assert.equal("table_filters", result.scope)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns form_fields when inside ->schema([ in a form function", function()
    local buf = make_buf({
      "public function form(Form $form): Form",
      "{",
      "    return $form->schema([",
      "        ",
    })
    local result = context.detect(buf, 4)
    assert.equal("form_fields", result.scope)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns infolist_entries when inside ->schema([ in an infolist function", function()
    local buf = make_buf({
      "public function infolist(Infolist $infolist): Infolist",
      "{",
      "    return $infolist->schema([",
      "        ",
    })
    local result = context.detect(buf, 4)
    assert.equal("infolist_entries", result.scope)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns component scope for Select::make chain", function()
    local buf = make_buf({
      "Select::make('status')",
      "    ->options(['active', 'inactive'])",
      "    ",
    })
    local result = context.detect(buf, 3)
    assert.equal("component", result.scope)
    assert.equal("Select", result.component)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns component scope for TextInput::make chain", function()
    local buf = make_buf({
      "TextInput::make('name')",
      "    ",
    })
    local result = context.detect(buf, 2)
    assert.equal("component", result.scope)
    assert.equal("TextInput", result.component)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("prefers component scope over container scope", function()
    -- Cursor is inside a Select chain that is itself inside ->columns([
    local buf = make_buf({
      "return $table->columns([",
      "    SelectColumn::make('status')",
      "        ",
    })
    local result = context.detect(buf, 3)
    assert.equal("component", result.scope)
    assert.equal("SelectColumn", result.component)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns unknown when no Filament scope found", function()
    local buf = make_buf({
      "public function boot()",
      "{",
      "    $this->loadRoutes();",
      "",
    })
    local result = context.detect(buf, 4)
    assert.equal("unknown", result.scope)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns actions scope for ->headerActions([", function()
    local buf = make_buf({
      "return $table->headerActions([",
      "    ",
    })
    local result = context.detect(buf, 2)
    assert.equal("actions", result.scope)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
nvim --headless -u tests/filament-scope/minimal_init.lua \
  -c "PlenaryBustedFile tests/filament-scope/context_spec.lua" \
  -c "qa" 2>&1
```

Expected: all tests FAIL (context.detect returns `{scope="unknown"}` for everything)

- [ ] **Step 3: Implement context.lua**

Replace `lua/filament-scope/context.lua` with:

```lua
local M = {}

-- Scan up to 50 lines backward from lnum (1-based) and return the innermost
-- Filament builder scope the cursor is inside.
-- Returns: { scope: string, component: string|nil }
function M.detect(bufnr, lnum)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  lnum = lnum or vim.api.nvim_win_get_cursor(0)[1]

  local start_line = math.max(0, lnum - 51)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, lnum, false)

  -- Search from cursor line upward (lines is 1-indexed, last element = line just above cursor)
  for i = #lines, 1, -1 do
    local line = lines[i]

    -- Component-level: UpperCaseClass::make( — highest priority
    local component = line:match("(%u%w+)::make%s*%(")
    if component then
      return { scope = "component", component = component }
    end

    -- ->columns([
    if line:match("%->columns%s*%(%s*%[") then
      return { scope = "table_columns" }
    end

    -- ->filters([
    if line:match("%->filters%s*%(%s*%[") then
      return { scope = "table_filters" }
    end

    -- ->actions([ / ->headerActions([ / ->bulkActions([
    if line:match("%->h?e?a?d?e?r?A?c?t?i?o?n?s?%s*%(%s*%[")
      or line:match("%->bulkActions%s*%(%s*%[")
      or line:match("%->actions%s*%(%s*%[")
    then
      return { scope = "actions" }
    end

    -- ->schema([ — needs disambiguation between Form and Infolist
    if line:match("%->schema%s*%(%s*%[") then
      return M._disambiguate_schema(lines, i)
    end
  end

  return { scope = "unknown" }
end

-- Scan upward from schema_line_idx in lines[] to find the enclosing function
-- signature and read its type hint to distinguish Form from Infolist.
function M._disambiguate_schema(lines, schema_line_idx)
  for i = schema_line_idx, 1, -1 do
    local line = lines[i]
    if line:match("function") then
      if line:match("Infolist %$") then
        return { scope = "infolist_entries" }
      end
      -- Form $form or no type hint → default form
      return { scope = "form_fields" }
    end
  end
  return { scope = "form_fields" }
end

return M
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
nvim --headless -u tests/filament-scope/minimal_init.lua \
  -c "PlenaryBustedFile tests/filament-scope/context_spec.lua" \
  -c "qa" 2>&1
```

Expected: `8 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add lua/filament-scope/context.lua tests/filament-scope/context_spec.lua
git commit -m "feat(filament-scope): context detector with tests"
```

---

## Task 4: Indexer

**Files:**
- Modify: `lua/filament-scope/indexer.lua`
- Create: `tests/filament-scope/indexer_spec.lua`

- [ ] **Step 1: Write failing tests**

`tests/filament-scope/indexer_spec.lua`:
```lua
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
nvim --headless -u tests/filament-scope/minimal_init.lua \
  -c "PlenaryBustedFile tests/filament-scope/indexer_spec.lua" \
  -c "qa" 2>&1
```

Expected: tests FAIL (stubs return empty values)

- [ ] **Step 3: Implement indexer.lua**

Replace `lua/filament-scope/indexer.lua` with:

```lua
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
    end

    -- Detect method call on current chain: ->methodName(args)
    if current_component then
      local method, raw_args = line:match("%->(%w+)%s*%(([^)]*)")
      if method then
        -- Normalise args: trim whitespace
        local args = (raw_args or ""):gsub("^%s*(.-)%s*$", "%1")
        if not result[current_component] then
          result[current_component] = {}
        end
        if not result[current_component][method] then
          result[current_component][method] = {}
        end
        local tbl = result[current_component][method]
        tbl[args] = (tbl[args] or 0) + 1
      end

      -- End of chain: line ends with ; and no further -> on this line
      if line:match(";") and not line:match("^%s*%->") then
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
    { "rg", "--type", "php", "-l", "", filament_dir },
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
nvim --headless -u tests/filament-scope/minimal_init.lua \
  -c "PlenaryBustedFile tests/filament-scope/indexer_spec.lua" \
  -c "qa" 2>&1
```

Expected: `9 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add lua/filament-scope/indexer.lua tests/filament-scope/indexer_spec.lua
git commit -m "feat(filament-scope): indexer with parse + frequency logic"
```

---

## Task 5: Inserter

**Files:**
- Modify: `lua/filament-scope/inserter.lua`
- Create: `tests/filament-scope/inserter_spec.lua`

- [ ] **Step 1: Write failing tests**

`tests/filament-scope/inserter_spec.lua`:
```lua
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
nvim --headless -u tests/filament-scope/minimal_init.lua \
  -c "PlenaryBustedFile tests/filament-scope/inserter_spec.lua" \
  -c "qa" 2>&1
```

Expected: tests FAIL (`build_insert_text` returns `""`)

- [ ] **Step 3: Implement inserter.lua**

Replace `lua/filament-scope/inserter.lua` with:

```lua
local M = {}

-- Build the text to insert for a registry entry given frequency index data.
--
-- For component method entries (have `method` field):
--   - complex=true  → always use the args template as-is (full snippet)
--   - complex=false, dominant index arg → ->method(top_arg) pre-filled
--   - complex=false, no dominant arg    → ->method(args_template) with placeholders
--   - complex=false, args=""            → ->method()
--
-- For container entries (have `snippet` field):
--   → return the snippet string directly
--
-- Returns a string suitable for vim.snippet.expand().
function M.build_insert_text(entry, index_data)
  -- Container entry
  if entry.snippet then
    return entry.snippet
  end

  -- Component method entry
  local method = entry.method
  local args   = entry.args   -- snippet template string including parens, or ""
  local complex = entry.complex

  if complex then
    return "->" .. method .. args
  end

  -- Simple method: try to pre-fill from index
  local top_arg = index_data and index_data.top_arg or ""

  if top_arg ~= "" then
    -- Use the dominant arg directly (strip placeholder if present)
    return "->" .. method .. "(" .. top_arg .. ")"
  end

  if args == "" then
    return "->" .. method .. "()"
  end

  -- No dominant arg, use the template (may contain ${1:default})
  return "->" .. method .. args
end

-- Insert text at the current cursor position using vim.snippet.expand().
-- Falls back to plain insertion if text has no snippet syntax.
function M.insert(text)
  if text == "" then return end

  -- If text contains snippet syntax, use snippet expansion
  if text:find("%${%d") then
    vim.snippet.expand(text)
  else
    -- Plain insertion at cursor
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
    local new_line = line:sub(1, col) .. text .. line:sub(col + 1)
    vim.api.nvim_buf_set_lines(0, row - 1, row, false, { new_line })
    vim.api.nvim_win_set_cursor(0, { row, col + #text })
  end
end

return M
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
nvim --headless -u tests/filament-scope/minimal_init.lua \
  -c "PlenaryBustedFile tests/filament-scope/inserter_spec.lua" \
  -c "qa" 2>&1
```

Expected: `8 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add lua/filament-scope/inserter.lua tests/filament-scope/inserter_spec.lua
git commit -m "feat(filament-scope): inserter with smart pre-fill logic"
```

---

## Task 6: Picker

**Files:**
- Modify: `lua/filament-scope/picker.lua`

No unit tests — Telescope picker requires interactive Neovim. Verified manually in Task 8.

- [ ] **Step 1: Implement picker.lua**

Replace `lua/filament-scope/picker.lua` with:

```lua
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
  local ok_telescope, pickers   = pcall(require, "telescope.pickers")
  local ok_finders,  finders    = pcall(require, "telescope.finders")
  local ok_conf,     conf_mod   = pcall(require, "telescope.config")
  local ok_actions,  actions    = pcall(require, "telescope.actions")
  local ok_state,    action_state = pcall(require, "telescope.actions.state")

  if not (ok_telescope and ok_finders and ok_conf and ok_actions and ok_state) then
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
    previewer = require("telescope.previewers").new_buffer_previewer({
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
        local inserter_mod = require("filament-scope.inserter")
        local preview_text = inserter_mod.build_insert_text(e, idata)
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
```

- [ ] **Step 2: Commit**

```bash
git add lua/filament-scope/picker.lua
git commit -m "feat(filament-scope): Telescope picker with freq-sorted entries"
```

---

## Task 7: Wire init.lua

**Files:**
- Modify: `lua/filament-scope/init.lua`

- [ ] **Step 1: Implement init.lua**

Replace `lua/filament-scope/init.lua` with:

```lua
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

local _debounce_timer = nil

local function trigger_index(root)
  if _debounce_timer then
    _debounce_timer:stop()
    _debounce_timer:close()
  end
  _debounce_timer = vim.uv.new_timer()
  _debounce_timer:start(2000, 0, vim.schedule_wrap(function()
    require("filament-scope.indexer").run_async(root)
    _debounce_timer = nil
  end))
end

function M.setup()
  local context  = require("filament-scope.context")
  local picker   = require("filament-scope.picker")
  local indexer  = require("filament-scope.indexer")

  -- Load on-disk index immediately (non-blocking read from JSON)
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      local root = project_root()
      if root then
        indexer.load(root)
        indexer.run_async(root)
      end
    end,
  })

  -- Re-index on PHP file save (debounced 2s)
  vim.api.nvim_create_autocmd("BufWritePost", {
    pattern = "*.php",
    callback = function()
      local root = project_root()
      if root then trigger_index(root) end
    end,
  })

  -- Picker trigger: normal mode
  vim.keymap.set("n", "<leader>fp", function()
    local ctx = context.detect()
    picker.open(ctx)
  end, { desc = "Filament picker" })

  -- Picker trigger: insert mode (returns to insert after selection)
  vim.keymap.set("i", "<leader>fp", function()
    local ctx = context.detect()
    picker.open(ctx)
  end, { desc = "Filament picker" })

  -- :FilamentIndex — manual full re-index
  vim.api.nvim_create_user_command("FilamentIndex", function()
    local root = project_root()
    if not root then
      vim.notify("filament-scope: no Laravel project root found (artisan not found)", vim.log.levels.WARN)
      return
    end
    vim.notify("filament-scope: indexing " .. root .. "/app/Filament ...", vim.log.levels.INFO)
    indexer.run_async(root)
  end, { desc = "Rebuild filament-scope index" })

  -- :FilamentIndexStatus — show last index stats
  vim.api.nvim_create_user_command("FilamentIndexStatus", function()
    local cache = indexer._cache
    local component_count = 0
    local method_count = 0
    for _, methods in pairs(cache) do
      component_count = component_count + 1
      for _ in pairs(methods) do method_count = method_count + 1 end
    end
    vim.notify(
      string.format("filament-scope index: %d components, %d method entries",
        component_count, method_count),
      vim.log.levels.INFO
    )
  end, { desc = "Show filament-scope index status" })
end

return M
```

- [ ] **Step 2: Reload Neovim and verify plugin loads without errors**

Start Neovim normally and check:
```vim
:messages
```

Expected: no errors, no "filament-scope" error lines.

- [ ] **Step 3: Verify user commands are registered**

```vim
:FilamentIndexStatus
```

Expected: notification `filament-scope index: 0 components, 0 method entries` (no project open yet)

- [ ] **Step 4: Commit**

```bash
git add lua/filament-scope/init.lua
git commit -m "feat(filament-scope): wire init.lua with keybindings and autocmds"
```

---

## Task 8: Smoke Test

Manual end-to-end verification. No automation — requires a real Filament project.

- [ ] **Step 1: Open a Filament Resource file**

Open any file under `app/Filament/` in a Laravel project that uses Filament v5. Place cursor inside `->columns([`:

```php
return $table
    ->columns([
        |   // cursor here
    ])
```

- [ ] **Step 2: Trigger picker in table_columns scope**

Press `<leader>fp`. Expected:
- Telescope opens titled `Filament: table columns`
- Entries show: TextColumn, BadgeColumn, IconColumn, etc.
- Most-used ones (if index has run) show `[×N]` counts

- [ ] **Step 3: Select TextColumn and verify insertion**

Select `TextColumn` and press Enter. Expected:
- `TextColumn::make('${1:column}')` inserted with cursor inside the string placeholder

- [ ] **Step 4: Trigger picker in component scope**

Place cursor on a line after `Select::make('field')`:

```php
Select::make('status')
    |   // cursor here
```

Press `<leader>fp`. Expected:
- Telescope opens titled `Filament: Select methods`
- `->badge()`, `->multiple()`, `->searchable()`, etc. listed
- If index has run, your most-used ones show counts and pre-filled args

- [ ] **Step 5: Trigger picker in form_fields scope**

Place cursor inside `->schema([` inside a `form(Form $form)` method. Press `<leader>fp`. Expected:
- `Filament: form fields` picker with TextInput, Select, Toggle, etc.

- [ ] **Step 6: Run :FilamentIndex and verify count increases**

```vim
:FilamentIndex
```

Wait 2-3 seconds, then:

```vim
:FilamentIndexStatus
```

Expected: `filament-scope index: N components, M method entries` with N and M > 0

- [ ] **Step 7: Re-open the Select picker and verify frequency data**

After indexing, press `<leader>fp` inside a Select chain. Expected:
- Most-used methods show `[×N]` counts
- `->badge()` shows your most common arg pre-filled (e.g. `false`) if you always use it that way

- [ ] **Step 8: Final commit**

```bash
git add -A
git commit -m "feat(filament-scope): complete v1 implementation"
```

---

## Self-Review Notes

- **Spec coverage:** All five components covered (context ✓, registry ✓, indexer ✓, picker ✓, inserter ✓). Keybindings (`<leader>fp`) ✓. User commands (`:FilamentIndex`, `:FilamentIndexStatus`) ✓. Debounced re-index on save ✓. Per-project JSON cache ✓.
- **No placeholders:** All code steps contain complete, runnable code.
- **Type consistency:** `index_data` shape `{ top_arg, count }` defined in `indexer.get()` (Task 4) and consumed identically in `picker.lua` (Task 6) and `inserter.lua` (Task 5). `ctx` shape `{ scope, component }` defined in `context.detect()` (Task 3) and consumed in `picker.open()` (Task 6) and `init.lua` (Task 7).
