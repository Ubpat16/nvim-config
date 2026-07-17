local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
vim.cmd.cd(root)

local files = {}
for index = 1, 4 do
  local path = vim.fs.joinpath(root, "tab-" .. index .. ".txt")
  vim.fn.writefile({ "tab " .. index }, path)
  files[index] = vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

package.loaded["config.tabs"] = nil
local tabs = require("config.tabs")
tabs.setup()

vim.cmd("edit " .. vim.fn.fnameescape(files[1]))
for index = 2, 4 do
  assert(tabs.new_tab(), "tab " .. index .. " should be created")
  vim.cmd("edit " .. vim.fn.fnameescape(files[index]))
end
vim.api.nvim_set_current_tabpage(vim.api.nvim_list_tabpages()[2])

vim.api.nvim_exec_autocmds("VimLeavePre", {})
local project_state = require("config.project_state")
local state_file = assert(io.open(project_state.state_path_for_root(root), "r"))
local state = vim.json.decode(state_file:read("*a"))
state_file:close()

assert(#state.tabs == 4, "all native tabs should be persisted")
for index, tab_state in ipairs(state.tabs) do
  local buffer = tab_state.layout and tab_state.layout.buffer
  assert(buffer and buffer.type == "file", "tab " .. index .. " layout should retain its visible file")
  assert(buffer.path == files[index], "tab " .. index .. " should retain the correct visible file")
end
assert(state.active_tab_id == state.tabs[2].id, "active tab identity should be persisted")

vim.fn.delete(root, "rf")
