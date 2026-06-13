# filament-scope — Design Spec
_2026-06-13_

## Goal

A local Neovim plugin that detects which Filament v5 builder scope the cursor is inside, pops a Telescope picker showing contextually relevant methods/types ranked by frequency in your own codebase, and inserts a smart snippet pre-filled with your most-used argument patterns. Zero AI, zero tokens — pure ripgrep indexing and frequency statistics.

**Primary use case:** Scaffold Filament Resources, Forms, Tables, and Infolists faster by eliminating the lookup → type → remember-the-arg loop.

---

## Architecture

Five single-purpose Lua modules, wired together on a keypress:

```
<leader>fp (normal + insert mode)
      │
      ▼
context.lua        ← where is my cursor? → {scope, component}
      │
      ├── registry.lua    ← Filament v5 method list for that scope
      └── indexer.lua     ← frequency table from your codebase
            │
            ▼
      picker.lua          ← Telescope menu, freq-sorted
            │
            ▼
      inserter.lua        ← smart snippet with your args pre-filled
```

**File layout:**
```
lua/filament-scope/
  init.lua       -- setup(), keybindings, autocmds
  context.lua    -- detect_cursor_context()
  registry.lua   -- Filament v5 API per scope
  indexer.lua    -- async ripgrep parser + JSON cache
  picker.lua     -- Telescope custom picker
  inserter.lua   -- LuaSnip / vim.snippet insertion
```

Plugin registered in `lua/plugins/` as a local plugin spec.

---

## Component 1: Indexer

### Trigger
- On project open: detects `artisan` file in project root → runs index async
- On PHP file save: debounced 2s re-index

### Process
1. `rg --type php -l "" app/Filament/` to get file list
2. For each file, extract all `ComponentClass::make(...)` chains via regex
3. For each chain, record: component name, method name, argument string
4. Aggregate into frequency table
5. Write to `.nvim/filament-index.json` in project root (gitignored)

### Index format
```json
{
  "Select": {
    "multiple":              { "top_arg": "",                        "count": 7  },
    "badge":                 { "top_arg": "false",                   "count": 12 },
    "options":               { "top_arg": "Helper::GetUserOptions()", "count": 8  },
    "getSearchResultsUsing": { "top_arg": "closure",                 "count": 3  }
  },
  "TextInput": {
    "required":  { "top_arg": "",    "count": 23 },
    "maxLength": { "top_arg": "255", "count": 14 }
  }
}
```

`top_arg` is the most frequent argument string seen for that method. If no single arg dominates (>50% of uses), `top_arg` is `""` and the inserter falls back to a placeholder.

### Per-project isolation
Each Laravel project writes its own `.nvim/filament-index.json`. The indexer detects the project root via `artisan` file, same as the existing `project_root()` helper in `keymaps.lua`.

---

## Component 2: Context Detector

### Strategy
Scans backwards from the cursor line by line (max 50 lines) using Lua string patterns. Returns the innermost matching scope.

### Scope detection rules (priority order)

| Pattern found above cursor | Scope returned |
|---|---|
| `SomeClass::make(` on current or recent chain | `{scope="component", component="SomeClass"}` |
| `->columns([` | `{scope="table_columns"}` |
| `->filters([` | `{scope="table_filters"}` |
| `->actions([` or `->headerActions([` or `->bulkActions([` | `{scope="actions"}` |
| `->schema([` + function sig contains `Form $form` | `{scope="form_fields"}` |
| `->schema([` + function sig contains `Infolist $infolist` | `{scope="infolist_entries"}` |
| No match | `{scope="unknown"}` → show generic Filament component list |

### Form vs Infolist disambiguation
When `->schema([` is found, continue scanning upward to the nearest `function` line. Read the parameter type hints:
- `Form $form` → form_fields scope
- `Infolist $infolist` → infolist_entries scope

### Component-level detection
If the cursor is inside a method chain (lines above contain `SomeClass::make(`), extract the class name and return component scope. This takes priority over container scope — being inside `Select::make(...)->` shows Select methods, not form field types.

---

## Component 3: Registry

Hard-coded Filament v5 API. Stored as Lua tables in `registry.lua`.

### Container scopes (what to add inside `[...]`)

**table_columns:**
TextColumn, BadgeColumn, IconColumn, ImageColumn, CheckboxColumn, ToggleColumn, ColorColumn, SelectColumn, TagsColumn, TextInputColumn

