-- Show more path context in buffer tabs for markdown files.
-- LazyVim's default bufferline shows only the filename, which isn't enough
-- when you have many files spread across a deep project hierarchy.
return {
  {
    "akinsho/bufferline.nvim",
    opts = {
      options = {
        name_formatter = function(buf)
          if not buf.path or not buf.path:match("%.md$") then
            return nil  -- use bufferline's default for non-markdown files
          end
          local parts = {}
          for part in buf.path:gmatch("[^/]+") do
            table.insert(parts, part)
          end
          -- Show up to 3 trailing path components so you can see
          -- client / document-type / filename without truncation.
          local n = math.min(3, #parts)
          local out = {}
          for i = #parts - n + 1, #parts do
            table.insert(out, parts[i])
          end
          return table.concat(out, "/")
        end,
      },
    },
  },
}
