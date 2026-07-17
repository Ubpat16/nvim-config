local M = {}

local CONFIG_NAME = "nvim.config"
local cache = {}

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

  if vim.fn.isdirectory(path) == 1 then
    return path
  end
  return vim.fn.fnamemodify(path, ":h")
end

local function find_config(start_path)
  local start = start_directory(start_path)
  if not start then
    return nil
  end

  local path = vim.fs.find(CONFIG_NAME, { path = start, upward = true, type = "file" })[1]
  return normalize(path)
end

local function fingerprint(stat)
  local mtime = stat and stat.mtime or {}
  return table.concat({ stat and stat.size or 0, mtime.sec or 0, mtime.nsec or 0 }, ":")
end

local function validate(decoded)
  if type(decoded) ~= "table" or not vim.islist(decoded) then
    local neotest = decoded.neotest
    if neotest == nil then
      return { neotest = { args = {} } }
    end
    if type(neotest) ~= "table" or vim.islist(neotest) then
      return nil, "neotest must be an object"
    end

    local args = neotest.args
    if args == nil then
      return { neotest = { args = {} } }
    end
    if type(args) ~= "table" or not vim.islist(args) then
      return nil, "neotest.args must be an array of strings"
    end
    for index, arg in ipairs(args) do
      if type(arg) ~= "string" then
        return nil, "neotest.args[" .. index .. "] must be a string"
      end
    end

    return { neotest = { args = vim.deepcopy(args) } }
  end

  return nil, "top-level value must be an object"
end

local function load_config(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    cache[path] = nil
    return { neotest = { args = {} } }
  end

  local version = fingerprint(stat)
  local cached = cache[path]
  if cached and cached.version == version then
    return cached.config
  end

  local file = io.open(path, "r")
  local content = file and file:read("*a") or nil
  if file then
    file:close()
  end

  local decoded_ok, decoded = pcall(vim.json.decode, content or "")
  local config, error_message
  if decoded_ok then
    config, error_message = validate(decoded)
  else
    error_message = "invalid JSON"
  end

  if not config then
    config = { neotest = { args = {} } }
    vim.notify(CONFIG_NAME .. ": " .. error_message .. " (" .. path .. ")", vim.log.levels.WARN)
  end

  cache[path] = { version = version, config = config }
  return config
end

function M.neotest_args(start_path)
  local path = find_config(start_path)
  if not path then
    return {}
  end
  return vim.deepcopy(load_config(path).neotest.args)
end

return M
