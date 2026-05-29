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

  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("silent update")
  end)
end

local lc_last_file_state_path = vim.fs.joinpath(vim.fn.stdpath("state"), "last-project-file.json")
local lc_max_recent_project_files = 10
local lc_project_markers = {
  ".git",
  "pyproject.toml",
  "package.json",
  "manage.py",
  "Cargo.toml",
  "go.mod",
  "Makefile",
}

local function lc_read_last_file_state()
  local file = io.open(lc_last_file_state_path, "r")
  if not file then
    return {}
  end

  local content = file:read("*a")
  file:close()

  local ok, decoded = pcall(vim.json.decode, content)
  if ok and type(decoded) == "table" then
    return decoded
  end
  return {}
end

local lc_last_file_state = lc_read_last_file_state()

local function lc_project_state_entry(root)
  if not root then
    return nil
  end

  local entry = lc_last_file_state[root]
  if type(entry) == "table" then
    if type(entry.files) ~= "table" then
      entry.files = {}
    end
    return entry
  end

  entry = {
    last = type(entry) == "string" and entry or nil,
    files = type(entry) == "string" and { entry } or {},
  }
  lc_last_file_state[root] = entry
  return entry
end

local function lc_last_project_file(root)
  local entry = lc_last_file_state[root]
  if type(entry) == "table" then
    return entry.last
  end
  if type(entry) == "string" then
    return entry
  end
  return nil
end

local function lc_recent_project_files(root)
  local entry = lc_last_file_state[root]
  if type(entry) == "table" and type(entry.files) == "table" then
    return entry.files
  end
  if type(entry) == "string" then
    return { entry }
  end
  return {}
end

local function lc_is_path_inside(parent, child)
  if type(parent) ~= "string" or type(child) ~= "string" then
    return false
  end

  parent = vim.fs.normalize(parent)
  child = vim.fs.normalize(child)
  return child == parent or vim.startswith(child, parent .. "/")
end

