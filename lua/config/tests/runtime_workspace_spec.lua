local project_dir = vim.fn.tempname()
vim.fn.mkdir(project_dir, "p")
vim.cmd.cd(project_dir)

package.loaded["config.tabs"] = nil
local tabs = require("config.tabs")
tabs.setup()

assert(#vim.api.nvim_list_tabpages() == 1, "startup should keep one native tab")
assert(#tabs.workspace_names() == 1, "startup should create one runtime workspace")
assert(tabs.workspace_names()[1].name == "main", "startup workspace should be main")
assert(vim.api.nvim_buf_get_name(0) == "", "startup should use a blank buffer")
assert(#tabs.current_tab_buffers() == 0, "startup should not restore tracked buffers")

vim.cmd("doautocmd VimLeavePre")
local has_persist_autocmd, persist_autocmds = pcall(vim.api.nvim_get_autocmds, { group = "lc_tab_state_persist" })
assert(not has_persist_autocmd or #persist_autocmds == 0, "tab state should not persist on exit")

vim.fn.delete(project_dir, "rf")
