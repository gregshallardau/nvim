local M = {
  _providers = {},
  _setup = false,
}

function M.register(provider)
  assert(type(provider) == "table", "project-intel provider must be a table")
  assert(type(provider.id) == "string", "project-intel provider requires id")
  M._providers[provider.id] = provider
end

function M.unregister(id)
  M._providers[id] = nil
end

function M.get(id)
  return M._providers[id]
end

function M.status()
  local result = {}
  for id, provider in pairs(M._providers) do
    local status = type(provider.status) == "function"
      and provider.status()
      or {}
    status.id = id
    result[id] = status
  end
  return result
end

function M.refresh_all()
  for _, provider in pairs(M._providers) do
    if type(provider.refresh) == "function" then
      provider.refresh()
    end
  end
end

function M.setup()
  if M._setup then return end
  M._setup = true

  vim.api.nvim_create_user_command("ProjectIntelStatus", function()
    local status = M.status()
    if vim.tbl_isempty(status) then
      vim.notify("project-intel: no providers registered", vim.log.levels.INFO)
      return
    end
    vim.notify(vim.inspect(status), vim.log.levels.INFO)
  end, { desc = "Show project-intel provider status" })

  vim.api.nvim_create_user_command("ProjectIntelRefresh", function()
    M.refresh_all()
  end, { desc = "Refresh all project-intel providers" })
end

return M
