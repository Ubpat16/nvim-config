local M = {}

function M.setup()
  local sections = {
    lualine_a = { "mode" },
    lualine_b = { "branch", "diff", "diagnostics" },
    lualine_c = { "filename" },
    lualine_x = {
      {
        require("config.ai.status").copilot_status,
        cond = require("config.ai.status").has_copilot_status,
      },
      "encoding",
      "fileformat",
      "filetype",
    },
    lualine_y = { "progress" },
    lualine_z = { "location" },
  }

  require("lualine").setup({
    options = {
      theme = "tokyonight",
      globalstatus = true,
      section_separators = "",
      component_separators = "|",
    },
    sections = sections,
  })
end

return M
