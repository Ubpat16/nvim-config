local M = {}

local function tab_title(tab, index, current)
  local label = " Tab " .. tostring(index) .. " "
  if current then
    return "%#TabLineSel#" .. "%" .. index .. "T" .. label
  end

  return "%#TabLine#" .. "%" .. index .. "T" .. label
end

function M.render()
  local tabs = vim.api.nvim_list_tabpages()
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
