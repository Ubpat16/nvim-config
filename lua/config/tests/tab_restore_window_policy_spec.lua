local project_root = vim.fn.tempname()
vim.fn.mkdir(project_root, "p")
vim.cmd.cd(project_root)

local file_path = vim.fs.joinpath(project_root, "restored.txt")
vim.fn.writefile({ "restored" }, file_path)
file_path = vim.fs.normalize(vim.uv.fs_realpath(file_path) or file_path)

package.loaded["config.project_state"] = nil
package.loaded["config.tabs"] = nil
local project_state = require("config.project_state")
project_state.write_root_state(project_root, {
  version = 2,
  root = project_root,
  active_tab_id = 1,
  next_tab_id = 2,
  tabs = {
    {
      id = 1,
      buffers = { file_path },
      focus_leaf = 1,
      layout = {
        type = "row",
        children = {
          { type = "leaf", buffer = { type = "file", path = file_path } },
          { type = "leaf", buffer = { type = "file", path = vim.fs.joinpath(project_root, "NvimTree_1") } },
          { type = "leaf", buffer = { type = "special", buftype = "nofile", name = "NvimTree_1" } },
          { type = "leaf", buffer = { type = "blank" } },
          { type = "leaf", buffer = { type = "file", path = file_path } },
        },
      },
    },
  },
})

local tabs = require("config.tabs")
tabs.setup()

local wins = vim.api.nvim_tabpage_list_wins(0)
assert(#wins == 2, "restore should keep duplicate real-file views but discard non-file leaves")
local restored_buf = vim.api.nvim_win_get_buf(wins[1])
assert(vim.api.nvim_buf_get_name(restored_buf) == file_path, "first split should restore the real file")
assert(vim.api.nvim_win_get_buf(wins[2]) == restored_buf, "duplicate file leaves should share one buffer")

vim.api.nvim_set_current_win(wins[1])
assert(tabs.close_current_buffer_view_if_shared(), "shared buffer view should close as a window")
assert(#vim.api.nvim_tabpage_list_wins(0) == 1, "only the selected split should close")
assert(vim.api.nvim_buf_is_valid(restored_buf), "closing one view must not delete the shared buffer")
assert(vim.api.nvim_win_get_buf(0) == restored_buf, "the remaining split should still display the file")

vim.fn.delete(project_root, "rf")
