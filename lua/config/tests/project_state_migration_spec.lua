local state_dir = vim.fn.stdpath("state")
vim.fn.mkdir(state_dir, "p")

local project_root = vim.fn.tempname()
local foreign_root = vim.fn.tempname()
vim.fn.mkdir(project_root, "p")
vim.fn.mkdir(foreign_root, "p")
vim.cmd.cd(project_root)
vim.cmd.enew()

local function write_file(dir, name)
  local path = vim.fs.joinpath(dir, name)
  vim.fn.writefile({ name }, path)
  return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

local local_file = write_file(project_root, "local.txt")
local foreign_file = write_file(foreign_root, "foreign.txt")

local legacy_state = vim.fs.joinpath(state_dir, "tab-state.json")
local file = assert(io.open(legacy_state, "w"))
file:write(vim.json.encode({
  version = 1,
  active_tab_id = 2,
  next_tab_id = 3,
  tabs = {
    {
      id = 1,
      workspace_id = 1,
      buffers = { local_file },
      layout = { type = "leaf", buffer = { type = "file", path = local_file } },
    },
    {
      id = 2,
      workspace_id = 1,
      buffers = { foreign_file },
      layout = { type = "leaf", buffer = { type = "file", path = foreign_file } },
    },
  },
}))
file:close()

package.loaded["config.tabs"] = nil
package.loaded["config.project_state"] = nil
local tabs = require("config.tabs")
tabs.setup()

assert(#tabs.current_workspace_tabs() == 1, "legacy state should only restore files from the active project")
local bufnr = vim.api.nvim_win_get_buf(vim.api.nvim_tabpage_get_win(vim.api.nvim_get_current_tabpage()))
assert(vim.api.nvim_buf_get_name(bufnr) == local_file, "legacy migration should restore the active project file")

vim.fn.delete(project_root, "rf")
vim.fn.delete(foreign_root, "rf")
