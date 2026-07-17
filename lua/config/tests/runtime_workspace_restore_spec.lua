local state_dir = vim.fn.stdpath("state")
vim.fn.mkdir(state_dir, "p")

local project_dir = vim.fn.tempname()
vim.fn.mkdir(project_dir, "p")
local restored_files = {}
for index = 1, 2 do
  local path = vim.fs.joinpath(project_dir, "restored-" .. index .. ".txt")
  vim.fn.writefile({ "restored " .. index }, path)
  restored_files[index] = vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

local state_file = vim.fs.joinpath(state_dir, "tab-state.json")
local file = assert(io.open(state_file, "w"))
file:write(vim.json.encode({
  version = 1,
  active_tab_id = 2,
  next_tab_id = 3,
  workspaces = {
    { id = 1, name = "main" },
    { id = 2, name = "personal" },
  },
  tabs = {
    {
      id = 1,
      workspace_id = 1,
      buffers = { restored_files[1] },
      layout = { type = "leaf" },
    },
    {
      id = 2,
      workspace_id = 2,
      buffers = { restored_files[2] },
      layout = { type = "leaf", buffer = { type = "file", path = restored_files[2] } },
    },
  },
}))
file:close()

package.loaded["config.tabs"] = nil
local tabs = require("config.tabs")
tabs.setup()

local workspaces = tabs.workspace_names()
assert(#workspaces == 1, "legacy workspaces must not survive restart")
assert(workspaces[1].name == "main", "restored tabs belong to a fresh main workspace")
assert(#tabs.current_workspace_tabs() == 2, "native tabs still restore")
assert(vim.api.nvim_tabpage_get_var(0, "lc_tab_id") == 2, "active native tab still restores")
for index, tab in ipairs(vim.api.nvim_list_tabpages()) do
  local win = vim.api.nvim_tabpage_get_win(tab)
  local bufnr = vim.api.nvim_win_get_buf(win)
  assert(vim.api.nvim_buf_get_name(bufnr) == restored_files[index], "tab " .. index .. " restores its visible file")
end

local parts = tabs.workspace_statusline_parts()
assert(parts.previous == "" and parts.next == "", "single workspace has no navigation arrows")

assert(tabs.workspace_new("second"), "second workspace should be created")
parts = tabs.workspace_statusline_parts()
assert(parts.previous == "<< " and parts.next == "", "last workspace only shows previous arrow")

tabs.workspace_next(-1)
parts = tabs.workspace_statusline_parts()
assert(parts.previous == "" and parts.next == " >>", "first workspace only shows next arrow")

vim.api.nvim_exec_autocmds("VimLeavePre", {})
local persisted_file = assert(io.open(state_file, "r"))
local persisted = vim.json.decode(persisted_file:read("*a"))
persisted_file:close()
assert(persisted.workspaces == nil, "workspace collection must not be persisted")
for _, tab in ipairs(persisted.tabs) do
  assert(tab.workspace_id == nil, "tab workspace membership must not be persisted")
end

vim.fn.delete(project_dir, "rf")
