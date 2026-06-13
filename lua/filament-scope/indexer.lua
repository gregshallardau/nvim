local M = {}
M._cache = {}
function M.parse_file(lines) return {} end
function M.compute_top_arg(arg_counts) return "", 0 end
function M.get(component, method) return { top_arg = "", count = 0 } end
function M.run_async(project_root) end
return M