local function lc_add_unique_readable_file(files, seen, path)
  if type(path) ~= "string" or path == "" or seen[path] or vim.fn.filereadable(path) ~= 1 then
    return
  end

  seen[path] = true
  files[#files + 1] = path
end

local function lc_recent_project_files_for_root(root)
  local files = {}
  local seen = {}
  local legacy_files = {}
  local legacy_seen = {}

  local function add_entry(entry, target_files, target_seen)
    if type(entry) == "table" then
      if type(entry.last) == "string" then
        lc_add_unique_readable_file(target_files, target_seen, entry.last)
      end
      for _, path in ipairs(type(entry.files) == "table" and entry.files or {}) do
        lc_add_unique_readable_file(target_files, target_seen, path)
      end
    elseif type(entry) == "string" then
      lc_add_unique_readable_file(legacy_files, legacy_seen, entry)
    end
  end

  add_entry(lc_last_file_state[root], files, seen)

  local nested_roots = {}
  for entry_root, entry in pairs(lc_last_file_state) do
    if entry_root ~= root and lc_is_path_inside(root, entry_root) and type(entry) == "table" then
      nested_roots[#nested_roots + 1] = entry_root
    end
  end
  table.sort(nested_roots)

  for _, entry_root in ipairs(nested_roots) do
    add_entry(lc_last_file_state[entry_root], files, seen)
  end

  for entry_root, entry in pairs(lc_last_file_state) do
    if entry_root ~= root and lc_is_path_inside(root, entry_root) and type(entry) == "string" then
      add_entry(entry, legacy_files, legacy_seen)
    end
  end

  for _, path in ipairs(legacy_files) do
    lc_add_unique_readable_file(files, seen, path)
  end

  while #files > lc_max_recent_project_files do
    table.remove(files)
  end

  return files
end

local function lc_normalize_path(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end

  local expanded = vim.fn.fnamemodify(path, ":p")
  local real = vim.uv.fs_realpath(expanded)
  return vim.fs.normalize(real or expanded)
end

local function lc_write_last_file_state()
  vim.fn.mkdir(vim.fn.fnamemodify(lc_last_file_state_path, ":h"), "p")
  local file = io.open(lc_last_file_state_path, "w")
  if not file then
    return
  end

  file:write(vim.json.encode(lc_last_file_state))
  file:close()
end

local function lc_project_root_for_path(path)
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
    return lc_normalize_path(vim.fn.fnamemodify(git_marker, ":h"))
  end

  local marker = vim.fs.find(lc_project_markers, { path = start, upward = true })[1]
  local root = marker and vim.fn.fnamemodify(marker, ":h") or vim.fn.getcwd()
  return lc_normalize_path(root)
end

local function lc_remember_last_project_file(bufnr)
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

  local entry = lc_project_state_entry(root)
  if not entry then
    return
  end

  entry.last = normalized_path

  local files = {}
  for _, existing in ipairs(entry.files) do
    if existing ~= normalized_path and vim.fn.filereadable(existing) == 1 then
      files[#files + 1] = existing
    end
  end

  table.insert(files, 1, normalized_path)
  while #files > lc_max_recent_project_files do
    table.remove(files)
  end
  entry.files = files
  lc_write_last_file_state()
end

local function lc_forget_project_file(path)
  local normalized_path = lc_normalize_path(path)
  if not normalized_path then
    return false
  end

  local changed = false
  local roots_to_delete = {}

  for root, entry in pairs(lc_last_file_state) do
    if type(entry) == "table" then
      local files = {}
      for _, existing in ipairs(type(entry.files) == "table" and entry.files or {}) do
        if lc_normalize_path(existing) == normalized_path then
          changed = true
        else
          files[#files + 1] = existing
        end
      end

      entry.files = files
      if lc_normalize_path(entry.last) == normalized_path then
        entry.last = files[1]
        changed = true
      end

      if entry.last == nil and #entry.files == 0 then
        roots_to_delete[#roots_to_delete + 1] = root
      end
    elseif lc_normalize_path(entry) == normalized_path then
      roots_to_delete[#roots_to_delete + 1] = root
      changed = true
    end
  end

  for _, root in ipairs(roots_to_delete) do
    lc_last_file_state[root] = nil
  end

  if changed then
    lc_write_last_file_state()
  end

  return changed
end

local function lc_startup_project_root()
  local argc = vim.fn.argc()
  if argc == 1 and vim.fn.isdirectory(vim.fn.argv(0)) == 1 then
    return lc_project_root_for_path(vim.fn.argv(0))
  end

  return lc_project_root_for_path(vim.fn.getcwd())
end

local function lc_startup_directory_arg()
  if vim.fn.argc() ~= 1 then
    return nil
  end

  local arg = vim.fn.argv(0)
  if vim.fn.isdirectory(arg) ~= 1 then
    return nil
  end

  return lc_normalize_path(arg)
end

local function lc_apply_startup_directory()
  local dir = lc_startup_directory_arg()
  if not dir then
    return
  end

  local current = lc_normalize_path(vim.fn.getcwd())
  if current == dir then
    return
  end

  vim.cmd.cd(vim.fn.fnameescape(dir))
end

local function lc_current_project_root()
  local path = vim.api.nvim_buf_get_name(0)
  if path ~= "" and vim.fn.filereadable(path) == 1 then
    return lc_project_root_for_path(path)
  end

  return lc_startup_project_root()
end

local function lc_restore_last_project_file()
  local argc = vim.fn.argc()
  if argc > 0 then
    for index = 0, argc - 1 do
      if vim.fn.isdirectory(vim.fn.argv(index)) ~= 1 then
        return
      end
    end
  end

  local root = lc_startup_project_root()
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
  local root = lc_startup_project_root()
  if not root or lc_restored_project_roots[root] then
    return
  end

  lc_restored_project_roots[root] = true
  lc_restore_last_project_file()
  lc_remember_last_project_file(vim.api.nvim_get_current_buf())
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
    lc_apply_startup_directory()
    vim.defer_fn(function()
      lc_restore_last_project_file_once()
    end, 150)
  end,
})

vim.api.nvim_create_autocmd("UIEnter", {
  group = vim.api.nvim_create_augroup("restore_last_project_file_ui", { clear = true }),
  callback = function()
    lc_apply_startup_directory()
    vim.defer_fn(function()
      lc_restore_last_project_file_once()
    end, 150)
  end,
})

vim.defer_fn(function()
  lc_apply_startup_directory()
  lc_restore_last_project_file_once()
end, 300)

vim.api.nvim_create_user_command("LastProjectFile", function()
  lc_remember_last_project_file(vim.api.nvim_get_current_buf())
  local root = lc_current_project_root()
  local files = root and lc_recent_project_files_for_root(root) or {}
  local path = files[1] or (root and lc_last_project_file(root) or nil)
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
