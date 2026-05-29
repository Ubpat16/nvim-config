local M = {}

function M.setup()
  local telescope = require("telescope")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local copy_selected_path = function(prompt_bufnr)
    local entry = action_state.get_selected_entry()
    local filepath = entry.path or entry.filename
    if not filepath then
      return
    end
    vim.fn.setreg("+", filepath)
    vim.notify("Copied path: " .. filepath, vim.log.levels.INFO)
    actions.close(prompt_bufnr)
  end

  telescope.setup({
    defaults = {
      layout_config = {
        horizontal = { prompt_position = "top" },
      },
      sorting_strategy = "ascending",
      prompt_prefix = "   ",
      selection_caret = "  ",
      winblend = 0,
      mappings = {
        i = {
          ["<C-y>"] = copy_selected_path,
          ["<C-v>"] = actions.select_vertical,
          ["<C-t>"] = actions.select_tab,
        },
        n = {
          ["y"] = copy_selected_path,
          ["v"] = actions.select_vertical,
          ["t"] = actions.select_tab,
        },
      },
    },
    pickers = {
      find_files = {
        hidden = true,
      },
    },
    extensions = {
      ["ui-select"] = require("telescope.themes").get_dropdown({}),
    },
  })

  pcall(telescope.load_extension, "ui-select")
end

return M
