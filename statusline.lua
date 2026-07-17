local M = {}

local function workspace_part(name)
  return require("config.tabs").workspace_statusline_parts()[name]
end

local function workspace_click(step)
  return function(_, button)
    if button == "l" then
      require("config.tabs").workspace_next(step)
    end
  end
end

local workspace_separator = { left = "", right = "" }

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
      {
        function()
          return workspace_part("previous")
        end,
        on_click = workspace_click(-1),
        padding = 0,
        separator = workspace_separator,
      },
      {
        function()
          return workspace_part("label")
        end,
        padding = 0,
        separator = workspace_separator,
      },
      {
        function()
          return workspace_part("next")
        end,
        on_click = workspace_click(1),
        padding = 0,
        separator = workspace_separator,
      },
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
