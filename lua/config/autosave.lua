local project_config = require("config.project_config")

local function lc_autosave_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if not vim.bo[bufnr].modified then
    return
  end
  if vim.bo[bufnr].readonly or not vim.bo[bufnr].modifiable then
    return
  end
  if vim.bo[bufnr].buftype ~= "" then
    return
  end
  if vim.api.nvim_buf_get_name(bufnr) == "" then
    return
  end
  if not project_config.get(project_config.start_path(bufnr)).editor.autosave then
    return
  end

  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("silent update")
  end)
end

local project_state = require("config.project_state")
local lc_max_recent_project_files = 10
local lc_remember_last_project_file
local function lc_normalize_path(path)
  return project_state.normalize_path(path)
end

local function lc_project_root_for_path(path)
  return project_state.project_root_for_path(path)
end

local function lc_recent_project_files_for_root(root)
  return project_state.recent_files_for_root(root)
end

local function lc_current_project_root()
  local path = vim.api.nvim_buf_get_name(0)
  if path ~= "" and vim.fn.filereadable(path) == 1 then
    return project_state.project_root_for_path(path)
  end

  return project_state.startup_context().root
end

local function lc_restore_last_project_file()
  local context = project_state.startup_context()
  if context.kind == "file" or context.kind == "multiple" then
    return
  end

  local root = context.root
  local recent_files = lc_recent_project_files_for_root(root)
  local path = recent_files[1]
  if type(path) ~= "string" or path == "" then
    return
  end

  local current = vim.api.nvim_buf_get_name(0)
  if current ~= "" and vim.fn.filereadable(current) == 1 then
    return
  end

  for _, recent_path in ipairs(recent_files) do
    if recent_path ~= path and vim.fn.filereadable(recent_path) == 1 then
      vim.cmd.badd(vim.fn.fnameescape(recent_path))
    end
  end

  vim.cmd.edit(vim.fn.fnameescape(path))
end

local lc_restored_project_roots = {}

local function lc_restore_last_project_file_once()
  local context = project_state.startup_context()
  local root = context.root
  if not root or lc_restored_project_roots[root] then
    return
  end

  lc_restored_project_roots[root] = true
  lc_restore_last_project_file()
  lc_remember_last_project_file(vim.api.nvim_get_current_buf())
end

lc_remember_last_project_file = function(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if vim.b[bufnr].lc_forget_project_file_on_close then
    return
  end
  if vim.bo[bufnr].buftype ~= "" then
    return
  end

  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" or vim.fn.filereadable(path) ~= 1 then
    return
  end

  local root = lc_project_root_for_path(path)
  local normalized_path = lc_normalize_path(path)
  if not root or not normalized_path then
    return
  end

  project_state.update_root_state(root, function(state)
    local files = {}
    for _, existing in ipairs(type(state.recent_files) == "table" and state.recent_files or {}) do
      if existing ~= normalized_path and vim.fn.filereadable(existing) == 1 then
        files[#files + 1] = existing
      end
    end

    table.insert(files, 1, normalized_path)
    while #files > lc_max_recent_project_files do
      table.remove(files)
    end

    state.recent_files = files
    state.last = normalized_path
    return state
  end)
end

local function lc_forget_project_file(path)
  local normalized_path = lc_normalize_path(path)
  if not normalized_path then
    return false
  end

  local changed = false
  project_state.update_root_state(project_state.project_root_for_path(normalized_path), function(state)
    local files = {}
    for _, existing in ipairs(type(state.recent_files) == "table" and state.recent_files or {}) do
      if lc_normalize_path(existing) == normalized_path then
        changed = true
      elseif vim.fn.filereadable(existing) == 1 then
        files[#files + 1] = existing
      end
    end

    if lc_normalize_path(state.last) == normalized_path then
      state.last = files[1]
      changed = true
    end

    state.recent_files = files
    return state
  end)

  return changed
end

-- Auto-save file buffers when moving away from them
vim.api.nvim_create_autocmd({ "BufLeave", "BufWinLeave", "FocusLost", "VimLeavePre" }, {
  group = vim.api.nvim_create_augroup("autosave_on_leave", { clear = true }),
  callback = function(args)
    lc_autosave_buffer(args.buf)
  end,
})

vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "VimLeavePre" }, {
  group = vim.api.nvim_create_augroup("last_project_file", { clear = true }),
  callback = function(args)
    lc_remember_last_project_file(args.buf)
  end,
})

vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("restore_last_project_file", { clear = true }),
  callback = function()
    vim.defer_fn(function()
      lc_restore_last_project_file_once()
    end, 150)
  end,
})

vim.api.nvim_create_autocmd("UIEnter", {
  group = vim.api.nvim_create_augroup("restore_last_project_file_ui", { clear = true }),
  callback = function()
    vim.defer_fn(function()
      lc_restore_last_project_file_once()
    end, 150)
  end,
})

vim.defer_fn(function()
  lc_restore_last_project_file_once()
end, 300)

vim.api.nvim_create_user_command("LastProjectFile", function()
  lc_remember_last_project_file(vim.api.nvim_get_current_buf())
  local root = lc_current_project_root()
  local files = root and lc_recent_project_files_for_root(root) or {}
  local path = files[1]
  print("Project: " .. (root or "unknown"))
  print("Last file: " .. (path or "none"))
end, {
  desc = "Show remembered file for the current project",
})

vim.api.nvim_create_user_command("LastProjectFileOpen", function()
  lc_restore_last_project_file()
end, {
  desc = "Open remembered file for the current project",
})

vim.api.nvim_create_user_command("LastProjectFileForget", function(opts)
  local path = opts.args ~= "" and opts.args or vim.api.nvim_buf_get_name(0)
  if lc_forget_project_file(path) then
    print("Forgot project file: " .. path)
  else
    print("Project file was not remembered: " .. path)
  end
end, {
  nargs = "?",
  complete = "file",
  desc = "Remove a file from remembered project files",
})

vim.api.nvim_create_user_command("LastProjectFiles", function()
  local root = lc_current_project_root()
  print("Project: " .. (root or "unknown"))
  for index, path in ipairs(root and lc_recent_project_files_for_root(root) or {}) do
    print(index .. ". " .. path)
  end
end, {
  desc = "Show remembered files for the current project",
})

-- Auto-create missing directories on save
vim.api.nvim_create_autocmd("BufWritePre", {
  callback = function(event)
    local file = event.match
    local dir = vim.fn.fnamemodify(file, ":p:h")
    if vim.fn.isdirectory(dir) == 0 then
      vim.fn.mkdir(dir, "p")
    end
  end,
})
