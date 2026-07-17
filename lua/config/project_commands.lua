local M = {}

local django = require("config.django")
local project_config = require("config.project_config")

local function append_args(command, args)
  for _, arg in ipairs(args or {}) do
    command = command .. " " .. vim.fn.shellescape(arg)
  end
  return command
end

local function pytest_root(start_path, configured_root)
  if configured_root then
    return configured_root
  end
  local marker = vim.fs.find({ "pyproject.toml", "pytest.ini", ".git" }, { path = start_path, upward = true })[1]
  return marker and vim.fn.fnamemodify(marker, ":h") or vim.fn.getcwd()
end

function M.pytest(opts)
  opts = opts or {}
  local file = opts.file or ""
  local start_path = file ~= "" and vim.fn.fnamemodify(file, ":h") or vim.fn.getcwd()
  local profile = project_config.get(file ~= "" and file or start_path)
  local root = pytest_root(start_path, profile.project.root)
  local env_file = profile.pytest.env_file or django.find_env_file(root)
  local command = "cd " .. vim.fn.shellescape(root) .. " && uv run"
  if env_file then
    command = command .. " --env-file " .. vim.fn.shellescape(env_file)
  end
  command = command .. " pytest"
  command = append_args(command, profile.pytest.direct_args)
  command = append_args(command, profile.neotest.args)
  if opts.target and opts.target ~= "" then
    command = command .. " " .. vim.fn.shellescape(opts.target)
  end
  return command
end

function M.python(file)
  local profile = project_config.get(file)
  local root = profile.project.root or vim.fn.fnamemodify(file, ":h")
  local command = "cd " .. vim.fn.shellescape(root) .. " && uv run"
  if profile.run.python.env_file then
    command = command .. " --env-file " .. vim.fn.shellescape(profile.run.python.env_file)
  end
  command = command .. " python " .. vim.fn.shellescape(file)
  return append_args(command, profile.run.python.args)
end

return M
