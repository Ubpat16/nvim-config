local M = {}

local copilot_icons = {
  InProgress = "**",
  Warning = "*!",
  Error = "!!",
}

function M.has_copilot_status()
  local ok, api = pcall(require, "copilot.api")
  return ok and api.status ~= nil and api.status.data ~= nil
end

function M.copilot_status()
  local ok, api = pcall(require, "copilot.api")
  if not ok or not api.status or not api.status.data then
    return ""
  end

  local status = api.status.data.status
  if not status or status == "" then
    return ""
  end

  return copilot_icons[status] or (" " .. status)
end

return M
