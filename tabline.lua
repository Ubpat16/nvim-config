local M = {}

local function current_workspace_tabs()
  local tabs_module = require("config.tabs")
  if type(tabs_module.ensure_workspace_consistent) == "function" then
    pcall(tabs_module.ensure_workspace_consistent)
  end
  return tabs_module.current_workspace_tabs()
end

local function tab_title(tab, workspace_index, current)
  local tab_number = vim.api.nvim_tabpage_get_number(tab)
  local label = " Tab " .. tostring(workspace_index) .. " "
  if current then
    return "%#TabLineSel#" .. "%" .. tab_number .. "T" .. label
  end

  return "%#TabLine#" .. "%" .. tab_number .. "T" .. label
end

function M.bufferline_workspace_tabs()
  local current = vim.api.nvim_get_current_tabpage()
  local items = {}

  for index, tab in ipairs(current_workspace_tabs()) do
    local tab_number = vim.api.nvim_tabpage_get_number(tab)
    items[#items + 1] = {
      text = "%" .. tab_number .. "T Tab " .. index .. " %T",
      link = tab == current and "TabLineSel" or "TabLine",
    }
  end

  return items
end

function M.render()
  local tabs = current_workspace_tabs()
  local current = vim.api.nvim_get_current_tabpage()

  if #tabs == 0 then
    return "%#TabLineFill#"
  end

  local chunks = { "%#TabLineFill#" }
  for index, tab in ipairs(tabs) do
    chunks[#chunks + 1] = tab_title(tab, index, tab == current)
  end

  chunks[#chunks + 1] = "%#TabLineFill#%T"
  return table.concat(chunks)
end

return M
