local captured = nil
local steps = {}

package.loaded["config.tabs"] = {
  workspace_statusline_parts = function()
    return {
      previous = "<< ",
      label = "WS: personal",
      next = " >>",
    }
  end,
  workspace_next = function(step)
    steps[#steps + 1] = step
  end,
}
package.loaded["config.ai.status"] = {
  copilot_status = function()
    return ""
  end,
  has_copilot_status = function()
    return false
  end,
}
package.loaded["lualine"] = {
  setup = function(config)
    captured = config
  end,
}
package.loaded["config.statusline"] = nil

require("config.statusline").setup()

local components = assert(captured.sections.lualine_x)
local previous = components[#components - 2]
local label = components[#components - 1]
local following = components[#components]

assert(previous[1]() == "<< ", "previous arrow is rendered separately")
assert(label[1]() == "WS: personal", "workspace label remains inert")
assert(following[1]() == " >>", "next arrow is rendered separately")
assert(label.on_click == nil, "workspace label must not be clickable")

previous.on_click(1, "l", "")
following.on_click(1, "l", "")
previous.on_click(1, "r", "")
assert(vim.deep_equal(steps, { -1, 1 }), "only left-clicks navigate in the displayed direction")
