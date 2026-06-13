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
    { name = "QueryBuilder",  snippet = "QueryBuilder::make()\n    ->constraints([\n        ${1:}\n    ])", desc = "Advanced query builder" },
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
-- args = "" means no args; inserter must append "()" to produce ->method().
-- args string is everything including parens when non-empty.
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
    { method = "minDate",           args = "(${1:now()})",        complex = false, desc = "Minimum selectable date" },
    { method = "maxDate",           args = "(${1:now()})",        complex = false, desc = "Maximum selectable date" },
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
