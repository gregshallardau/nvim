-- lua/config/keymaps.lua
local map = vim.keymap.set

local function project_root()
  local file = vim.api.nvim_buf_get_name(0)
  local start = file ~= "" and vim.fn.fnamemodify(file, ":p:h") or vim.uv.cwd()
  local found = vim.fs.find({ "artisan", "composer.json", ".git" }, { path = start, upward = true })
  if found and #found > 0 then
    return vim.fn.fnamemodify(found[1], ":h")
  end
  return vim.fn.expand("~/platform")
end

map("n", "<leader>w", "<cmd>w<cr>", { desc = "Write" })
map("n", "<leader>q", "<cmd>q<cr>", { desc = "Quit" })
map("n", "<leader>H", function() Snacks.dashboard() end, { desc = "Home dashboard" })

map("n", "<leader>ff", function() require("telescope.builtin").find_files() end, { desc = "Find files" })
map("n", "<leader>fg", function() require("telescope.builtin").live_grep() end, { desc = "Live grep" })
map("n", "<leader>fb", function() require("telescope.builtin").buffers() end, { desc = "Buffers" })
map("n", "<leader>fr", function() require("telescope.builtin").oldfiles() end, { desc = "Recent files" })

map("n", "gd", function() require("telescope.builtin").lsp_definitions({ reuse_win = true }) end, { desc = "Definitions" })
map("n", "gr", function() require("telescope.builtin").lsp_references() end, { desc = "References" })
map("n", "<leader>ss", function() require("telescope.builtin").lsp_document_symbols() end, { desc = "Document symbols" })
map("n", "<leader>sS", function() require("telescope.builtin").lsp_workspace_symbols() end, { desc = "Workspace symbols" })
map("n", "K", vim.lsp.buf.hover, { desc = "Hover docs" })
map("i", "<C-k>", vim.lsp.buf.signature_help, { desc = "Signature help" })

map("n", "<leader>e", vim.diagnostic.open_float, { desc = "Line diagnostics" })
map("n", "[d", function() vim.diagnostic.jump({ count = -1, float = true }) end, { desc = "Previous diagnostic" })
map("n", "]d", function() vim.diagnostic.jump({ count = 1, float = true }) end, { desc = "Next diagnostic" })
map("n", "[e", function() vim.diagnostic.jump({ count = -1, float = true, severity = vim.diagnostic.severity.ERROR }) end, { desc = "Previous error" })
map("n", "]e", function() vim.diagnostic.jump({ count = 1, float = true, severity = vim.diagnostic.severity.ERROR }) end, { desc = "Next error" })
map("n", "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", { desc = "Diagnostics list" })

map("n", "<leader>qf", function()
  vim.lsp.buf.code_action({
    apply = true,
    filter = function(action)
      return action.isPreferred == true
    end,
  })
end, { desc = "Apply preferred quick-fix" })
map("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "Code action" })

map("n", "<leader>uh", function()
  vim.lsp.inlay_hint.enable(
    not vim.lsp.inlay_hint.is_enabled({ bufnr = 0 }),
    { bufnr = 0 }
  )
end, { desc = "Toggle inlay hints" })

map("n", "<leader>lp", function()
  local root = project_root()
  local cmd = vim.env.PINT_CMD or "./vendor/bin/pint --config=.pint.json --dirty"
  vim.cmd("botright 12split")
  vim.fn.termopen({ "bash", "-lc", "cd " .. vim.fn.shellescape(root) .. " && " .. cmd }, { cwd = root })
  vim.cmd("startinsert")
end, { desc = "Run Pint dirty" })
