local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
vim.env.XDG_STATE_HOME = root

local function write_lines(path, count)
  local file = assert(io.open(path, "w"))
  for index = 1, count do
    file:write("line " .. index .. "\n")
  end
  file:close()
end

local first = vim.fs.joinpath(root, "first.txt")
local second = vim.fs.joinpath(root, "second.txt")
local third = vim.fs.joinpath(root, "third.txt")
write_lines(first, 40)
write_lines(second, 40)
write_lines(third, 40)

package.loaded["config.tabs"] = nil
local tabs = require("config.tabs")
tabs.setup()

vim.cmd("edit " .. vim.fn.fnameescape(first))
local first_buf = vim.api.nvim_get_current_buf()
vim.cmd("vsplit")
local right_win = vim.api.nvim_get_current_win()
local split_wins = vim.api.nvim_tabpage_list_wins(0)
local left_win = split_wins[1] == right_win and split_wins[2] or split_wins[1]
assert(left_win and left_win ~= right_win, "fixture must create two distinct split windows")

vim.api.nvim_set_current_win(left_win)
vim.api.nvim_win_set_cursor(left_win, { 5, 0 })
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = first_buf })
vim.api.nvim_set_current_win(right_win)
vim.api.nvim_win_set_cursor(right_win, { 20, 0 })
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = first_buf })

vim.api.nvim_set_current_win(left_win)
vim.cmd("edit " .. vim.fn.fnameescape(second))
vim.api.nvim_set_current_win(right_win)

assert(vim.api.nvim_win_get_buf(right_win) == first_buf, "right split should still show the first buffer")
assert(vim.api.nvim_win_get_cursor(right_win)[1] == 20, "each split must retain its own cursor for the same buffer")

vim.cmd("edit " .. vim.fn.fnameescape(third))
vim.api.nvim_set_current_win(left_win)
vim.cmd("edit " .. vim.fn.fnameescape(first))
local restored_left_line = vim.api.nvim_win_get_cursor(left_win)[1]
assert(restored_left_line == 5, "returning in the left split must restore the left cursor, got " .. restored_left_line)

vim.api.nvim_set_current_win(right_win)
vim.cmd("edit " .. vim.fn.fnameescape(first))
assert(vim.api.nvim_win_get_cursor(right_win)[1] == 20, "returning in the right split must restore the right cursor")

vim.cmd("only")
vim.cmd("edit " .. vim.fn.fnameescape(first))
vim.cmd("edit " .. vim.fn.fnameescape(second))
vim.cmd("edit " .. vim.fn.fnameescape(third))

local initial_order = tabs.current_tab_buffers()
vim.cmd("buffer " .. initial_order[1])
local visited_order = tabs.current_tab_buffers()

assert(vim.deep_equal(visited_order, initial_order), "visiting a buffer must not reorder tab-local navigation")

vim.fn.delete(root, "rf")
