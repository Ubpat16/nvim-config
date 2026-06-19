local M = {}

local function state_path(...)
  return vim.fs.joinpath(vim.fn.stdpath("state"), ...)
end

local function log_path()
  local ok, path = pcall(vim.fn.stdpath, "log")
  if ok and path and path ~= "" then
    return path
  end
  return vim.fn.stdpath("state")
end

local function nvim_log_path()
  return vim.fs.joinpath(log_path(), "nvim.log")
end

local sources = {
  nvim = {
    paths = function()
      return { nvim_log_path() }
    end,
  },
  copilot = {
    paths = function()
      return { state_path("copilot-lua.log") }
    end,
  },
  codex = {
    paths = function()
      return { state_path("codex", "notify.jsonl") }
    end,
  },
  openai = {
    paths = function()
      return { state_path("openai.log") }
    end,
  },
}

local groups = {
  ai = { "openai", "copilot", "codex" },
  all = { "nvim", "openai", "copilot", "codex" },
}

local function ensure_file(path)
  local directory = vim.fs.dirname(path)
  if directory then
    vim.fn.mkdir(directory, "p")
  end

  if vim.fn.filereadable(path) == 0 then
    vim.fn.writefile({}, path)
  end
end

local function source_paths(name)
  local source = sources[name]
  if not source then
    return {}
  end
  return source.paths()
end

function M.path(name)
  return source_paths(name)[1]
end

function M.paths(name)
  local selected = groups[name] or { name }
  local paths = {}

  for _, source_name in ipairs(selected) do
    vim.list_extend(paths, source_paths(source_name))
  end

  return paths
end

function M.write(source_name, level, message, context)
  local path = M.path(source_name)
  if not path then
    return
  end

  ensure_file(path)

  local entry = {
    time = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    level = level,
    message = message,
    context = context or vim.empty_dict(),
  }

  vim.fn.writefile({ vim.json.encode(entry) }, path, "a")
end

local function source_complete()
  local names = vim.tbl_keys(sources)
  vim.list_extend(names, vim.tbl_keys(groups))
  table.sort(names)
  return names
end

function M.open(name)
  name = name ~= "" and name or "all"

  local paths = M.paths(name)
  if #paths == 0 then
    vim.notify("Unknown log source: " .. name, vim.log.levels.WARN)
    return
  end

  for _, path in ipairs(paths) do
    ensure_file(path)
  end

  local escaped_paths = vim.tbl_map(vim.fn.shellescape, paths)
  vim.cmd("botright split")
  vim.cmd("terminal tail -n 200 -F " .. table.concat(escaped_paths, " "))
  vim.bo.buflisted = false
  vim.bo.bufhidden = "wipe"
  pcall(vim.api.nvim_buf_set_name, 0, ("Plugin logs: %s %s"):format(name, os.time()))
  vim.cmd("startinsert")
end

function M.create_commands()
  vim.api.nvim_create_user_command("PluginLogs", function(opts)
    M.open(opts.args)
  end, {
    nargs = "?",
    force = true,
    complete = function()
      return source_complete()
    end,
    desc = "Tail plugin logs",
  })

  vim.api.nvim_create_user_command("AILogs", function()
    M.open("ai")
  end, { force = true, desc = "Tail AI plugin logs" })
end

return M
