-- greg/ctxslice/health.lua — `:checkhealth greg.ctxslice`
--
-- The nvim-native answer to "why did my slice come back empty". Verifies every
-- deterministic-retrieval dependency the engine relies on is present, and that
-- the engine scripts themselves are on disk and executable.

local M = {}

local health = vim.health or require("health")
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error_ = health.error or health.report_error
local start = health.start or health.report_start

-- Mirror the default in greg/ctxslice.lua without hard-requiring it.
local bin_dir = vim.fn.stdpath("config") .. "/bin"

-- Report a required external command, capturing its first version line.
local function check_cmd(cmd, why, min_hint)
  if vim.fn.executable(cmd) == 1 then
    local out = vim.fn.system({ cmd, "--version" })
    local first = vim.split(out or "", "\n", { trimempty = true })[1] or ""
    ok(("%s found — %s"):format(cmd, first))
  else
    error_(("%s NOT found — %s"):format(cmd, why), min_hint)
  end
end

local function check_script(name)
  local path = bin_dir .. "/" .. name
  if vim.fn.filereadable(path) == 1 then
    ok(("engine script present: %s"):format(path))
  else
    error_(("engine script missing: %s"):format(path),
      { "Ensure the ctxslice bin/ directory ships with this config." })
  end
end

function M.check()
  start("greg.ctxslice — required tools")
  check_cmd("bash", "the engine entry points are bash scripts")
  check_cmd("rg", "callers/index scans use ripgrep", { "Install ripgrep: https://github.com/BurntSushi/ripgrep" })
  check_cmd("php", "callee extraction + the symbol index need the PHP CLI")
  check_cmd("jq", "the slice logic parses the JSON index with jq", { "Install jq: https://jqlang.github.io/jq" })

  start("greg.ctxslice — optional accelerators")
  if vim.fn.executable("ctags") == 1 then
    local out = vim.fn.system({ "ctags", "--version" })
    local first = vim.split(out or "", "\n", { trimempty = true })[1] or ""
    if first:lower():find("universal") then
      ok("universal-ctags found — " .. first)
      warn("Note: through 5.9.x the bundled PHP parser does not emit end lines, "
        .. "so ctxslice uses its own PHP tokenizer index (bin/phpindex.php) for "
        .. "accurate symbol ranges regardless.")
    else
      warn("ctags found but is not universal-ctags — ctxslice uses bin/phpindex.php instead")
    end
  else
    ok("ctags not required — bin/phpindex.php provides the symbol index natively")
  end

  start("greg.ctxslice — engine scripts")
  check_script("ctxslice.sh")
  check_script("filament-slice.sh")
  check_script("phpindex.php")
  check_script("callees.php")

  start("greg.ctxslice — project")
  local file = vim.api.nvim_buf_get_name(0)
  local from = file ~= "" and vim.fn.fnamemodify(file, ":p:h") or vim.uv.cwd()
  local found = vim.fs.find({ "artisan", "composer.json", ".git" }, { path = from, upward = true })
  if found and #found > 0 then
    ok("project root: " .. vim.fn.fnamemodify(found[1], ":h"))
  else
    warn("no project root marker (artisan/composer.json/.git) found above "
      .. from .. " — slices will index the current working directory")
  end
end

return M
