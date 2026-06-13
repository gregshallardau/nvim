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

  it("returns form_fields when cursor is after a completed multi-line Select chain", function()
    local buf = make_buf({
      "public function form(Form $form): Form",
      "{",
      "    return $form->schema([",
      "        Select::make('status')",
      "            ->label('Status')",
      "            ->options(['active', 'inactive']),",
      "        ",
    })
    local result = context.detect(buf, 7)
    assert.equal("form_fields", result.scope)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("returns actions for ->bulkActions([", function()
    local buf = make_buf({
      "return $table->bulkActions([",
      "    ",
    })
    local result = context.detect(buf, 2)
    assert.equal("actions", result.scope)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
