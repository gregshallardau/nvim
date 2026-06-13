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
