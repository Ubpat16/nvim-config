local M = {}

local CONFIG_NAME = "nvim.config"
local cache = {}

local DEFAULTS = {
  project = { root = nil },
  editor = {
    autosave = true,
    options = {},
  },
  python = { interpreter = nil },
  django = { root = nil, manage_py = nil, env_file = nil },
  neotest = {
    args = {},
    python = { runner = "pytest" },
    jest = { args = {} },
  },
  pytest = { direct_args = { "--reuse-db" }, env_file = nil },
  formatting = {
    on_save = true,
    timeout_ms = nil,
    by_filetype = {
      python = { "ruff_fix_imports", "black" },
      javascript = { "prettier" },
      javascriptreact = { "prettier" },
      typescript = { "prettier" },
      typescriptreact = { "prettier" },
      json = { "prettier" },
      html = { "prettier" },
      htmldjango = { "prettier" },
      css = { "prettier" },
      yaml = { "prettier" },
      markdown = { "prettier" },
    },
  },
  linting = {
    enabled = true,
    by_filetype = {
      javascript = { "eslint_d" },
      javascriptreact = { "eslint_d" },
      typescript = { "eslint_d" },
      typescriptreact = { "eslint_d" },
    },
  },
  lsp = { settings = {} },
  dap = {
    python = {
      just_my_code = false,
      env_file = nil,
      django_runserver_args = { "runserver", "--noreload" },
      celery_app = "config",
      celery_args = { "worker", "-l", "info", "-P", "solo" },
      attach_host = "127.0.0.1",
      attach_port = 5678,
    },
  },
  run = { python = { args = {}, env_file = nil } },
}

local EDITOR_OPTION_TYPES = {
  expandtab = "boolean",
  shiftwidth = "number",
  tabstop = "number",
  softtabstop = "number",
  textwidth = "number",
  colorcolumn = "string",
  wrap = "boolean",
  spell = "boolean",
}

local function normalize(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local expanded = vim.fn.fnamemodify(path, ":p")
  return vim.fs.normalize(vim.uv.fs_realpath(expanded) or expanded)
end

local function start_directory(start_path)
  local path = normalize(start_path) or normalize(vim.fn.getcwd())
  if not path then
    return nil
  end
  return vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ":h")
end

local function find_config(start_path)
  local start = start_directory(start_path)
  if not start then
    return nil
  end
  return normalize(vim.fs.find(CONFIG_NAME, { path = start, upward = true, type = "file" })[1])
end

local function fingerprint(stat)
  local mtime = stat and stat.mtime or {}
  return table.concat({ stat and stat.size or 0, mtime.sec or 0, mtime.nsec or 0 }, ":")
end

local function is_object(value)
  return type(value) == "table" and not vim.islist(value)
end

