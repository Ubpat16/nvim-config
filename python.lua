local M = {}

local cached_global_python = nil

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

function M.global_python_env()
  local py = M.setup_global_python()
  if not py then
    return nil
  end

  local bin_dir = vim.fn.fnamemodify(py, ":h")
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
    VIRTUAL_ENV = "",
  }
end

--- Point Python tooling at the global Neovim interpreter.
---@param bufnr integer
function M.apply_global_python(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local ft = vim.bo[bufnr].filetype
  local name = vim.api.nvim_buf_get_name(bufnr)
  if ft ~= "python" and not (name ~= "" and name:lower():match("%.py$")) then
    return
  end

  local py = M.setup_global_python()
  if not py then
    return
  end

  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if client.name == "pyright" then
      client.settings = client.settings or {}
      client.settings.python = vim.tbl_deep_extend("force", client.settings.python or {}, { pythonPath = py })
      client:notify("workspace/didChangeConfiguration", { settings = nil })
    end
  end
end

M.setup_global_python()

return M
