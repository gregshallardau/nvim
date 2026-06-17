-- Show more path context in buffer tabs for markdown files.
-- LazyVim's default bufferline shows only the filename, which isn't enough
-- when you have many files spread across a deep project hierarchy.
return {
  {
    "akinsho/bufferline.nvim",
    opts = {
      options = {
        max_name_length   = 60,  -- allow long paths before bufferline clips them
        tab_size          = 20,  -- minimum tab width
        name_formatter = function(buf)
          if not buf.path or not buf.path:match("%.md$") then
            return nil  -- use bufferline's default for non-markdown files
          end
          local parts = {}
          for part in buf.path:gmatch("[^/]+") do
            table.insert(parts, part)
          end
          -- Show up to 4 trailing path components:
          -- e.g. clients/company-x/templates/policy-documents.md
          local n = math.min(4, #parts)
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