local function string_list(value)
  if type(value) ~= "table" or not vim.islist(value) then
    return nil
  end
  local copy = {}
  for _, item in ipairs(value) do
    if type(item) ~= "string" then
      return nil
    end
    copy[#copy + 1] = item
  end
  return copy
end

local function add_error(errors, path, message)
  errors[#errors + 1] = path .. " " .. message
end

local function check_unknown(value, allowed, path, errors)
  if not is_object(value) then
    return false
  end
  for key in pairs(value) do
    if not allowed[key] then
      add_error(errors, path .. "." .. tostring(key), "is unknown")
    end
  end
  return true
end

local function assign_scalar(target, source, key, expected, path, errors, predicate)
  if source[key] == nil then
    return
  end
  if type(source[key]) ~= expected or (predicate and not predicate(source[key])) then
    add_error(errors, path .. "." .. key, "must be " .. expected)
    return
  end
  target[key] = source[key]
end

local function assign_list(target, source, key, path, errors)
  if source[key] == nil then
    return
  end
  local value = string_list(source[key])
  if not value then
    add_error(errors, path .. "." .. key, "must be an array of strings")
    return
  end
  target[key] = value
end

local function validate_filetype_map(value, path, errors)
  if not is_object(value) then
    add_error(errors, path, "must be an object of string arrays")
    return nil
  end
  local result = {}
  for filetype, configured in pairs(value) do
    if type(filetype) ~= "string" then
      add_error(errors, path, "contains a non-string filetype")
    else
      local list = string_list(configured)
      if list then
        result[filetype] = list
      else
        add_error(errors, path .. "." .. filetype, "must be an array of strings")
      end
    end
  end
  return result
end

local function validate(decoded)
  local profile = vim.deepcopy(DEFAULTS)
  local errors = {}
  if not is_object(decoded) then
    return profile, { "top-level value must be an object" }
  end

  check_unknown(decoded, {
    project = true, editor = true, python = true, django = true, neotest = true,
    pytest = true, formatting = true, linting = true, lsp = true, dap = true, run = true,
  }, "config", errors)

  local function section(name, allowed)
    local value = decoded[name]
    if value == nil then
      return nil
    end
    if not check_unknown(value, allowed, name, errors) then
      add_error(errors, name, "must be an object")
      return nil
    end
    return value
  end

  local value = section("project", { root = true })
  if value then assign_scalar(profile.project, value, "root", "string", "project", errors) end

  value = section("editor", { autosave = true, options = true })
  if value then
    assign_scalar(profile.editor, value, "autosave", "boolean", "editor", errors)
    if value.options ~= nil then
      if check_unknown(value.options, EDITOR_OPTION_TYPES, "editor.options", errors) then
        for key, expected in pairs(EDITOR_OPTION_TYPES) do
          assign_scalar(profile.editor.options, value.options, key, expected, "editor.options", errors, function(item)
            return expected ~= "number" or item >= 0
          end)
        end
      else
        add_error(errors, "editor.options", "must be an object")
      end
    end
  end

  value = section("python", { interpreter = true })
  if value then assign_scalar(profile.python, value, "interpreter", "string", "python", errors) end

  value = section("django", { root = true, manage_py = true, env_file = true })
  if value then
    for _, key in ipairs({ "root", "manage_py", "env_file" }) do
      assign_scalar(profile.django, value, key, "string", "django", errors)
    end
  end

  value = section("neotest", { args = true, python = true, jest = true })
  if value then
    assign_list(profile.neotest, value, "args", "neotest", errors)
    if value.python ~= nil then
      if check_unknown(value.python, { runner = true }, "neotest.python", errors) then
        assign_scalar(profile.neotest.python, value.python, "runner", "string", "neotest.python", errors, function(item)
          return item == "pytest" or item == "unittest"
        end)
      else
        add_error(errors, "neotest.python", "must be an object")
      end
    end
    if value.jest ~= nil then
      if check_unknown(value.jest, { args = true }, "neotest.jest", errors) then
        assign_list(profile.neotest.jest, value.jest, "args", "neotest.jest", errors)
      else
        add_error(errors, "neotest.jest", "must be an object")
      end
    end
  end

  value = section("pytest", { direct_args = true, env_file = true })
  if value then
    assign_list(profile.pytest, value, "direct_args", "pytest", errors)
    assign_scalar(profile.pytest, value, "env_file", "string", "pytest", errors)
  end

  value = section("formatting", { on_save = true, timeout_ms = true, by_filetype = true })
  if value then
    assign_scalar(profile.formatting, value, "on_save", "boolean", "formatting", errors)
    assign_scalar(profile.formatting, value, "timeout_ms", "number", "formatting", errors, function(item) return item > 0 end)
    if value.by_filetype ~= nil then
      local configured = validate_filetype_map(value.by_filetype, "formatting.by_filetype", errors)
      if configured then
        profile.formatting.by_filetype = vim.tbl_deep_extend("force", profile.formatting.by_filetype, configured)
      end
    end
  end

  value = section("linting", { enabled = true, by_filetype = true })
  if value then
    assign_scalar(profile.linting, value, "enabled", "boolean", "linting", errors)
    if value.by_filetype ~= nil then
      local configured = validate_filetype_map(value.by_filetype, "linting.by_filetype", errors)
      if configured then
        profile.linting.by_filetype = vim.tbl_deep_extend("force", profile.linting.by_filetype, configured)
      end
    end
  end

  value = section("lsp", { settings = true })
  if value and value.settings ~= nil then
    if is_object(value.settings) then
      profile.lsp.settings = vim.deepcopy(value.settings)
    else
      add_error(errors, "lsp.settings", "must be an object")
    end
  end

  value = section("dap", { python = true })
  if value and value.python ~= nil then
    local python = value.python
    if check_unknown(python, {
      just_my_code = true, env_file = true, django_runserver_args = true, celery_app = true,
      celery_args = true, attach_host = true, attach_port = true,
    }, "dap.python", errors) then
      assign_scalar(profile.dap.python, python, "just_my_code", "boolean", "dap.python", errors)
      assign_scalar(profile.dap.python, python, "env_file", "string", "dap.python", errors)
      assign_list(profile.dap.python, python, "django_runserver_args", "dap.python", errors)
      assign_scalar(profile.dap.python, python, "celery_app", "string", "dap.python", errors)
      assign_list(profile.dap.python, python, "celery_args", "dap.python", errors)
      assign_scalar(profile.dap.python, python, "attach_host", "string", "dap.python", errors)
      assign_scalar(profile.dap.python, python, "attach_port", "number", "dap.python", errors, function(item)
        return item >= 1 and item <= 65535 and item % 1 == 0
      end)
    else
      add_error(errors, "dap.python", "must be an object")
    end
  end

  value = section("run", { python = true })
  if value and value.python ~= nil then
    if check_unknown(value.python, { args = true, env_file = true }, "run.python", errors) then
      assign_list(profile.run.python, value.python, "args", "run.python", errors)
      assign_scalar(profile.run.python, value.python, "env_file", "string", "run.python", errors)
    else
      add_error(errors, "run.python", "must be an object")
    end
  end

  return profile, errors
end

local function resolve_relative(config_dir, path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local expanded = vim.fn.expand(path)
  if not expanded:match("^/") then
    expanded = vim.fs.joinpath(config_dir, expanded)
  end
  return normalize(expanded)
end

local function resolve_paths(profile, config_dir)
  profile.project.root = resolve_relative(config_dir, profile.project.root)
  profile.python.interpreter = resolve_relative(config_dir, profile.python.interpreter)
  for _, key in ipairs({ "root", "manage_py", "env_file" }) do
    profile.django[key] = resolve_relative(config_dir, profile.django[key])
  end
  profile.pytest.env_file = resolve_relative(config_dir, profile.pytest.env_file)
  profile.dap.python.env_file = resolve_relative(config_dir, profile.dap.python.env_file)
  profile.run.python.env_file = resolve_relative(config_dir, profile.run.python.env_file)
  return profile
end

local function load_config(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    cache[path] = nil
    return vim.deepcopy(DEFAULTS)
  end
  local version = fingerprint(stat)
  local cached = cache[path]
  if cached and cached.version == version then
    return cached.profile
  end

  local file = io.open(path, "r")
  local content = file and file:read("*a") or nil
  if file then file:close() end

  local decoded_ok, decoded = pcall(vim.json.decode, content or "")
  local profile, errors
  if decoded_ok then
    profile, errors = validate(decoded)
  else
    profile, errors = vim.deepcopy(DEFAULTS), { "invalid JSON" }
  end

  local config_dir = vim.fs.dirname(path)
  profile = resolve_paths(profile, config_dir)
  if #errors > 0 then
    vim.notify(CONFIG_NAME .. ": " .. table.concat(errors, "; ") .. " (" .. path .. ")", vim.log.levels.WARN)
  end

  cache[path] = { version = version, profile = profile }
  return profile
end

function M.get(start_path)
  local path = find_config(start_path)
  if not path then
    return vim.deepcopy(DEFAULTS), { config_path = nil, config_dir = nil }
  end
  return vim.deepcopy(load_config(path)), {
    config_path = path,
    config_dir = vim.fs.dirname(path),
  }
end

function M.neotest_args(start_path)
  return M.get(start_path).neotest.args
end

function M.start_path(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
      return name
    end
  end
  return vim.fn.getcwd()
end

function M.apply_lsp_settings(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) or not vim.lsp then
    return
  end
  local profile = M.get(M.start_path(bufnr))
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if client._lc_project_base_settings == nil then
      client._lc_project_base_settings = vim.deepcopy(client.settings or {})
    end
    local override = profile.lsp.settings[client.name] or {}
    client.settings = vim.tbl_deep_extend(
      "force",
      vim.deepcopy(client._lc_project_base_settings),
      vim.deepcopy(override)
    )
    client:notify("workspace/didChangeConfiguration", { settings = client.settings })
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("lc_project_profile", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "FileType", "DirChanged" }, {
    group = group,
    callback = function(event)
      local bufnr = event.buf and event.buf > 0 and event.buf or vim.api.nvim_get_current_buf()
      vim.schedule(function()
        M.apply_editor_options(bufnr)
        M.apply_lsp_settings(bufnr)
      end)
    end,
  })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = CONFIG_NAME,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      vim.schedule(function()
        M.apply_editor_options(bufnr)
        M.apply_lsp_settings(bufnr)
      end)
    end,
  })
end

function M.apply_editor_options(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  local profile = M.get(name ~= "" and name or vim.fn.getcwd())
  local state = vim.b[bufnr].lc_project_option_state or { baseline = {}, applied = {} }
  for option in pairs(EDITOR_OPTION_TYPES) do
    local ok, current = pcall(function() return vim.bo[bufnr][option] end)
    if ok then
      if state.baseline[option] == nil or (state.applied[option] ~= nil and current ~= state.applied[option]) then
        state.baseline[option] = current
      end
      local value = profile.editor.options[option]
      if value == nil then
        value = state.baseline[option]
      end
      pcall(function() vim.bo[bufnr][option] = value end)
      state.applied[option] = value
    end
  end
  vim.b[bufnr].lc_project_option_state = state
end

M.defaults = function()
  return vim.deepcopy(DEFAULTS)
end

return M
