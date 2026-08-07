local M = {}

local legacy_state_paths = {
  vim.fs.joinpath(vim.fn.stdpath("state"), "tab-state.json"),
  vim.fs.joinpath(vim.fn.stdpath("state"), "last-project-file.json"),
}
local project_markers = {
  ".git",
  "pyproject.toml",
  "package.json",
  "manage.py",
  "Cargo.toml",
  "go.mod",
  "Makefile",
}
local project_root_cache = {}

local function normalize_path(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end

  local expanded = vim.fn.fnamemodify(path, ":p")
  local real = vim.uv.fs_realpath(expanded)
  return vim.fs.normalize(real or expanded)
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

  local cache_key = normalize_path(start)
  if cache_key and project_root_cache[cache_key] then
    return project_root_cache[cache_key]
  end

  local git_marker = vim.fs.find({ ".git" }, { path = start, upward = true })[1]
  if git_marker then
    local root = normalize_path(vim.fn.fnamemodify(git_marker, ":h"))
    if cache_key then
      project_root_cache[cache_key] = root
    end
    return root
  end

  local marker = vim.fs.find(project_markers, { path = start, upward = true })[1]
  local root = marker and vim.fn.fnamemodify(marker, ":h") or vim.fn.getcwd()
  root = normalize_path(root)
  if cache_key then
    project_root_cache[cache_key] = root
  end
  return root
end

function M.normalize_path(path)
  return normalize_path(path)
end

function M.project_root_for_path(path)
  return project_root_for_path(path)
end

function M.clear_obsolete_state()
  for _, path in ipairs(legacy_state_paths) do
    if vim.fn.filereadable(path) == 1 then
      vim.fn.delete(path)
    end
  end
end

return M
