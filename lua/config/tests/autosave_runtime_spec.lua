local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local path = vim.fs.joinpath(root, "autosave.txt")
vim.fn.writefile({ "before" }, path)

require("config.autosave")
vim.cmd.edit(vim.fn.fnameescape(path))
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "after" })
vim.bo.modified = true
vim.api.nvim_exec_autocmds("VimLeavePre", { buffer = 0 })

assert(vim.fn.readfile(path)[1] == "after", "modified files should still autosave on exit")
vim.fn.delete(root, "rf")
