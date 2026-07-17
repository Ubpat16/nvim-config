local project_root = vim.fn.tempname()
vim.fn.mkdir(project_root, "p")
vim.cmd.cd(project_root)
vim.cmd.enew()

local file_path = vim.fs.joinpath(project_root, "clear-me.txt")
vim.fn.writefile({ "clear me" }, file_path)
local normalized = vim.fs.normalize(vim.uv.fs_realpath(file_path) or file_path)

package.loaded["config.project_state"] = nil
package.loaded["config.tabs"] = nil
local project_state = require("config.project_state")
local tabs = require("config.tabs")
tabs.setup()

vim.cmd("edit " .. vim.fn.fnameescape(normalized))
vim.api.nvim_exec_autocmds("VimLeavePre", {})
assert(project_state.read_root_state(project_root) ~= nil, "fixture should persist before clearing")

tabs.clear_all_buffers()
assert(project_state.read_root_state(project_root) == nil, "clear-all should remove persisted project state")

package.loaded["config.tabs"] = nil
package.loaded["config.project_state"] = nil
local reloaded_tabs = require("config.tabs")
reloaded_tabs.setup()
assert(#reloaded_tabs.current_workspace_tabs() == 1, "cleared project should reopen without restored tabs")
local bufnr = vim.api.nvim_win_get_buf(vim.api.nvim_tabpage_get_win(vim.api.nvim_get_current_tabpage()))
assert(vim.api.nvim_buf_get_name(bufnr) == "", "cleared project should not restore the cleared file")

vim.fn.delete(project_root, "rf")
