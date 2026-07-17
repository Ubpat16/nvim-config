local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")

local function write_lines(path, count)
  local file = assert(io.open(path, "w"))
  for index = 1, count do
    file:write("line " .. index .. "\n")
  end
  file:close()
end

local first = vim.fs.joinpath(root, "first.txt")
local second = vim.fs.joinpath(root, "second.txt")
write_lines(first, 30)
write_lines(second, 30)

package.loaded["config.tabs"] = nil
local tabs = require("config.tabs")
tabs.setup()

vim.cmd("edit " .. vim.fn.fnameescape(first))
vim.cmd("normal! 5G")
vim.cmd("normal! 10j")
vim.cmd("keepjumps edit " .. vim.fn.fnameescape(second))

local jumps, jump_index = unpack(vim.fn.getjumplist())
local target = assert(jumps[jump_index], "fixture must have an older jump")
local second_buf = vim.api.nvim_get_current_buf()

vim.cmd("noautocmd keepjumps buffer " .. target.bufnr)
vim.api.nvim_win_set_cursor(0, { math.min(target.lnum + 10, 30), 0 })
vim.api.nvim_exec_autocmds("BufLeave", { buffer = target.bufnr })
vim.cmd("noautocmd keepjumps buffer " .. second_buf)

tabs.jump_history(-1, 1)
assert(vim.api.nvim_get_current_buf() == target.bufnr, "older jump should return to the target buffer")
assert(vim.api.nvim_win_get_cursor(0)[1] == target.lnum, "older jump must keep the jumplist line")

local forward_jumps, forward_index = unpack(vim.fn.getjumplist())
local forward_target = assert(forward_jumps[forward_index + 2], "fixture must have a newer jump")
tabs.jump_history(1, 1)
assert(vim.api.nvim_get_current_buf() == forward_target.bufnr, "newer jump should return to the target buffer")
assert(vim.api.nvim_win_get_cursor(0)[1] == forward_target.lnum, "newer jump must keep the jumplist line")

tabs.jump_history(1, 100)
vim.api.nvim_win_set_cursor(0, { 20, 0 })
vim.cmd("edit " .. vim.fn.fnameescape(first))
vim.cmd("edit " .. vim.fn.fnameescape(second))
assert(vim.api.nvim_win_get_cursor(0)[1] == 20, "failed jumps must not suppress later cursor restoration")

vim.fn.delete(root, "rf")
