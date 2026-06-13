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

    -- Component-level: UpperCaseClass::make( — highest priority.
    -- Skip if the line ends with a comma, meaning this component is a
    -- completed entry inside a container (not an open chain at cursor).
    local component = line:match("(%u%w+)::make%s*%(")
    if component and not line:match(",%s*$") then
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
    if line:match("%->headerActions%s*%(%s*%[")
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
