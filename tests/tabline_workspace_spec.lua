local original_tabs = package.loaded["config.tabs"]

local active_tabs = { 22, 44 }
package.loaded["config.tabs"] = {
  current_workspace_tabs = function()
    return active_tabs
  end,
}

local original_get_current_tabpage = vim.api.nvim_get_current_tabpage
local original_get_number = vim.api.nvim_tabpage_get_number
vim.api.nvim_get_current_tabpage = function()
  return 44
end
vim.api.nvim_tabpage_get_number = function(tab)
  return ({ [22] = 2, [44] = 4 })[tab]
end

package.loaded["config.tabline"] = nil
local tabline = require("config.tabline")
local items = tabline.bufferline_workspace_tabs()

assert(#items == 2, "only active workspace tabs should be rendered")
assert(items[1].text:find(" Tab 1 ", 1, true), "first workspace tab should be numbered 1")
assert(items[2].text:find(" Tab 2 ", 1, true), "second workspace tab should be numbered 2")
assert(items[1].text:find("%2T", 1, true), "click target should use native tab number 2")
assert(items[2].text:find("%4T", 1, true), "click target should use native tab number 4")
assert(items[2].link == "TabLineSel", "current workspace tab should use selected highlight")

vim.api.nvim_get_current_tabpage = original_get_current_tabpage
vim.api.nvim_tabpage_get_number = original_get_number
package.loaded["config.tabs"] = original_tabs
package.loaded["config.tabline"] = nil
