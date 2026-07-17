local project_state = require("config.project_state")

assert(project_state.restore_allowed_for_context({ kind = "directory" }), "directory launches should restore")
assert(project_state.restore_allowed_for_context({ kind = "default" }), "plain editor launches should restore")
assert(not project_state.restore_allowed_for_context({ kind = "file" }), "explicit file launches must not restore")
assert(not project_state.restore_allowed_for_context({ kind = "multiple" }), "multi-file launches must not restore")

local project_a = vim.fn.tempname()
local project_b = vim.fn.tempname()
vim.fn.mkdir(project_a, "p")
vim.fn.mkdir(project_b, "p")
vim.cmd.cd(project_a)
vim.cmd.enew()

local b_file = vim.fs.joinpath(project_b, "foreign.txt")
vim.fn.writefile({ "foreign" }, b_file)
local b_path = vim.fs.normalize(vim.uv.fs_realpath(b_file) or b_file)

local state_path = project_state.state_path_for_root(project_b)
local file = assert(io.open(state_path, "w"))
file:write(vim.json.encode({
  version = 2,
  root = project_state.normalize_path(project_b),
  active_tab_id = 1,
  next_tab_id = 2,
  tabs = {
    {
      id = 1,
      buffers = { b_path },
      layout = { type = "leaf", buffer = { type = "file", path = b_path } },
    },
  },
  recent_files = { b_path },
}))
file:close()

package.loaded["config.tabs"] = nil
package.loaded["config.project_state"] = nil
local tabs = require("config.tabs")
tabs.setup()

assert(#tabs.current_workspace_tabs() == 1, "project A must not restore project B's tabs")
local bufnr = vim.api.nvim_win_get_buf(vim.api.nvim_tabpage_get_win(vim.api.nvim_get_current_tabpage()))
assert(vim.api.nvim_buf_get_name(bufnr) == "", "foreign project state must not open a file in project A")

vim.fn.delete(project_a, "rf")
vim.fn.delete(project_b, "rf")
