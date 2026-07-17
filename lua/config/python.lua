local M = {}

local cached_global_python = nil
local cached_project_pythons = {}

local function normalize_executable(path)
  if not path or path == "" then
    return nil
  end

  local expanded = vim.fn.expand(path)
  if vim.fn.executable(expanded) ~= 1 then
    return nil
  end

  return vim.fs.normalize(vim.uv.fs_realpath(expanded) or expanded)
end

local function normalize_venv_executable(path)
  if not path or path == "" then
    return nil
  end

  local expanded = vim.fn.expand(path)
  if vim.fn.executable(expanded) ~= 1 then
    return nil
  end

  return vim.fs.normalize(expanded)
end

local function pyenv_global_python()
  local pyenv_root = vim.env.PYENV_ROOT
  if not pyenv_root or pyenv_root == "" then
    pyenv_root = vim.fs.joinpath(vim.fn.expand("~"), ".pyenv")
  end

  local version_file = vim.fs.joinpath(pyenv_root, "version")
  local ok, lines = pcall(vim.fn.readfile, version_file)
  if not ok or not lines or #lines == 0 then
    return nil
  end

  local version = vim.trim(lines[1] or ""):match("^(%S+)")
  if not version or version == "" or version == "system" then
    return nil
  end

  for _, executable in ipairs({ "python3", "python" }) do
    local candidate = vim.fs.joinpath(pyenv_root, "versions", version, "bin", executable)
    local normalized = normalize_executable(candidate)
    if normalized then
      return normalized
    end
  end

  return nil
end

local function project_root(bufnr, start_dir)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local root = vim.fs.root(bufnr, { ".venv", "venv", "env", "uv.lock", "pyproject.toml", "pytest.ini", "manage.py", ".git" })
    if root then
      return root
    end
  end

  if not start_dir or start_dir == "" then
    start_dir = vim.fn.getcwd()
  end

  local marker = vim.fs.find({ ".venv", "venv", "env", "uv.lock", "pyproject.toml", "pytest.ini", "manage.py", ".git" }, {
    path = start_dir,
    upward = true,
  })[1]

  if marker then
    return vim.fn.fnamemodify(marker, ":p:h")
  end

  return vim.fs.normalize(vim.fn.fnamemodify(start_dir, ":p"))
end

--- Walk upward from `start_dir` and return the first usable project venv interpreter.
---@param start_dir string|nil
---@return string|nil
local function find_venv_python(start_dir)
  if not start_dir or start_dir == "" then
    start_dir = vim.fn.getcwd()
  end

  local cur = vim.fs.normalize(vim.fn.fnamemodify(start_dir, ":p"))
  local rels = {
    ".venv/bin/python3",
    ".venv/bin/python",
    "venv/bin/python3",
    "venv/bin/python",
    "env/bin/python3",
    "env/bin/python",
  }

  for _ = 1, 48 do
    for _, rel in ipairs(rels) do
      local normalized = normalize_venv_executable(vim.fs.joinpath(cur, rel))
      if normalized then
        return normalized
      end
    end

    local parent = vim.fn.fnamemodify(cur, ":h")
    if parent == cur then
      break
    end
    cur = parent
  end

  return nil
end

function M.global_python()
  if cached_global_python and vim.fn.executable(cached_global_python) == 1 then
    return cached_global_python
  end

  for _, candidate in ipairs({
    function()
      return vim.env.NVIM_PYTHON
    end,
    function()
      return vim.g.python3_host_prog
    end,
    pyenv_global_python,
    function()
      return vim.fn.exepath("python3")
    end,
    function()
      return vim.fn.exepath("python")
    end,
  }) do
    local candidate_path = candidate()
    local normalized = normalize_executable(candidate_path)
    if normalized then
      cached_global_python = normalized
      return cached_global_python
    end
  end

  return nil
end

function M.setup_global_python()
  local py = M.global_python()
  if not py then
    return nil
  end

  vim.g.python3_host_prog = py
  return py
end

--- Resolve the interpreter Python tools should use for a buffer or directory.
--- Project virtualenvs are preferred; Neovim's own host Python is the fallback.
---@param bufnr integer|nil
---@param start_dir string|nil
---@return string|nil
function M.project_python(bufnr, start_dir)
  local name = nil
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
      start_dir = vim.fn.fnamemodify(name, ":p:h")
    end
  end

  local root = project_root(bufnr, start_dir)
  if root and cached_project_pythons[root] and vim.fn.executable(cached_project_pythons[root]) == 1 then
    return cached_project_pythons[root]
  end

  local py = find_venv_python(start_dir or root)
  if not py and root then
    py = find_venv_python(root)
  end

  if py and root then
    cached_project_pythons[root] = py
    return py
  end

  return M.global_python()
end

---@param bufnr integer|nil
---@param start_dir string|nil
---@return table|nil
function M.project_python_env(bufnr, start_dir)
  local py = M.project_python(bufnr, start_dir)
  if not py then
    return nil
  end

  local bin_dir = vim.fn.fnamemodify(py, ":h")
  local venv_root = vim.fn.fnamemodify(py, ":h:h")
  local path = vim.env.PATH or ""
  if path ~= "" then
    path = bin_dir .. ":" .. path
  else
    path = bin_dir
  end

  return {
    PATH = path,
    PYTHON = py,
    PYTHON3 = py,
    VIRTUAL_ENV = venv_root,
  }
end

function M.global_python_env()
  return M.project_python_env()
end

--- Point Python language tooling at the active project's interpreter.
---@param bufnr integer
function M.apply_project_python(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local ft = vim.bo[bufnr].filetype
  local name = vim.api.nvim_buf_get_name(bufnr)
  if ft ~= "python" and not (name ~= "" and name:lower():match("%.py$")) then
    return
  end

  local py = M.project_python(bufnr)
  if not py then
    return
  end

  local global_py = M.global_python()
  if py ~= global_py then
    vim.env.VIRTUAL_ENV = vim.fn.fnamemodify(py, ":h:h")
  end

  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if client.name == "pyright" then
      client.settings = client.settings or {}
      client.settings.python = vim.tbl_deep_extend("force", client.settings.python or {}, { pythonPath = py })
      client:notify("workspace/didChangeConfiguration", { settings = nil })
    end
  end
end

M.apply_global_python = M.apply_project_python

M.setup_global_python()

return M
