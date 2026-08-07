local project_state = require("config.project_state")

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")

project_state.update_root_state(root, function(state)
  state.marker = "unchanged"
  return state
end)

local path = project_state.state_path_for_root(root)
local before = assert(vim.uv.fs_stat(path))
vim.uv.sleep(30)

project_state.update_root_state(root, function(state)
  assert(state.marker == "unchanged", "cached state should be reused")
  return state
end)

local after = assert(vim.uv.fs_stat(path))
assert(before.size == after.size, "unchanged state should retain its serialized size")
assert(before.mtime.sec == after.mtime.sec and before.mtime.nsec == after.mtime.nsec, "unchanged state should not be rewritten")

vim.fn.delete(root, "rf")
