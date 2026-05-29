local M = {}

local SCRIPT_PATTERNS = {
  "/main%.py$",
  "^main%.py$",
  "/scripts/.+%.py$",
}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Django" })
end

local function save_current_buffer_if_file()
  if vim.bo.buftype ~= "" then
    return
  end
  if not vim.bo.modifiable or vim.bo.readonly then
    return
  end
  if vim.api.nvim_buf_get_name(0) == "" then
    return
  end

  vim.cmd("silent update")
end

local function normalize(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local expanded = vim.fn.fnamemodify(path, ":p")
  local real = vim.uv.fs_realpath(expanded)
  return vim.fs.normalize(real or expanded)
end

local function current_path()
  local name = vim.api.nvim_buf_get_name(0)
  if name ~= "" then
    return name
  end
  return vim.fn.getcwd()
end

function M.find_manage_py_root(start_path)
  local start = start_path or current_path()
  if vim.fn.filereadable(start) == 1 then
    start = vim.fn.fnamemodify(start, ":p:h")
  elseif vim.fn.isdirectory(start) == 1 then
    start = vim.fn.fnamemodify(start, ":p")
  else
    start = vim.fn.getcwd()
  end

  local manage_py = vim.fs.find("manage.py", {
    path = start,
    upward = true,
  })[1]

  if not manage_py then
    return nil
  end

  return normalize(vim.fn.fnamemodify(manage_py, ":h"))
end

function M.find_env_file(root)
  if not root then
    return nil
  end

  for _, name in ipairs({ ".env.test", ".env-test" }) do
    local path = vim.fs.joinpath(root, name)
    if vim.fn.filereadable(path) == 1 then
      return normalize(path)
    end
  end

  return nil
end

function M.resolve_context(start_path)
  local root = M.find_manage_py_root(start_path)
  if not root then
    return nil, "No Django project found. Expected a manage.py above the current file or cwd."
  end

  local env_file = M.find_env_file(root)
  if not env_file then
    return nil, "No env file found. Expected .env.test or .env-test in the Django project root."
  end

  return {
    root = root,
    env_file = env_file,
    manage_py = vim.fs.joinpath(root, "manage.py"),
  }
end

local function shell_prefix(root)
  return "cd " .. vim.fn.shellescape(root) .. " && "
end

function M.base_manage_command(context)
  return shell_prefix(context.root)
    .. "uv run --env-file "
    .. vim.fn.shellescape(context.env_file)
    .. " python manage.py"
end

function M.manage_command(args, start_path)
  local context, error_message = M.resolve_context(start_path)
  if not context then
    return nil, error_message
  end

  local command = M.base_manage_command(context)
  if args and args ~= "" then
    command = command .. " " .. args
  end
  return command, context
end

function M.run_in_shell(command)
  vim.cmd("!" .. command)
end

function M.run_manage(args)
  local command, context_or_error = M.manage_command(args)
  if not command then
    notify(context_or_error, vim.log.levels.WARN)
    return
  end

  save_current_buffer_if_file()
  M.run_in_shell(command)
end

function M.prompt_manage()
  local command, context_or_error = M.manage_command("")
  if not command then
    notify(context_or_error, vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = "manage.py command: " }, function(input)
    if not input or vim.trim(input) == "" then
      return
    end

    M.run_in_shell(command .. " " .. vim.trim(input))
  end)
end

local function is_script_candidate(path)
  local relative = path
  for _, pattern in ipairs(SCRIPT_PATTERNS) do
    if relative:match(pattern) then
      return true
    end
  end
  return false
end

local function collect_script_candidates(root)
  local files = {}

  if vim.fn.executable("rg") == 1 then
    files = vim.fn.systemlist(
      "cd " .. vim.fn.shellescape(root) .. " && rg --files -g '*.py'"
    )
    if vim.v.shell_error ~= 0 then
      files = {}
    end
  else
    files = vim.fs.find(function(name)
      return name:match("%.py$")
    end, {
      path = root,
      type = "file",
      limit = math.huge,
    })

    for index, file in ipairs(files) do
      files[index] = file:gsub("^" .. vim.pesc(root .. "/"), "")
    end
  end

  local results = {}
  for _, file in ipairs(files) do
    if is_script_candidate(file) then
      results[#results + 1] = file
    end
  end

  table.sort(results)
  return results
end

function M.run_script_in_shell(script_path, start_path)
  local command, context_or_error = M.manage_command("shell < " .. vim.fn.shellescape(script_path), start_path)
  if not command then
    notify(context_or_error, vim.log.levels.WARN)
    return
  end

  M.run_in_shell(command)
end

function M.pick_script_and_run()
  local context, error_message = M.resolve_context()
  if not context then
    notify(error_message, vim.log.levels.WARN)
    return
  end

  local candidates = collect_script_candidates(context.root)
  if #candidates == 0 then
    notify("No Django entry scripts found in this project.", vim.log.levels.WARN)
    return
  end

  local ok, pickers = pcall(require, "telescope.pickers")
  local ok_finders, finders = pcall(require, "telescope.finders")
  local ok_config, telescope_config = pcall(require, "telescope.config")
  local ok_actions, actions = pcall(require, "telescope.actions")
  local ok_action_state, action_state = pcall(require, "telescope.actions.state")

  if not (ok and ok_finders and ok_config and ok_actions and ok_action_state) then
    notify("Telescope is required to pick a Django script.", vim.log.levels.ERROR)
    return
  end

  pickers
    .new({}, {
      prompt_title = "Django Scripts",
      finder = finders.new_table({
        results = candidates,
      }),
      sorter = telescope_config.values.generic_sorter({}),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if not selection or not selection.value then
            return
          end

          local absolute = vim.fs.joinpath(context.root, selection.value)
          M.run_script_in_shell(absolute, context.root)
        end)
        return true
      end,
    })
    :find()
end

return M
