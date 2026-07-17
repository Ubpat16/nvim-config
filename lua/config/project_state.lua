local M = {}

local state_root = vim.fs.joinpath(vim.fn.stdpath("state"), "projects")
local legacy_tab_state_path = vim.fs.joinpath(vim.fn.stdpath("state"), "tab-state.json")
local legacy_recent_files_path = vim.fs.joinpath(vim.fn.stdpath("state"), "last-project-file.json")
local project_markers = {
  ".git",
  "pyproject.toml",
  "package.json",
  "manage.py",
  "Cargo.toml",
  "go.mod",
  "Makefile",
}

local state_cache = {}

local function normalize_path(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end

  local expanded = vim.fn.fnamemodify(path, ":p")
  local real = vim.uv.fs_realpath(expanded)
  return vim.fs.normalize(real or expanded)
end

local function hash_root(root)
  local ok, hashed = pcall(vim.fn.sha256, root)
  if ok and type(hashed) == "string" and hashed ~= "" then
    return hashed
  end

  return (root:gsub("[^%w]", "_"))
end

local function ensure_state_dir()
  vim.fn.mkdir(state_root, "p")
end

local function state_path(root)
  local normalized = normalize_path(root)
  if not normalized then
    return nil
  end

  ensure_state_dir()
  return vim.fs.joinpath(state_root, hash_root(normalized) .. ".json")
end

local function project_root_for_path(path)
  local start = path
  if start == nil or start == "" then
    start = vim.fn.getcwd()
  elseif vim.fn.filereadable(start) == 1 then
    start = vim.fn.fnamemodify(start, ":p:h")
  elseif vim.fn.isdirectory(start) == 1 then
    start = vim.fn.fnamemodify(start, ":p")
  else
    start = vim.fn.getcwd()
  end

  local git_marker = vim.fs.find({ ".git" }, { path = start, upward = true })[1]
  if git_marker then
    return normalize_path(vim.fn.fnamemodify(git_marker, ":h"))
  end

  local marker = vim.fs.find(project_markers, { path = start, upward = true })[1]
  local root = marker and vim.fn.fnamemodify(marker, ":h") or vim.fn.getcwd()
  return normalize_path(root)
end

local function startup_directory_arg()
  if vim.fn.argc() ~= 1 then
    return nil
  end

  local arg = vim.fn.argv(0)
  if vim.fn.isdirectory(arg) ~= 1 then
    return nil
  end

  return normalize_path(arg)
end

local function startup_file_arg()
  if vim.fn.argc() ~= 1 then
    return nil
  end

  local arg = vim.fn.argv(0)
  if vim.fn.filereadable(arg) ~= 1 then
    return nil
  end

  return normalize_path(arg)
end

function M.normalize_path(path)
  return normalize_path(path)
end

function M.project_root_for_path(path)
  return project_root_for_path(path)
end

function M.startup_context()
  local file_arg = startup_file_arg()
  if file_arg then
    return {
      kind = "file",
      root = project_root_for_path(file_arg),
      file = file_arg,
    }
  end

  local dir_arg = startup_directory_arg()
  if dir_arg then
    return {
      kind = "directory",
      root = project_root_for_path(dir_arg),
      directory = dir_arg,
    }
  end

  if vim.fn.argc() > 1 then
    return {
      kind = "multiple",
      root = project_root_for_path(vim.fn.getcwd()),
    }
  end

  return {
    kind = "default",
    root = project_root_for_path(vim.fn.getcwd()),
  }
end

function M.restore_allowed()
  return M.restore_allowed_for_context(M.startup_context())
end

function M.restore_allowed_for_context(context)
  return type(context) == "table" and (context.kind == "directory" or context.kind == "default")
end

function M.state_path_for_root(root)
  return state_path(root)
end

function M.read_root_state(root)
  local path = state_path(root)
  if not path then
    return nil
  end

  local file = io.open(path, "r")
  if not file then
    return nil
  end

  local content = file:read("*a")
  file:close()
  if content == nil or content == "" then
    return nil
  end

  local ok, decoded = pcall(vim.json.decode, content)
  if ok and type(decoded) == "table" then
    return decoded
  end

  return nil
end

function M.write_root_state(root, state)
  local path = state_path(root)
  if not path then
    return false
  end

  ensure_state_dir()
  local file = io.open(path, "w")
  if not file then
    return false
  end

  file:write(vim.json.encode(state))
  file:close()
  return true
end

function M.update_root_state(root, updater)
  local current = M.read_root_state(root) or {
    version = 2,
    root = normalize_path(root),
    tabs = {},
    recent_files = {},
  }

  local updated = updater(current) or current
  if type(updated) == "table" then
    updated.version = 2
    updated.root = normalize_path(root)
    M.write_root_state(root, updated)
  end

  return updated
end

local function recent_files_from_state(state)
  local recent_files = {}
  local seen = {}
  local function add(path)
    path = normalize_path(path)
    if not path or seen[path] or vim.fn.filereadable(path) ~= 1 then
      return
    end

    seen[path] = true
    recent_files[#recent_files + 1] = path
  end

  if type(state) == "table" then
    for _, path in ipairs(type(state.recent_files) == "table" and state.recent_files or {}) do
      add(path)
    end
    if type(state.last) == "string" then
      add(state.last)
    end
  elseif type(state) == "string" then
    add(state)
  end

  return recent_files
end

local function legacy_recent_files_for_root(root)
  local file = io.open(legacy_recent_files_path, "r")
  if not file then
    return {}
  end

  local content = file:read("*a")
  file:close()
  local ok, decoded = pcall(vim.json.decode, content or "")
  if not ok or type(decoded) ~= "table" then
    return {}
  end

  local entry = decoded[root]
  return recent_files_from_state(entry)
end

function M.recent_files_for_root(root)
  local state = M.read_root_state(root)
  if state then
    local recent = recent_files_from_state(state)
    if #recent > 0 then
      return recent
    end
  end

  return legacy_recent_files_for_root(root)
end

local function tab_paths_from_legacy_state(root, tabs)
  local paths = {}
  local seen = {}
  for _, tab_state in ipairs(tabs) do
    local buffers = type(tab_state.buffers) == "table" and tab_state.buffers or {}
    for _, path in ipairs(buffers) do
      path = normalize_path(path)
      if path and not seen[path] and vim.fn.filereadable(path) == 1 and vim.startswith(path, root .. "/") or path == root then
        seen[path] = true
        paths[#paths + 1] = path
      end
    end

    local layout = type(tab_state.layout) == "table" and tab_state.layout or nil
    local leaf = layout and layout.buffer or nil
    if leaf and leaf.type == "file" then
      local path = normalize_path(leaf.path)
      if path and not seen[path] and vim.fn.filereadable(path) == 1 and (path == root or vim.startswith(path, root .. "/")) then
        seen[path] = true
        paths[#paths + 1] = path
      end
    end
  end
  return paths
end

function M.legacy_tab_state_for_root(root)
  local file = io.open(legacy_tab_state_path, "r")
  if not file then
    return nil
  end

  local content = file:read("*a")
  file:close()
  if content == nil or content == "" then
    return nil
  end

  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" or type(decoded.tabs) ~= "table" then
    return nil
  end

  local tabs = {}
  for _, tab_state in ipairs(decoded.tabs) do
    local buffers = type(tab_state.buffers) == "table" and tab_state.buffers or {}
    local keep = false
    for _, path in ipairs(buffers) do
      path = normalize_path(path)
      if path and (path == root or vim.startswith(path, root .. "/")) then
        keep = true
        break
      end
    end

    if keep then
      tabs[#tabs + 1] = tab_state
    end
  end

  if #tabs == 0 then
    return nil
  end

  local state = {
    version = 2,
    root = normalize_path(root),
    active_tab_id = decoded.active_tab_id,
    next_tab_id = decoded.next_tab_id,
    tabs = tabs,
    recent_files = legacy_recent_files_for_root(root),
  }

  local paths = tab_paths_from_legacy_state(root, tabs)
  if #state.recent_files == 0 then
    state.recent_files = paths
  end

  return state
end

return M