**form_fields:**
TextInput, Select, Toggle, DatePicker, DateTimePicker, TimePicker, FileUpload, RichEditor, MarkdownEditor, Repeater, Fieldset, Section, Grid, Tabs, Wizard, ColorPicker, KeyValue, TagsInput, Checkbox, Radio, CheckboxList

**infolist_entries:**
TextEntry, BadgeEntry, ImageEntry, IconEntry, ColorEntry, KeyValueEntry, RepeatableEntry, Section, Fieldset, Grid, Tabs

**table_filters:**
SelectFilter, TernaryFilter, Filter, QueryBuilder

**actions:**
Action, BulkAction, HeaderAction, CreateAction, EditAction, DeleteAction, ViewAction, ForceDeleteAction, RestoreAction, ExportAction, ImportAction

### Component method scopes (what to chain on a component)

Each entry: `{ method, args_template, complex, description }`

Example — Select methods:
```lua
{ method="multiple",              args="",                          complex=false, desc="Allow multiple selections" },
{ method="searchable",            args="",                          complex=false, desc="Enable search input" },
{ method="badge",                 args="",                          complex=false, desc="Display as badge" },
{ method="options",               args="(${1:options})",            complex=true,  desc="Static options array or callable" },
{ method="relationship",          args="('${1:rel}', '${2:col}')",  complex=true,  desc="Populate from relationship" },
{ method="getSearchResultsUsing", args="(fn (string $search) ...)", complex=true,  desc="Dynamic search closure" },
{ method="getOptionLabelUsing",   args="(fn (mixed $value) ...)",   complex=true,  desc="Custom label for stored value" },
{ method="preload",               args="",                          complex=false, desc="Preload all options" },
{ method="native",                args="(false)",                   complex=false, desc="Use custom select UI" },
```

Full registry covers all major Filament v5 components. Can be extended without touching other modules.

---

## Component 4: Picker

Telescope custom picker built with `telescope.pickers.new`.

### Entry format
```
->badge()          [×12]   false
->options()        [×8]    Helper::GetUserOptions()
->multiple()       [×7]
->searchable()     [×3]
->preload()                              ← not yet used, freq=0
```

### Sorting
1. Entries in the frequency index → sorted by count DESC
2. Entries in registry but not yet used → appended alphabetically

### Preview
Telescope preview pane shows:
- Method signature
- Your most common usage (from index)
- One-line description from registry

### Fallback
If index doesn't exist yet (first open), picker shows registry entries only with no frequency data. Prompts user to `:FilamentIndex` to trigger manual index build.

---

## Component 5: Inserter

Called with the selected entry. Decides insertion strategy:

| Condition | Action |
|---|---|
| `complex=false`, no args | Insert `->method()` literally |
| `complex=false`, top_arg dominant (>50%) | Insert `->method(top_arg)` pre-filled |
| `complex=false`, no dominant arg | Insert `->method(${1:})` as snippet with placeholder |
| `complex=true` | Insert full LuaSnip snippet with named placeholders |

Uses `vim.snippet.expand()` (Neovim 0.10+ built-in) for simple cases, LuaSnip for complex multi-placeholder closures.

### Complex snippet example — getSearchResultsUsing
```php
->getSearchResultsUsing(fn (string $search): array => ${1:Model}::query()
    ->where('${2:name}', 'like', "%{$search}%")
    ->limit(50)
    ->pluck('${3:name}', 'id')
    ->all())
```

### Post-insert
Sets a buffer-local flag. On next file save, the re-index includes this file immediately (bypasses the 2s debounce once).

---

## Keybindings

| Key | Mode | Action |
|---|---|---|
| `<leader>fp` | normal | Open filament-scope picker |
| `<leader>fp` | insert | Open filament-scope picker (returns to insert after) |
| `:FilamentIndex` | command | Manually trigger full re-index |
| `:FilamentIndexStatus` | command | Show last index time + entry count |

---

## What This Is Not

- Not a general PHP autocomplete (Intelephense handles that)
- Not AI-powered — purely local grep + statistics
- Not a replacement for LSP completions — it's a deliberate scaffolding tool, invoked intentionally

---

## Out of Scope (v1)

- Filament plugins/third-party components (SpatieLaravelPermissionsPlugin etc.) — registry can be extended manually
- Multi-argument frequency tracking (tracks top single arg only, not arg combinations)
- Cross-project frequency aggregation
- Auto-import of component classes (assume IDE helper / Intelephense handles this)
