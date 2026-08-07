local project_config = require("config.project_config")

local M = {}

local function unquote(value)
  value = vim.trim(value)
  local first, last = value:sub(1, 1), value:sub(-1)
  if (first == "\"" and last == "\"") or (first == "'" and last == "'") then
    return value:sub(2, -2)
  end
  return value
end

local function read_env(path)
  local values = {}
  local file = io.open(path, "r")
  if not file then
    return values
  end

  for line in file:lines() do
    local key, value = line:match("^%s*export%s+([%w_]+)%s*=%s*(.-)%s*$")
    if not key then
      key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    end
    if key and value and value:sub(1, 1) ~= "#" then
      values[key] = unquote(value)
    end
  end
  file:close()
  return values
end

local function encode(value)
  if not value or value == "" then
    return ""
  end
  local ok, encoded = pcall(vim.uri_encode, value)
  return ok and encoded or value
end

local function database_type(url)
  local scheme = url:match("^([%w_]+)://")
  if scheme == "postgresql" then
    return "postgres"
  end
  return scheme
end

local function project_env(start_path)
  local profile = project_config.get(start_path)
  if profile.django.env_file and vim.uv.fs_stat(profile.django.env_file) then
    return profile.django.env_file
  end

  local env_file = vim.fs.find(".env", {
    path = start_path,
    upward = true,
    type = "file",
  })[1]
  return env_file
end

local function connection_from_env(env, name, db_name)
  local url = env.DATABASE_URL or env.DB_URL
  if url and url ~= "" then
    return {
      name = name,
      type = database_type(url),
      url = url,
    }
  end

  local engine = (env.DB_ENGINE or ""):lower()
  local sqlite_path = env.SQLITE_DB or env.SQLITE_DATABASE
  if engine:find("sqlite", 1, true) or sqlite_path then
    return {
      name = name,
      type = "sqlite",
      url = sqlite_path or db_name or "db.sqlite3",
    }
  end

  if env.DB_HOST and db_name then
    local user = encode(env.DB_USER or "")
    local password = encode(env.DB_PASS or env.DB_PASSWORD or "")
    local credentials = user
    if password ~= "" then
      credentials = credentials .. ":" .. password
    end
    if credentials ~= "" then
      credentials = credentials .. "@"
    end
    local port = env.DB_PORT or "5432"
    local sslmode = env.DB_SSLMODE or "disable"
    return {
      name = name,
      type = "postgres",
      url = string.format("postgres://%s%s:%s/%s?sslmode=%s", credentials, env.DB_HOST, port, db_name, sslmode),
    }
  end
end

M.ProjectSource = {}

function M.ProjectSource:new()
  local source = {}
  setmetatable(source, self)
  self.__index = self
  return source
end

function M.ProjectSource:name()
  return "project environment"
end

function M.ProjectSource:load()
  local env_file = project_env(project_config.start_path())
  if not env_file then
    return {}
  end

  local env = read_env(env_file)
  local connections = {}
  local primary = connection_from_env(env, vim.fs.basename(vim.fs.dirname(env_file)), env.DB_NAME)
  if primary then
    primary.id = "project_source_primary"
    table.insert(connections, primary)
  end

  if env.BATCHES_DB_NAME and env.BATCHES_DB_NAME ~= env.DB_NAME then
    local batches = connection_from_env(env, "Batches database", env.BATCHES_DB_NAME)
    if batches then
      batches.id = "project_source_batches"
      table.insert(connections, batches)
    end
  end

  return connections
end

return M
