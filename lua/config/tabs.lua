local M = {}

local routing_duplicate = false
local creating_workspace = false
local creating_tab = false
local clearing_buffers = false
local restoring_tabs = false
local persisting_tabs = false
local jumplist_navigation_depth = 0
local buffer_ownership = {}
local tab_buffers = {}
local tab_all_buffers = {}
local tab_floats = {}
local tab_workspaces = {}
local buffer_last_tabs = {}
local window_buffer_cursors = {}
local tab_buffer_cursors = {}
local register_buffer_ownership
local tab_workspace
local normalized_buffer_name
local project_state = require("config.project_state")
local workspaces = {}
local workspace_order = {}
local active_workspace = nil
local next_workspace_id = 1
local next_tab_id = 1
local file_preview = {
  bufnr = nil,
  winid = nil,
}
local remove_tab_from_workspace

local function valid_buf(bufnr)
  return type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr)
end

local function valid_win(win)
  return type(win) == "number" and vim.api.nvim_win_is_valid(win)
end

local function is_floating_window(win)
  if not valid_win(win) then
    return false
  end

  local ok, config = pcall(vim.api.nvim_win_get_config, win)
  return ok and config.relative ~= ""
end

local function close_win(win)
  if valid_win(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
end

local function normalize_path(path)
  path = vim.trim(tostring(path or ""))
  if path == "" then
    return nil
  end

  path = vim.fn.expand(path)
  if not path:match("^/") then
    path = vim.fs.joinpath(vim.fn.getcwd(), path)
  end

  local real = vim.uv.fs_realpath(path)
  return vim.fs.normalize(real or vim.fn.fnamemodify(path, ":p"))
end

local function readable_file(path)
  return path and vim.fn.filereadable(path) == 1 and vim.fn.isdirectory(path) == 0
end

function M.is_normal_file_buffer(bufnr)
  if not valid_buf(bufnr) then
    return false
  end

  return vim.bo[bufnr].buflisted
    and vim.bo[bufnr].buftype == ""
    and vim.api.nvim_buf_get_name(bufnr) ~= ""
end

function M.is_normal_window(win)
  if not valid_win(win) then
    return false
  end

  local buf = vim.api.nvim_win_get_buf(win)
  return vim.bo[buf].buftype == "" and not vim.wo[win].winfixbuf
end

function M.current_tab_normal_windows()
  return vim.tbl_filter(M.is_normal_window, vim.api.nvim_tabpage_list_wins(0))
end

local function current_tab()
  return vim.api.nvim_get_current_tabpage()
end

local function tab_key(tab)
  tab = tab or current_tab()
  if not vim.api.nvim_tabpage_is_valid(tab) then
    return nil
  end

  local ok, id = pcall(vim.api.nvim_tabpage_get_var, tab, "lc_tab_id")
  if ok and type(id) == "number" then
    return id
  end

  id = next_tab_id
  next_tab_id = next_tab_id + 1
  pcall(vim.api.nvim_tabpage_set_var, tab, "lc_tab_id", id)
  return id
end

local function tab_by_key(key)
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if tab_key(tab) == key then
      return tab
    end
  end

  return nil
end

local function assign_new_tab_key(tab)
  local id = next_tab_id
  next_tab_id = next_tab_id + 1
  pcall(vim.api.nvim_tabpage_set_var, tab, "lc_tab_id", id)
  return id
end

local function workspace_by_id(id)
  return id and workspaces[id] or nil
end

local function workspace_index(id)
  for index, existing in ipairs(workspace_order) do
    if existing == id then
      return index
    end
  end

  return nil
end

local function workspace_tab_list(workspace)
  if type(workspace) ~= "table" then
    return {}
  end

  workspace.tabs = workspace.tabs or {}
  return workspace.tabs
end

local function remove_tab_from_all_workspaces(tab)
  if not vim.api.nvim_tabpage_is_valid(tab) then
    return
  end

  for _, id in ipairs(workspace_order) do
    remove_tab_from_workspace(tab, id)
  end
end

local function add_tab_to_workspace(tab, workspace_id)
  local workspace = workspace_by_id(workspace_id)
  if not workspace or not vim.api.nvim_tabpage_is_valid(tab) then
    return
  end

  remove_tab_from_all_workspaces(tab)

  local tabs = workspace_tab_list(workspace)
  for _, existing in ipairs(tabs) do
    if existing == tab then
      return
    end
  end

  tabs[#tabs + 1] = tab
end

remove_tab_from_workspace = function(tab, workspace_id)
  local workspace = workspace_by_id(workspace_id)
  if not workspace then
    return
  end

  local tabs = workspace_tab_list(workspace)
  for index = #tabs, 1, -1 do
    if tabs[index] == tab then
      table.remove(tabs, index)
    end
  end
end

local function workspace_tabs(id)
  local workspace = workspace_by_id(id)
  if not workspace then
    return {}
  end

  local tabs = {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if vim.api.nvim_tabpage_is_valid(tab) and tab_workspaces[tab_key(tab)] == id then
      tabs[#tabs + 1] = tab
    end
  end

  workspace.tabs = tabs
  return tabs
end

local function create_workspace(name)
  local id = next_workspace_id
  next_workspace_id = next_workspace_id + 1
  workspaces[id] = {
    id = id,
    name = name and name ~= "" and name or ("workspace-" .. id),
    last_tab = nil,
    last_tab_key = nil,
    tabs = {},
  }
  workspace_order[#workspace_order + 1] = id
  return id
end

local function ensure_workspace()
  if not active_workspace or not workspace_by_id(active_workspace) then
    active_workspace = create_workspace("main")
  end

  local tab = current_tab()
  local key = tab_key(tab)
  if vim.api.nvim_tabpage_is_valid(tab) then
    if tab_workspaces[key] and workspace_by_id(tab_workspaces[key]) then
      active_workspace = tab_workspaces[key]
    else
      tab_workspaces[key] = active_workspace
      add_tab_to_workspace(tab, active_workspace)
    end
    workspaces[active_workspace].last_tab = tab
    workspaces[active_workspace].last_tab_key = key
  end

  return active_workspace
end

local function current_workspace()
  return ensure_workspace()
end

local function tab_entry(tab)
  local key = tab_key(tab)
  tab_buffers[key] = tab_buffers[key] or {}
  return tab_buffers[key]
end

local function tab_all_entry(tab)
  local key = tab_key(tab)
  tab_all_buffers[key] = tab_all_buffers[key] or {}
  return tab_all_buffers[key]
end

local function cleanup_tabs()
  local valid_tab_keys = {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    valid_tab_keys[tab_key(tab)] = true
  end

  for key in pairs(tab_buffers) do
    if not valid_tab_keys[key] then
      tab_buffers[key] = nil
    end
  end

  for key in pairs(tab_all_buffers) do
    if not valid_tab_keys[key] then
      tab_all_buffers[key] = nil
    end
  end

  for key in pairs(tab_floats) do
    if not valid_tab_keys[key] then
      tab_floats[key] = nil
    end
  end

  for key in pairs(tab_workspaces) do
    if not valid_tab_keys[key] then
      tab_workspaces[key] = nil
    end
  end

  for win in pairs(window_buffer_cursors) do
    if not valid_win(win) then
      window_buffer_cursors[win] = nil
    end
  end

  for key in pairs(tab_buffer_cursors) do
    if not valid_tab_keys[key] then
      tab_buffer_cursors[key] = nil
    end
  end

  for bufnr in pairs(buffer_ownership) do
    if not valid_buf(bufnr) then
      buffer_ownership[bufnr] = nil
    end
  end

  for _, id in ipairs(workspace_order) do
    local workspace = workspaces[id]
    if workspace then
      local tabs = workspace_tabs(id)

      if workspace.last_tab_key and not tab_by_key(workspace.last_tab_key) then
        local tab = tabs[1]
        workspace.last_tab = tab
        workspace.last_tab_key = tab and tab_key(tab) or nil
      elseif workspace.last_tab and not vim.api.nvim_tabpage_is_valid(workspace.last_tab) then
        local tab = tabs[1]
        workspace.last_tab = tab
        workspace.last_tab_key = tab and tab_key(tab) or nil
      end
    end
  end
end

function M.ensure_workspace_consistent()
  -- Exposed for callers (like the tabline renderer) that need a fresh view
  -- of the tab -> workspace mapping before they render or make decisions.
  cleanup_tabs()
end

local function refresh_workspace_ui()
  pcall(vim.cmd, "redrawtabline")
  pcall(vim.cmd, "redrawstatus")
end

local function buffer_in_list(list, bufnr)
  if type(list) ~= "table" then
    return false
  end

  for _, existing in ipairs(list) do
    if existing == bufnr then
      return true
    end
  end

  return false
end

local function add_buffer_to_tab(bufnr, tab)
  if not valid_buf(bufnr) then
    return
  end

  tab = tab or current_tab()
  local key = tab_key(tab)
  buffer_last_tabs[bufnr] = key
  register_buffer_ownership(bufnr, tab)

  local all_entry = tab_all_entry(tab)
  if not buffer_in_list(all_entry, bufnr) then
    all_entry[#all_entry + 1] = bufnr
  end

  if M.is_normal_file_buffer(bufnr) then
    local entry = tab_entry(tab)
    if not buffer_in_list(entry, bufnr) then
      entry[#entry + 1] = bufnr
    end
  end
end

local function remove_buffer_from_tab(bufnr, key)
  local entry = tab_buffers[key]
  if entry then
    for index = #entry, 1, -1 do
      if entry[index] == bufnr then
        table.remove(entry, index)
      end
    end
  end

  local all_entry = tab_all_buffers[key]
  if all_entry then
    for index = #all_entry, 1, -1 do
      if all_entry[index] == bufnr then
        table.remove(all_entry, index)
      end
    end
  end
end

local function buffer_kind_for(bufnr)
  if M.is_normal_file_buffer(bufnr) then
    return "file"
  end

  if valid_buf(bufnr) and vim.bo[bufnr].buftype == "" and vim.api.nvim_buf_get_name(bufnr) == "" then
    return "blank"
  end

  return "special"
end

local function buffer_ownership_entry(bufnr)
  if not valid_buf(bufnr) then
    return nil
  end

  return buffer_ownership[bufnr]
end

function M.buffer_owner(bufnr)
  local entry = buffer_ownership_entry(bufnr)
  if not entry then
    return nil
  end

  return vim.tbl_extend("force", {}, entry)
end

local function buffer_tab_id(bufnr)
  local entry = buffer_ownership_entry(bufnr)
  if not entry then
    return nil
  end

  return entry.tab_id or entry.last_seen_tab_id
end

local function buffer_workspace_id(bufnr)
  local entry = buffer_ownership_entry(bufnr)
  if not entry then
    return nil
  end

  return entry.workspace_id or entry.last_seen_workspace_id
end

register_buffer_ownership = function(bufnr, tab, opts)
  if not valid_buf(bufnr) then
    return
  end

  tab = tab or current_tab()
  if not vim.api.nvim_tabpage_is_valid(tab) then
    return
  end

  local tab_id = tab_key(tab)
  local workspace_id = (opts and opts.workspace_id) or tab_workspace(tab) or current_workspace()
  local kind = (opts and opts.kind) or buffer_kind_for(bufnr)
  local entry = buffer_ownership[bufnr] or {}

  entry.tab_id = tab_id
  entry.workspace_id = workspace_id
  entry.last_seen_tab_id = tab_id
  entry.last_seen_workspace_id = workspace_id
  entry.last_seen_kind = kind
  entry.last_seen_buffer_name = vim.api.nvim_buf_get_name(bufnr)
  if kind == "file" then
    entry.path = normalized_buffer_name(bufnr)
  end

  buffer_ownership[bufnr] = entry
end

local function snapshot_buffer_cursor(bufnr, win)
  if not M.is_normal_file_buffer(bufnr) then
    return
  end

  win = valid_win(win) and win or vim.api.nvim_get_current_win()
  if not valid_win(win) or vim.api.nvim_win_get_buf(win) ~= bufnr then
    return
  end

  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, win)
  if ok and type(cursor) == "table" and type(cursor[1]) == "number" and type(cursor[2]) == "number" then
    local position = { cursor[1], cursor[2] }
    window_buffer_cursors[win] = window_buffer_cursors[win] or {}
    window_buffer_cursors[win][bufnr] = position

    local tab = vim.api.nvim_win_get_tabpage(win)
    local key = tab_key(tab)
    tab_buffer_cursors[key] = tab_buffer_cursors[key] or {}
    tab_buffer_cursors[key][bufnr] = position
  end
end

function M.forget_buffer_cursor(bufnr)
  for _, cursors in pairs(window_buffer_cursors) do
    cursors[bufnr] = nil
  end
  for _, cursors in pairs(tab_buffer_cursors) do
    cursors[bufnr] = nil
  end
end

function M.jump_history(step, count)
  local key = step < 0 and "<C-o>" or "<C-i>"
  count = math.max(1, math.floor(tonumber(count) or 1))
  local command = ('execute "normal! %d\\%s"'):format(count, key)

  jumplist_navigation_depth = jumplist_navigation_depth + 1
  local ok = pcall(vim.cmd, command)
  jumplist_navigation_depth = jumplist_navigation_depth - 1
  return ok
end

local function restore_buffer_cursor(bufnr, win)
  if not M.is_normal_file_buffer(bufnr) then
    return
  end

  win = valid_win(win) and win or vim.api.nvim_get_current_win()
  if not valid_win(win) or vim.api.nvim_win_get_buf(win) ~= bufnr then
    return
  end

  local window_cursors = window_buffer_cursors[win]
  local cursor = window_cursors and window_cursors[bufnr] or nil
  if type(cursor) ~= "table" then
    local tab = vim.api.nvim_win_get_tabpage(win)
    local tab_cursors = tab_buffer_cursors[tab_key(tab)]
    cursor = tab_cursors and tab_cursors[bufnr] or nil
  end
  if type(cursor) ~= "table" then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count <= 0 then
    return
  end

  local line = math.max(1, math.min(tonumber(cursor[1]) or 1, line_count))
  local line_text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
  local col = math.max(0, math.min(tonumber(cursor[2]) or 0, #line_text))
  pcall(vim.api.nvim_win_set_cursor, win, { line, col })
end

local function ensure_buffer_in_tab(bufnr, tab)
  if not valid_buf(bufnr) then
    return
  end

  tab = tab or current_tab()
  local key = tab_key(tab)
  buffer_last_tabs[bufnr] = key
  register_buffer_ownership(bufnr, tab)

  local all_entry = tab_all_entry(tab)
  if not buffer_in_list(all_entry, bufnr) then
    all_entry[#all_entry + 1] = bufnr
  end

  if M.is_normal_file_buffer(bufnr) then
    local entry = tab_entry(tab)
    if not buffer_in_list(entry, bufnr) then
      entry[#entry + 1] = bufnr
    end
  end
end

local function record_tab_windows(tab)
  if not vim.api.nvim_tabpage_is_valid(tab) then
    return
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if valid_win(win) then
      add_buffer_to_tab(vim.api.nvim_win_get_buf(win), tab)
    end
  end
end

local function record_display_windows(tab)
  tab = tab or current_tab()
  record_tab_windows(tab)

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if valid_win(win) and is_floating_window(win) then
      local ok, win_tab = pcall(vim.api.nvim_win_get_tabpage, win)
      if ok and win_tab == tab then
        add_buffer_to_tab(vim.api.nvim_win_get_buf(win), tab)
      end
    end
  end
end

local function snapshot_floating_windows(tab)
  tab = tab or current_tab()
  local key = tab_key(tab)
  local snapshots = {}

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if valid_win(win) and is_floating_window(win) then
      local ok, win_tab = pcall(vim.api.nvim_win_get_tabpage, win)
      if ok and win_tab == tab then
        local buf = vim.api.nvim_win_get_buf(win)
        add_buffer_to_tab(buf, tab)
        snapshots[#snapshots + 1] = {
          buf = buf,
          config = vim.api.nvim_win_get_config(win),
        }
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end

  if #snapshots > 0 then
    tab_floats[key] = snapshots
  end
end

local function restore_floating_windows(tab)
  tab = tab or current_tab()
  local key = tab_key(tab)
  local snapshots = tab_floats[key]
  if not snapshots then
    return
  end

  tab_floats[key] = nil
  for _, snapshot in ipairs(snapshots) do
    if valid_buf(snapshot.buf) and type(snapshot.config) == "table" then
      pcall(vim.api.nvim_open_win, snapshot.buf, false, snapshot.config)
    end
  end
end

local function reset_current_tab_to_blank(blank)
  vim.api.nvim_win_set_buf(0, blank)
  pcall(vim.cmd, "silent! only!")
  if valid_buf(blank) then
    vim.api.nvim_win_set_buf(0, blank)
  end
end

local function initialize_blank_tab(tab, workspace_id, blank)
  if not vim.api.nvim_tabpage_is_valid(tab) then
    return nil
  end

  workspace_id = workspace_id or current_workspace()
  local key = assign_new_tab_key(tab)
  tab_workspaces[key] = workspace_id
  tab_buffers[key] = {}
  tab_all_buffers[key] = {}
  add_tab_to_workspace(tab, workspace_id)

  if valid_buf(blank) then
    vim.bo[blank].bufhidden = "hide"
    vim.bo[blank].swapfile = false
    reset_current_tab_to_blank(blank)
    add_buffer_to_tab(blank, tab)
  end

  if workspace_by_id(workspace_id) then
    workspaces[workspace_id].last_tab = tab
    workspaces[workspace_id].last_tab_key = key
  end

  return key
end

function M.current_tab_buffers()
  ensure_workspace()
  cleanup_tabs()
  local buffers = {}
  local kept = {}

  for _, bufnr in ipairs(tab_entry()) do
    if M.is_normal_file_buffer(bufnr) then
      buffers[#buffers + 1] = bufnr
      kept[#kept + 1] = bufnr
    end
  end

  tab_buffers[tab_key(current_tab())] = kept
  return buffers
end

function M.current_tab_visible_buffers()
  local buffers = {}
  local seen = {}

  for _, win in ipairs(M.current_tab_normal_windows()) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    if M.is_normal_file_buffer(bufnr) and not seen[bufnr] then
      seen[bufnr] = true
      buffers[#buffers + 1] = bufnr
    end
  end

  return buffers
end

function M.is_in_current_tab(bufnr)
  for _, existing in ipairs(M.current_tab_buffers()) do
    if existing == bufnr then
      return true
    end
  end

  return false
end

function M.new_tab()
  ensure_workspace()

  local workspace_id = current_workspace()
  local previous_tab = current_tab()
  local ok, err = pcall(function()
    creating_tab = true
    vim.cmd("tab split")
  end)
  creating_tab = false

  if not ok then
    vim.notify("Tab creation failed: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  local tab = current_tab()
  if not vim.api.nvim_tabpage_is_valid(tab) or tab == previous_tab then
    vim.notify("Tab creation failed: new tab was not created", vim.log.levels.ERROR)
    return false
  end

  local blank = vim.api.nvim_create_buf(true, false)
  local init_ok, init_err = pcall(function()
    creating_tab = true
    initialize_blank_tab(tab, workspace_id, blank)
  end)
  creating_tab = false

  if not init_ok then
    vim.notify("Tab creation failed: " .. tostring(init_err), vim.log.levels.ERROR)
    return false
  end

  return true
end

tab_workspace = function(tab)
  active_workspace = active_workspace or ensure_workspace()
  tab = tab or current_tab()
  local key = tab_key(tab)
  if vim.api.nvim_tabpage_is_valid(tab) and not tab_workspaces[key] then
    tab_workspaces[key] = active_workspace
    add_tab_to_workspace(tab, active_workspace)
  end
  return tab_workspaces[key]
end

function M.is_visible_in_current_tab(bufnr)
  for _, win in ipairs(M.current_tab_normal_windows()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      return true
    end
  end

  return false
end

function M.find_visible_buffer_window(bufnr, opts)
  opts = opts or {}
  local current_tab = vim.api.nvim_get_current_tabpage()

  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if not opts.other_tabs_only or tab ~= current_tab then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        if M.is_normal_window(win) and vim.api.nvim_win_get_buf(win) == bufnr then
          return tab, win
        end
      end
    end
  end

  return nil, nil
end

local function find_owned_file_buffer(current_name, workspace_id)
  for bufnr, entry in pairs(buffer_ownership) do
    if valid_buf(bufnr) and entry and (entry.kind == "file" or entry.last_seen_kind == "file") then
      local path = entry.path or normalized_buffer_name(bufnr)
      if path == current_name then
        local owner_workspace = entry.workspace_id or entry.last_seen_workspace_id
        local owner_tab = tab_by_key(entry.tab_id or entry.last_seen_tab_id or -1)
        if owner_tab and (workspace_id == nil or owner_workspace == workspace_id) then
          return owner_workspace, owner_tab, bufnr
        end
      end
    end
  end

  return nil, nil, nil
end

local function find_buffer_tab(bufnr)
  local workspace_id = current_workspace()
  local owner_tab = tab_by_key(buffer_tab_id(bufnr) or -1)
  if owner_tab and buffer_workspace_id(bufnr) == workspace_id then
    return owner_tab
  end

  cleanup_tabs()

  for key, buffers in pairs(tab_buffers) do
    local tab = tab_by_key(key)
    if tab and tab_workspace(tab) == workspace_id then
      for _, existing in ipairs(buffers) do
        if existing == bufnr and M.is_normal_file_buffer(existing) then
          return tab
        end
      end
    end
  end

  return nil
end

function M.focus_buffer_window(bufnr)
  local visible_tab, win = M.find_visible_buffer_window(bufnr)
  if visible_tab and win then
    vim.api.nvim_set_current_tabpage(visible_tab)
    vim.api.nvim_set_current_win(win)
    return true
  end

  local owner = M.buffer_owner(bufnr)
  if owner then
    local owner_tab = tab_by_key(owner.tab_id or owner.last_seen_tab_id or -1)
    local owner_workspace = owner.workspace_id or owner.last_seen_workspace_id
    if owner_tab and owner_workspace then
      if owner_workspace ~= current_workspace() and workspace_by_id(owner_workspace) then
        active_workspace = owner_workspace
      end

      if vim.api.nvim_get_current_tabpage() ~= owner_tab then
        vim.api.nvim_set_current_tabpage(owner_tab)
      end

      if vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win()) ~= bufnr then
        vim.cmd("buffer " .. bufnr)
      end

      return true
    end
  end

  local owner_tab = find_buffer_tab(bufnr)
  if owner_tab and owner_tab ~= current_tab() then
    vim.api.nvim_set_current_tabpage(owner_tab)
    add_buffer_to_tab(bufnr, owner_tab)
    vim.cmd("buffer " .. bufnr)
    return true
  end

  if valid_buf(bufnr) then
    add_buffer_to_tab(bufnr, current_tab())
    vim.cmd("buffer " .. bufnr)
    return true
  end

  return false
end

function M.focus_existing_or_current_tab(bufnr)
  local tab, win = M.find_visible_buffer_window(bufnr)
  if tab and win then
    vim.api.nvim_set_current_tabpage(tab)
    vim.api.nvim_set_current_win(win)
    return true
  end

  if valid_buf(bufnr) then
    vim.cmd("buffer " .. bufnr)
    return true
  end

  return false
end

local function create_fallback_buffer()
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  return bufnr
end

normalized_buffer_name = function(bufnr)
  local name = valid_buf(bufnr) and vim.api.nvim_buf_get_name(bufnr) or ""
  if name == "" then
    return nil
  end

  local real = vim.uv.fs_realpath(name)
  return vim.fs.normalize(real or vim.fn.fnamemodify(name, ":p"))
end

local function read_tab_state()
  local root = project_state.startup_context().root
  local state = project_state.read_root_state(root)
  if type(state) == "table" and type(state.tabs) == "table" then
    return state
  end

  return project_state.legacy_tab_state_for_root(root)
end

local function write_tab_state(state)
  local root = project_state.startup_context().root
  return project_state.update_root_state(root, function(existing)
    existing.active_tab_id = state.active_tab_id
    existing.next_tab_id = state.next_tab_id
    existing.tabs = vim.tbl_map(function(tab)
      local clean = vim.deepcopy(tab)
      clean.workspace_id = nil
      return clean
    end, state.tabs or {})
    existing.workspaces = nil
    existing.version = state.version or existing.version or 2
    return existing
  end)
end

local function save_buffer_state(bufnr)
  if not valid_buf(bufnr) then
    return { type = "blank" }
  end

  local name = normalized_buffer_name(bufnr)
  if name then
    return {
      type = "file",
      path = name,
    }
  end

  if vim.bo[bufnr].buftype ~= "" then
    return {
      type = "special",
      buftype = vim.bo[bufnr].buftype,
      name = vim.api.nvim_buf_get_name(bufnr),
    }
  end

  return { type = "blank" }
end

local function load_file_buffer(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end

  local bufnr = vim.fn.bufnr(path, true)
  if bufnr == -1 then
    bufnr = vim.fn.bufadd(path)
  end

  if not valid_buf(bufnr) then
    return nil
  end

  pcall(vim.fn.bufload, bufnr)
  return bufnr
end

local function capture_layout_node(node, tab_state)
  if type(node) ~= "table" or node[1] == nil then
    return nil
  end

  if node[1] == "leaf" and type(node[2]) == "number" then
    local win = node[2]
    local bufnr = vim.api.nvim_win_get_buf(win)
    local leaf = {
      type = "leaf",
      buffer = save_buffer_state(bufnr),
    }

    tab_state.leaf_count = tab_state.leaf_count + 1
    if win == tab_state.current_win then
      tab_state.focus_leaf = tab_state.leaf_count
    end

    return leaf
  end

  local layout = {
    type = node[1],
    children = {},
  }

  local children = type(node[2]) == "table" and node[2] or {}
  for _, child in ipairs(children) do
    local serialized = capture_layout_node(child, tab_state)
    if serialized then
      layout.children[#layout.children + 1] = serialized
    end
  end

  return layout
end

local function capture_current_tab_state(tab)
  if not vim.api.nvim_tabpage_is_valid(tab) then
    return nil
  end

  local ok, previous_tab = pcall(vim.api.nvim_get_current_tabpage)
  if not ok then
    previous_tab = nil
  end

  local tab_state = {
    id = tab_key(tab),
    buffers = {},
    layout = nil,
    focus_leaf = 1,
    leaf_count = 0,
  }

  local switched = false
  if previous_tab ~= tab then
    switched = pcall(vim.api.nvim_set_current_tabpage, tab)
  end

  if switched or previous_tab == tab then
    local current_win = vim.api.nvim_get_current_win()
    tab_state.current_win = current_win
    local layout = vim.fn.winlayout()
    tab_state.layout = capture_layout_node(layout, tab_state)
  end

  for _, bufnr in ipairs(tab_entry(tab)) do
    if valid_buf(bufnr) and M.is_normal_file_buffer(bufnr) then
      local name = normalized_buffer_name(bufnr)
      if name then
        tab_state.buffers[#tab_state.buffers + 1] = name
      end
    end
  end

  if previous_tab and previous_tab ~= tab and vim.api.nvim_tabpage_is_valid(previous_tab) then
    pcall(vim.api.nvim_set_current_tabpage, previous_tab)
  end

  tab_state.tab_key = tab_key(tab)
  return tab_state
end

local function rebuild_tab_layout(node, tab_state, focus_state)
  if not node then
    return nil
  end

  if node.type == "leaf" then
    local buffer_state = node.buffer
    local bufnr = nil

    if buffer_state == nil then
      bufnr = tab_state.fallback_buffers[tab_state.leaf_count + 1]
    elseif buffer_state.type == "file" and buffer_state.path then
      bufnr = load_file_buffer(buffer_state.path)
    elseif buffer_state.type == "special" then
      bufnr = vim.api.nvim_create_buf(true, false)
    else
      bufnr = vim.api.nvim_create_buf(true, false)
    end

    if valid_buf(bufnr) then
      vim.api.nvim_win_set_buf(0, bufnr)
      ensure_buffer_in_tab(bufnr, tab_state.tab)
      tab_state.leaf_count = tab_state.leaf_count + 1
      if tab_state.leaf_count == focus_state.focus_leaf then
        focus_state.win = vim.api.nvim_get_current_win()
      end
    end

    return focus_state.win
  end

  local children = type(node.children) == "table" and node.children or {}
  if #children == 0 then
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(0, bufnr)
    ensure_buffer_in_tab(bufnr, tab_state.tab)
    tab_state.leaf_count = tab_state.leaf_count + 1
    if tab_state.leaf_count == focus_state.focus_leaf then
      focus_state.win = vim.api.nvim_get_current_win()
    end
    return focus_state.win
  end

  rebuild_tab_layout(children[1], tab_state, focus_state)

  for index = 2, #children do
    if node.type == "row" then
      vim.cmd("belowright vsplit")
    else
      vim.cmd("belowright split")
    end
    if node.type == "row" then
      vim.cmd("wincmd l")
    else
      vim.cmd("wincmd j")
    end
    rebuild_tab_layout(children[index], tab_state, focus_state)
  end

  return focus_state.win
end

local function restore_tab_state(tab, state)
  if not vim.api.nvim_tabpage_is_valid(tab) or type(state) ~= "table" then
    return nil
  end

  local tab_state = {
    tab = tab,
    leaf_count = 0,
    fallback_buffers = {},
  }
  local focus_state = {
    focus_leaf = tonumber(state.focus_leaf) or 1,
    win = nil,
  }

  local buffers = type(state.buffers) == "table" and state.buffers or {}
  for _, path in ipairs(buffers) do
    local bufnr = load_file_buffer(path)
    if valid_buf(bufnr) then
      tab_state.fallback_buffers[#tab_state.fallback_buffers + 1] = bufnr
      ensure_buffer_in_tab(bufnr, tab)
    end
  end

  local layout = type(state.layout) == "table" and state.layout or nil
  if layout then
    rebuild_tab_layout(layout, tab_state, focus_state)
  end

  if valid_win(focus_state.win) then
    pcall(vim.api.nvim_set_current_win, focus_state.win)
  end

  return focus_state.win
end

local function persist_tabs_state()
  if persisting_tabs or restoring_tabs then
    return
  end

  persisting_tabs = true
  local ok, state = pcall(function()
    local current_tabpage = current_tab()
    local tabs = {}
    local active_tab_id = nil
    local max_tab_id = 0

    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      if vim.api.nvim_tabpage_is_valid(tab) then
        local tab_state = capture_current_tab_state(tab)
        if tab_state then
          tabs[#tabs + 1] = tab_state
          if tab_state.id and tab_state.id > max_tab_id then
            max_tab_id = tab_state.id
          end
          if tab == current_tabpage then
            active_tab_id = tab_state.id
          end
        end
      end
    end

    return {
      version = 1,
      active_tab_id = active_tab_id,
      next_tab_id = math.max(next_tab_id, max_tab_id + 1),
      tabs = tabs,
    }
  end)

  if ok and state then
    write_tab_state(state)
  end
  persisting_tabs = false
end

local function restore_tabs_state()
  if not project_state.restore_allowed() then
    return false
  end

  local state = read_tab_state()
  if type(state) ~= "table" then
    return false
  end

  local tabs = type(state.tabs) == "table" and state.tabs or {}
  if #tabs == 0 then
    return false
  end

  restoring_tabs = true
  local ok, err = pcall(function()
    local original_tab = current_tab()

    if not active_workspace or not workspace_by_id(active_workspace) then
      active_workspace = create_workspace("main")
    end

    local restored_tabs = {}
    local max_tab_id = 0

    for index, tab_state in ipairs(tabs) do
      local tab = index == 1 and original_tab or nil
      if index > 1 then
        vim.cmd("tabnew")
        tab = current_tab()
      end

      if not vim.api.nvim_tabpage_is_valid(tab) then
        error("Invalid tab during restore")
      end

      local key = tonumber(tab_state.id) or tab_key(tab)
      pcall(vim.api.nvim_tabpage_set_var, tab, "lc_tab_id", key)
      if key > max_tab_id then
        max_tab_id = key
      end

      tab_buffers[key] = {}
      tab_all_buffers[key] = {}
      tab_workspaces[key] = active_workspace
      add_tab_to_workspace(tab, active_workspace)

      restore_tab_state(tab, tab_state)
      restored_tabs[#restored_tabs + 1] = {
        tab = tab,
        id = key,
      }
    end

    local active_tab_id = tonumber(state.active_tab_id)
    local target_tab = restored_tabs[1] and restored_tabs[1].tab or original_tab
    if active_tab_id then
      for _, item in ipairs(restored_tabs) do
        if item.id == active_tab_id then
          target_tab = item.tab
          break
        end
      end
    end

    if vim.api.nvim_tabpage_is_valid(target_tab) then
      vim.api.nvim_set_current_tabpage(target_tab)
      workspaces[active_workspace].last_tab = target_tab
      workspaces[active_workspace].last_tab_key = tab_key(target_tab)
    end

    next_tab_id = math.max(tonumber(state.next_tab_id) or 0, max_tab_id + 1)
  end)
  restoring_tabs = false

  if not ok then
    vim.notify("Failed to restore tab state: " .. tostring(err), vim.log.levels.WARN)
    return false
  end

  return true
end

local function find_visible_file_window(bufnr)
  local current_tab = vim.api.nvim_get_current_tabpage()
  local workspace_id = current_workspace()
  local current_name = normalized_buffer_name(bufnr)
  if not current_name then
    return nil, nil
  end

  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if tab ~= current_tab and tab_workspace(tab) == workspace_id then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        if M.is_normal_window(win) then
          local win_buf = vim.api.nvim_win_get_buf(win)
          if normalized_buffer_name(win_buf) == current_name then
            return tab, win
          end
        end
      end
    end
  end

  return nil, nil
end

local function find_file_tab(bufnr)
  local workspace_id = current_workspace()
  local current_name = normalized_buffer_name(bufnr)
  if not current_name then
    return nil
  end

  local _, owned_tab = find_owned_file_buffer(current_name, workspace_id)
  if owned_tab then
    return owned_tab
  end

  cleanup_tabs()
  for key, buffers in pairs(tab_buffers) do
    local tab = tab_by_key(key)
    if tab and tab ~= current_tab() and tab_workspace(tab) == workspace_id then
      for _, existing in ipairs(buffers) do
        if normalized_buffer_name(existing) == current_name then
          return tab
        end
      end
    end
  end

  return nil
end

local function find_file_workspace_tab(bufnr)
  local current_name = normalized_buffer_name(bufnr)
  if not current_name then
    return nil, nil
  end

  local workspace_id = current_workspace()
  local owned_workspace, owned_tab = find_owned_file_buffer(current_name)
  if owned_workspace and owned_tab then
    return owned_workspace, owned_tab
  end

  cleanup_tabs()
  for key, buffers in pairs(tab_buffers) do
    local tab = tab_by_key(key)
    if tab and tab_workspace(tab) ~= workspace_id then
      for _, existing in ipairs(buffers) do
        if normalized_buffer_name(existing) == current_name then
          return tab_workspace(tab), tab
        end
      end
    end
  end

  return nil, nil
end

function M.fallback_buffer(excluded)
  excluded = excluded or {}

  for _, win in ipairs(M.current_tab_normal_windows()) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    if not excluded[bufnr] and M.is_normal_file_buffer(bufnr) then
      return bufnr
    end
  end

  for _, bufnr in ipairs(M.current_tab_buffers()) do
    if not excluded[bufnr] and M.is_normal_file_buffer(bufnr) then
      return bufnr
    end
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if not excluded[bufnr] and M.is_normal_file_buffer(bufnr) then
      return bufnr
    end
  end

  return create_fallback_buffer()
end

function M.restore_window_to_fallback(win, excluded)
  if not M.is_normal_window(win) then
    return false
  end

  local fallback = M.fallback_buffer(excluded)
  if not valid_buf(fallback) then
    return false
  end

  local tab = vim.api.nvim_win_get_tabpage(win)
  vim.api.nvim_win_set_buf(win, fallback)
  register_buffer_ownership(fallback, tab, { kind = "blank" })
  return true
end

function M.close_file_preview()
  close_win(file_preview.winid)

  if valid_buf(file_preview.bufnr) then
    pcall(vim.cmd, "silent! bwipeout " .. file_preview.bufnr)
  end

  file_preview.bufnr = nil
  file_preview.winid = nil
end

local function prompt_file_preview()
  vim.ui.input({ prompt = "Preview file: ", completion = "file" }, function(input)
    if input and input ~= "" then
      M.preview_file(input)
    end
  end)
end

function M.select_file_preview()
  local ok_builtin, builtin = pcall(require, "telescope.builtin")
  local ok_actions, actions = pcall(require, "telescope.actions")
  local ok_state, action_state = pcall(require, "telescope.actions.state")
  if not ok_builtin or not ok_actions or not ok_state then
    prompt_file_preview()
    return false
  end

  builtin.find_files({
    prompt_title = "Preview file",
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        local path = entry and (entry.path or entry.filename or entry[1])
        actions.close(prompt_bufnr)
        if path and path ~= "" then
          vim.schedule(function()
            M.preview_file(path)
          end)
        end
      end)
      return true
    end,
  })

  return true
end

function M.preview_file(path)
  path = normalize_path(path)
  if not path then
    return M.select_file_preview()
  end

  if vim.fn.isdirectory(path) == 1 then
    vim.notify("Cannot preview directory: " .. path, vim.log.levels.WARN)
    return false
  end

  if not readable_file(path) then
    vim.notify("Cannot preview unreadable file: " .. path, vim.log.levels.WARN)
    return false
  end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    vim.notify("Could not read preview file: " .. tostring(lines), vim.log.levels.ERROR)
    return false
  end

  M.close_file_preview()

  local bufnr = vim.api.nvim_create_buf(false, true)
  file_preview.bufnr = bufnr

  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].buflisted = false
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].readonly = false
  vim.bo[bufnr].swapfile = false
  pcall(vim.api.nvim_buf_set_name, bufnr, "file-preview://" .. path)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  local filetype = vim.filetype.match({ filename = path })
  if filetype then
    vim.bo[bufnr].filetype = filetype
  end
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].readonly = true

  local width = math.min(math.max(60, math.floor(vim.o.columns * 0.72)), math.max(20, vim.o.columns - 4))
  local height = math.min(math.max(14, math.floor(vim.o.lines * 0.58)), math.max(8, vim.o.lines - 4))
  local winid = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = "minimal",
    border = "rounded",
    title = " " .. vim.fn.fnamemodify(path, ":~:.") .. " ",
    title_pos = "center",
  })
  file_preview.winid = winid

  vim.wo[winid].cursorline = true
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = "no"
  vim.wo[winid].wrap = false
  vim.wo[winid].winfixbuf = true

  add_buffer_to_tab(bufnr, current_tab())

  vim.keymap.set("n", "q", M.close_file_preview, { buffer = bufnr, desc = "Close file preview" })
  vim.keymap.set("n", "<Esc>", M.close_file_preview, { buffer = bufnr, desc = "Close file preview" })

  return true
end

local function route_duplicate_buffer(bufnr, win)
  if creating_workspace
    or routing_duplicate
    or clearing_buffers
    or restoring_tabs
    or persisting_tabs
    or not M.is_normal_file_buffer(bufnr)
    or not M.is_normal_window(win)
  then
    return
  end

  local target_tab, target_win = find_visible_file_window(bufnr)
  target_tab = target_tab or find_file_tab(bufnr)
  local target_workspace = nil
  if not target_tab then
    target_workspace, target_tab = find_file_workspace_tab(bufnr)
  end

  if target_tab == current_tab() then
    add_buffer_to_tab(bufnr, target_tab)
    return
  end

  if not target_tab then
    add_buffer_to_tab(bufnr, current_tab())
    return
  end

  routing_duplicate = true
  pcall(M.restore_window_to_fallback, win, { [bufnr] = true })

  if target_workspace then
    active_workspace = target_workspace
  end

  if target_win and vim.api.nvim_tabpage_is_valid(target_tab) and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_tabpage(target_tab)
    vim.api.nvim_set_current_win(target_win)
  elseif vim.api.nvim_tabpage_is_valid(target_tab) then
    vim.api.nvim_set_current_tabpage(target_tab)
    add_buffer_to_tab(bufnr, target_tab)
    vim.cmd("buffer " .. bufnr)
  end

  routing_duplicate = false
end

function M.workspace_names()
  ensure_workspace()
  local items = {}
  for _, id in ipairs(workspace_order) do
    local workspace = workspaces[id]
    if workspace then
      items[#items + 1] = {
        id = id,
        name = workspace.name,
        active = id == active_workspace,
      }
    end
  end
  return items
end

function M.workspace_new(name)
  ensure_workspace()
  local previous_tab = current_tab()
  record_display_windows(previous_tab)
  snapshot_floating_windows(previous_tab)

  local id = create_workspace(name)
  local ok, err = pcall(function()
    creating_workspace = true
    active_workspace = id
    vim.cmd("tabnew")
  end)
  creating_workspace = false

  if not ok then
    workspaces[id] = nil
    table.remove(workspace_order, workspace_index(id) or #workspace_order)
    active_workspace = tab_workspace(previous_tab) or active_workspace
    restore_floating_windows(previous_tab)
    vim.notify("Workspace creation failed: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  local tab = current_tab()
  if tab == previous_tab then
    workspaces[id] = nil
    table.remove(workspace_order, workspace_index(id) or #workspace_order)
    active_workspace = tab_workspace(previous_tab) or active_workspace
    restore_floating_windows(previous_tab)
    vim.notify("Workspace creation failed: new tab was not created", vim.log.levels.ERROR)
    return false
  end

  local key = assign_new_tab_key(tab)
  local blank = vim.api.nvim_create_buf(true, false)
  vim.bo[blank].bufhidden = "hide"
  vim.bo[blank].swapfile = false

  ok, err = pcall(function()
    creating_workspace = true
    reset_current_tab_to_blank(blank)
  end)
  creating_workspace = false
  if not ok then
    workspaces[id] = nil
    table.remove(workspace_order, workspace_index(id) or #workspace_order)
    active_workspace = tab_workspace(previous_tab) or active_workspace
    restore_floating_windows(previous_tab)
    vim.notify("Workspace creation failed: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  tab_workspaces[key] = id
  tab_buffers[key] = {}
  tab_all_buffers[key] = {}
  add_tab_to_workspace(tab, id)
  add_buffer_to_tab(blank, tab)

  workspaces[id].last_tab = tab
  workspaces[id].last_tab_key = key

  refresh_workspace_ui()
  vim.schedule(refresh_workspace_ui)
  vim.notify("Workspace: " .. workspaces[id].name, vim.log.levels.INFO)
  return true
end

function M.workspace_switch(id)
  ensure_workspace()
  if not workspace_by_id(id) then
    vim.notify("Workspace not found", vim.log.levels.WARN)
    return false
  end

  snapshot_floating_windows(current_tab())

  active_workspace = id
  local workspace = workspaces[id]
  local target = workspace.last_tab_key and tab_by_key(workspace.last_tab_key) or workspace.last_tab
  if not target or not vim.api.nvim_tabpage_is_valid(target) or tab_workspaces[tab_key(target)] ~= id then
    target = workspace_tabs(id)[1]
  end

  if not target then
    vim.cmd("tabnew")
    target = current_tab()
    tab_workspaces[tab_key(target)] = id
    add_tab_to_workspace(target, id)
  end

  workspace.last_tab = target
  workspace.last_tab_key = tab_key(target)
  vim.api.nvim_set_current_tabpage(target)
  restore_floating_windows(target)
  refresh_workspace_ui()
  vim.notify("Workspace: " .. workspace.name, vim.log.levels.INFO)
  return true
end

function M.workspace_next(step)
  ensure_workspace()
  if #workspace_order <= 1 then
    return
  end

  local index = workspace_index(active_workspace) or 1
  local target = workspace_order[((index - 1 + step) % #workspace_order) + 1]
  M.workspace_switch(target)
end

local function workspace_tab_index(tabs, tab)
  for index, candidate in ipairs(tabs) do
    if candidate == tab then
      return index
    end
  end

  return nil
end

function M.tab_next(step)
  ensure_workspace()

  local tabs = M.current_workspace_tabs()
  if #tabs <= 1 then
    return false
  end

  local current = current_tab()
  local index = workspace_tab_index(tabs, current) or 1
  local target = tabs[((index - 1 + step) % #tabs) + 1]
  if not target or not vim.api.nvim_tabpage_is_valid(target) or target == current then
    return false
  end

  vim.api.nvim_set_current_tabpage(target)
  return true
end

function M.tab_previous()
  return M.tab_next(-1)
end

function M.workspace_rename(name)
  ensure_workspace()
  if not name or name == "" then
    vim.notify("Workspace name required", vim.log.levels.WARN)
    return
  end

  workspaces[active_workspace].name = name
  refresh_workspace_ui()
  vim.notify("Workspace renamed: " .. name, vim.log.levels.INFO)
end

function M.workspace_select()
  ensure_workspace()
  local items = M.workspace_names()
  vim.ui.select(items, {
    prompt = "Workspace",
    format_item = function(item)
      return (item.active and "* " or "  ") .. item.name
    end,
  }, function(item)
    if item then
      M.workspace_switch(item.id)
    end
  end)
end

local function is_buffer_visible_outside_tabs(bufnr, closing_tab_keys)
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local key = tab_key(tab)
    if not closing_tab_keys[key] then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        if valid_win(win) and vim.api.nvim_win_get_buf(win) == bufnr then
          return true
        end
      end
    end
  end

  return false
end

local function wipe_owned_special_buffers(buffers, closing_tab_keys)
  for bufnr in pairs(buffers) do
    if valid_buf(bufnr)
      and not M.is_normal_file_buffer(bufnr)
      and not is_buffer_visible_outside_tabs(bufnr, closing_tab_keys)
    then
      if vim.bo[bufnr].modified then
        vim.notify("Skipped modified workspace buffer: " .. bufnr, vim.log.levels.WARN)
      else
        pcall(vim.cmd, "silent! bwipeout " .. bufnr)
      end
    end
  end
end

function M.workspace_close()
  ensure_workspace()
  if #workspace_order <= 1 then
    vim.notify("Cannot close the last workspace", vim.log.levels.WARN)
    return false
  end

  local closing = active_workspace
  local closing_index = workspace_index(closing) or 1
  local target_index = closing_index < #workspace_order and closing_index + 1 or closing_index - 1
  local target = workspace_order[target_index]
  local closing_tabs = workspace_tabs(closing)
  local closing_tab_keys = {}
  local special_buffers = {}

  for _, tab in ipairs(closing_tabs) do
    record_display_windows(tab)
    local key = tab_key(tab)
    closing_tab_keys[key] = true
    for _, bufnr in ipairs(tab_all_buffers[key] or {}) do
      special_buffers[bufnr] = true
    end
  end

  M.workspace_switch(target)

  for _, tab in ipairs(closing_tabs) do
    local key = tab_key(tab)
    if vim.api.nvim_tabpage_is_valid(tab) and #vim.api.nvim_list_tabpages() > 1 then
      vim.api.nvim_set_current_tabpage(tab)
      pcall(vim.cmd, "tabclose")
    end
    tab_buffers[key] = nil
    tab_all_buffers[key] = nil
    tab_workspaces[key] = nil
    remove_tab_from_workspace(tab, closing)
  end

  wipe_owned_special_buffers(special_buffers, closing_tab_keys)

  workspaces[closing] = nil
  table.remove(workspace_order, closing_index)
  M.workspace_switch(target)
  return true
end

function M.workspace_current_name()
  ensure_workspace()
  return workspaces[active_workspace].name
end

function M.workspace_statusline_parts()
  ensure_workspace()

  local workspace = workspaces[active_workspace]
  if not workspace then
    return { previous = "", label = "WS: main.", next = "" }
  end

  local index = workspace_index(active_workspace) or 1
  local total = #workspace_order
  local punctuation = total <= 1 and "." or ""

  return {
    previous = index > 1 and "<< " or "",
    label = "WS: " .. workspace.name .. punctuation,
    next = index < total and " >>" or "",
  }
end

function M.workspace_statusline()
  local parts = M.workspace_statusline_parts()
  return parts.previous .. parts.label .. parts.next
end

local function scope_tab_buffers(tabs)
  local buffers = {}
  local seen = {}

  for _, tab in ipairs(tabs) do
    local key = tab_key(tab)
    for _, bufnr in ipairs(tab_buffers[key] or {}) do
      if valid_buf(bufnr) and M.is_normal_file_buffer(bufnr) and not seen[bufnr] then
        seen[bufnr] = true
        buffers[#buffers + 1] = bufnr
      end
    end
  end

  return buffers
end

local function clear_file_registry_names(buffer_list)
  local names = {}
  local seen = {}

  for _, bufnr in ipairs(buffer_list) do
    local name = normalized_buffer_name(bufnr)
    if name and not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end

  for _, name in ipairs(names) do
    pcall(vim.cmd, "silent! LastProjectFileForget " .. vim.fn.fnameescape(name))
  end

  pcall(vim.cmd, "silent! LastProjectFileForget")
end

local function clear_project_state_for_buffers(buffer_list)
  local roots = {}
  for _, bufnr in ipairs(buffer_list) do
    local name = normalized_buffer_name(bufnr)
    if name then
      local root = project_state.project_root_for_path(name)
      if root then
        roots[root] = true
      end
    end
  end

  for root in pairs(roots) do
    project_state.clear_root_state(root)
  end
end

local function tab_blank_buffer(tab)
  if not vim.api.nvim_tabpage_is_valid(tab) then
    return nil
  end

  local key = tab_key(tab)
  for _, bufnr in ipairs(tab_all_buffers[key] or {}) do
    if valid_buf(bufnr)
      and vim.bo[bufnr].buftype == ""
      and vim.api.nvim_buf_get_name(bufnr) == ""
    then
      return bufnr
    end
  end

  return nil
end

local function blank_tab_windows(tabs)
  local blanks = {}

  for _, tab in ipairs(tabs) do
    if vim.api.nvim_tabpage_is_valid(tab) then
      local key = tab_key(tab)
      local blank = blanks[key]
      if not valid_buf(blank) then
        blank = tab_blank_buffer(tab) or create_fallback_buffer()
        blanks[key] = blank
        add_buffer_to_tab(blank, tab)
      end

      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        if M.is_normal_window(win) then
          pcall(vim.api.nvim_win_set_buf, win, blank)
        end
      end
    end
  end
end

local function clear_buffers_for_tabs(tabs)
  local buffers = scope_tab_buffers(tabs)
  if #buffers == 0 then
    clear_file_registry_names({})
    blank_tab_windows(tabs)
    return true
  end

  clearing_buffers = true
  blank_tab_windows(tabs)

  for _, bufnr in ipairs(buffers) do
    if valid_buf(bufnr) then
      pcall(vim.cmd, "silent! bdelete! " .. bufnr)
      M.forget_buffer_cursor(bufnr)
    end
  end
  clearing_buffers = false

  clear_file_registry_names(buffers)
  return true
end

function M.clear_workspace_buffers()
  local workspace_id = current_workspace()
  cleanup_tabs()
  local buffers = scope_tab_buffers(workspace_tabs(workspace_id))
  local ok = clear_buffers_for_tabs(workspace_tabs(workspace_id))
  clear_project_state_for_buffers(buffers)
  active_workspace = workspace_id
  return ok
end

function M.clear_all_buffers()
  local workspace_id = current_workspace()
  cleanup_tabs()
  local buffers = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if M.is_normal_file_buffer(bufnr) then
      buffers[#buffers + 1] = bufnr
    end
  end

  clearing_buffers = true
  blank_tab_windows(vim.api.nvim_list_tabpages())

  for _, bufnr in ipairs(buffers) do
    pcall(vim.cmd, "silent! bdelete! " .. bufnr)
    M.forget_buffer_cursor(bufnr)
  end
  clearing_buffers = false

  clear_file_registry_names(buffers)
  clear_project_state_for_buffers(buffers)
  active_workspace = workspace_id
  return true
end

function M.current_workspace_tabs()
  ensure_workspace()
  cleanup_tabs()
  return workspace_tabs(active_workspace)
end

function M.setup()
  local restored_tabs = restore_tabs_state()
  ensure_workspace()
  if not restored_tabs then
    record_display_windows(current_tab())
  end

  vim.api.nvim_create_autocmd("TabLeave", {
    group = vim.api.nvim_create_augroup("lc_workspace_display_cleanup", { clear = true }),
    callback = function()
      if restoring_tabs or persisting_tabs then
        return
      end
      snapshot_floating_windows(current_tab())
    end,
  })

  vim.api.nvim_create_autocmd({ "BufLeave", "BufWinLeave", "WinLeave" }, {
    group = vim.api.nvim_create_augroup("lc_tab_buffer_capture", { clear = true }),
    callback = function(event)
      snapshot_buffer_cursor(event.buf)
      if event.event ~= "BufLeave" then
        return
      end
      if restoring_tabs or persisting_tabs or creating_workspace or creating_tab or clearing_buffers then
        return
      end
      local tab = tab_by_key(buffer_last_tabs[event.buf])
      if not tab then
        tab = current_tab()
      end
      add_buffer_to_tab(event.buf, tab)
    end,
  })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = vim.api.nvim_create_augroup("lc_window_cursor_capture", { clear = true }),
    callback = function(event)
      snapshot_buffer_cursor(event.buf, vim.api.nvim_get_current_win())
    end,
  })

  vim.api.nvim_create_autocmd({ "TabEnter", "TabNewEntered" }, {
    group = vim.api.nvim_create_augroup("lc_workspace_tab_tracking", { clear = true }),
    callback = function()
      if restoring_tabs or persisting_tabs or creating_workspace or creating_tab or clearing_buffers then
        return
      end
      ensure_workspace()
      local tab = current_tab()
      local key = tab_key(tab)
      if not tab_workspaces[key] then
        tab_workspaces[key] = active_workspace
      else
        active_workspace = tab_workspaces[key]
      end
      workspaces[active_workspace].last_tab = tab
      workspaces[active_workspace].last_tab_key = key
      record_display_windows(tab)
      restore_floating_windows(tab)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "WinEnter" }, {
    group = vim.api.nvim_create_augroup("lc_tab_file_routing", { clear = true }),
    callback = function(event)
      if restoring_tabs or persisting_tabs or creating_workspace or creating_tab or clearing_buffers then
        return
      end
      local win = vim.api.nvim_get_current_win()
      if jumplist_navigation_depth > 0 then
        if valid_win(win) and vim.api.nvim_win_get_buf(win) == event.buf then
          add_buffer_to_tab(event.buf, current_tab())
        end
        return
      end
      if valid_win(win) and vim.api.nvim_win_get_buf(win) == event.buf then
        local tab = current_tab()
        route_duplicate_buffer(event.buf, win)
        if vim.api.nvim_get_current_tabpage() == tab
          and valid_win(win)
          and vim.api.nvim_win_get_buf(win) == event.buf
        then
          add_buffer_to_tab(event.buf, tab)
          restore_buffer_cursor(event.buf, win)
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = vim.api.nvim_create_augroup("lc_tab_buffer_cleanup", { clear = true }),
    callback = function(event)
      if restoring_tabs or persisting_tabs then
        return
      end
      local keys = {}
      for key in pairs(tab_buffers) do
        keys[key] = true
      end
      for key in pairs(tab_all_buffers) do
        keys[key] = true
      end
      for key in pairs(keys) do
        remove_buffer_from_tab(event.buf, key)
      end
      buffer_last_tabs[event.buf] = nil
      buffer_ownership[event.buf] = nil
      M.forget_buffer_cursor(event.buf)
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("lc_tab_state_persist", { clear = true }),
    callback = function()
      persist_tabs_state()
    end,
  })

  vim.api.nvim_create_user_command("WorkspaceNew", function(opts)
    M.workspace_new(opts.args)
  end, { nargs = "?", desc = "Create a runtime workspace" })

  vim.api.nvim_create_user_command("WorkspaceNext", function()
    M.workspace_next(1)
  end, { desc = "Next runtime workspace" })

  vim.api.nvim_create_user_command("WorkspacePrevious", function()
    M.workspace_next(-1)
  end, { desc = "Previous runtime workspace" })

  vim.api.nvim_create_user_command("WorkspaceList", function()
    M.workspace_select()
  end, { desc = "List runtime workspaces" })

  vim.api.nvim_create_user_command("WorkspaceRename", function(opts)
    M.workspace_rename(opts.args)
  end, { nargs = 1, desc = "Rename current runtime workspace" })

  vim.api.nvim_create_user_command("WorkspaceClose", function()
    M.workspace_close()
  end, { desc = "Close current runtime workspace" })

  vim.api.nvim_create_user_command("FilePreview", function(opts)
    M.preview_file(opts.args)
  end, { nargs = "?", complete = "file", desc = "Preview a file in a floating window" })

  vim.api.nvim_create_user_command("FilePreviewClose", function()
    M.close_file_preview()
  end, { desc = "Close the file preview floating window" })
end

return M
