local M = {}

local routing_duplicate = false
local tab_buffers = {}
local tab_workspaces = {}
local buffer_last_tabs = {}
local workspaces = {}
local workspace_order = {}
local active_workspace = nil
local next_workspace_id = 1
local next_tab_id = 1

local function valid_buf(bufnr)
  return type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr)
end

local function valid_win(win)
  return type(win) == "number" and vim.api.nvim_win_is_valid(win)
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

local function workspace_tabs(id)
  local tabs = {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if tab_workspaces[tab_key(tab)] == id then
      tabs[#tabs + 1] = tab
    end
  end
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

  for key in pairs(tab_workspaces) do
    if not valid_tab_keys[key] then
      tab_workspaces[key] = nil
    end
  end

  for _, id in ipairs(workspace_order) do
    local workspace = workspaces[id]
    if workspace and workspace.last_tab_key and not tab_by_key(workspace.last_tab_key) then
      local tab = workspace_tabs(id)[1]
      workspace.last_tab = tab
      workspace.last_tab_key = tab and tab_key(tab) or nil
    end
  end
end

local function add_buffer_to_tab(bufnr, tab)
  if not M.is_normal_file_buffer(bufnr) then
    return
  end

  tab = tab or current_tab()
  buffer_last_tabs[bufnr] = tab_key(tab)
  local entry = tab_entry(tab)
  for index, existing in ipairs(entry) do
    if existing == bufnr then
      table.remove(entry, index)
      break
    end
  end

  entry[#entry + 1] = bufnr
end

local function remove_buffer_from_tab(bufnr, key)
  local entry = tab_buffers[key]
  if not entry then
    return
  end

  for index = #entry, 1, -1 do
    if entry[index] == bufnr then
      table.remove(entry, index)
    end
  end
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

local function tab_workspace(tab)
  active_workspace = active_workspace or ensure_workspace()
  tab = tab or current_tab()
  local key = tab_key(tab)
  if vim.api.nvim_tabpage_is_valid(tab) and not tab_workspaces[key] then
    tab_workspaces[key] = active_workspace
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

local function find_buffer_tab(bufnr)
  local workspace_id = current_workspace()
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

local function normalized_buffer_name(bufnr)
  local name = valid_buf(bufnr) and vim.api.nvim_buf_get_name(bufnr) or ""
  if name == "" then
    return nil
  end

  local real = vim.uv.fs_realpath(name)
  return vim.fs.normalize(real or vim.fn.fnamemodify(name, ":p"))
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

  cleanup_tabs()
  for key, buffers in pairs(tab_buffers) do
    local tab = tab_by_key(key)
    if tab and tab_workspace(tab) ~= current_workspace() then
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

  vim.api.nvim_win_set_buf(win, fallback)
  return true
end

local function route_duplicate_buffer(bufnr, win)
  if routing_duplicate or not M.is_normal_file_buffer(bufnr) or not M.is_normal_window(win) then
    return
  end

  local target_tab, target_win = find_visible_file_window(bufnr)
  target_tab = target_tab or find_file_tab(bufnr)
  local target_workspace = nil
  if not target_tab then
    target_workspace, target_tab = find_file_workspace_tab(bufnr)
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
  local previous_workspace = active_workspace
  local previous_tab = current_tab()
  local previous_key = tab_key(previous_tab)
  local previous_buffers = vim.deepcopy(tab_buffers[previous_key] or {})
  local previous_buf = vim.api.nvim_get_current_buf()
  local id = create_workspace(name)
  active_workspace = id
  vim.cmd("tabnew")
  local tab = current_tab()
  local key = tab_key(tab)
  if previous_tab == tab or key == tab_key(previous_tab) then
    key = assign_new_tab_key(tab)
  end

  local restored_previous_tab = nil
  for _, candidate in ipairs(vim.api.nvim_list_tabpages()) do
    if candidate ~= tab then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(candidate)) do
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == previous_buf then
          restored_previous_tab = candidate
          break
        end
      end
    end
    if restored_previous_tab then
      break
    end
  end

  if restored_previous_tab then
    local previous_key = tab_key(restored_previous_tab)
    tab_workspaces[previous_key] = previous_workspace
    workspaces[previous_workspace].last_tab = restored_previous_tab
    workspaces[previous_workspace].last_tab_key = previous_key
  end
  active_workspace = id
  tab_workspaces[key] = id
  tab_buffers[key] = {}
  workspaces[id].last_tab = tab
  workspaces[id].last_tab_key = key

  for _, candidate in ipairs(vim.api.nvim_list_tabpages()) do
    if candidate ~= tab then
      local candidate_key = tab_key(candidate)
      if tab_workspaces[candidate_key] == id then
        tab_workspaces[candidate_key] = previous_workspace
        tab_buffers[candidate_key] = vim.deepcopy(previous_buffers)
        workspaces[previous_workspace].last_tab = candidate
        workspaces[previous_workspace].last_tab_key = candidate_key
      end
    end
  end

  vim.notify("Workspace: " .. workspaces[id].name, vim.log.levels.INFO)
end

function M.workspace_switch(id)
  ensure_workspace()
  if not workspace_by_id(id) then
    vim.notify("Workspace not found", vim.log.levels.WARN)
    return false
  end

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
  end

  workspace.last_tab = target
  workspace.last_tab_key = tab_key(target)
  vim.api.nvim_set_current_tabpage(target)
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

function M.workspace_rename(name)
  ensure_workspace()
  if not name or name == "" then
    vim.notify("Workspace name required", vim.log.levels.WARN)
    return
  end

  workspaces[active_workspace].name = name
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

  M.workspace_switch(target)

  for _, tab in ipairs(closing_tabs) do
    local key = tab_key(tab)
    if vim.api.nvim_tabpage_is_valid(tab) and #vim.api.nvim_list_tabpages() > 1 then
      vim.api.nvim_set_current_tabpage(tab)
      pcall(vim.cmd, "tabclose")
    end
    tab_buffers[key] = nil
    tab_workspaces[key] = nil
  end

  workspaces[closing] = nil
  table.remove(workspace_order, closing_index)
  M.workspace_switch(target)
  return true
end

function M.workspace_current_name()
  ensure_workspace()
  return workspaces[active_workspace].name
end

function M.setup()
  ensure_workspace()
  for _, win in ipairs(M.current_tab_normal_windows()) do
    add_buffer_to_tab(vim.api.nvim_win_get_buf(win), current_tab())
  end

  vim.api.nvim_create_autocmd("BufLeave", {
    group = vim.api.nvim_create_augroup("lc_tab_buffer_capture", { clear = true }),
    callback = function(event)
      local tab = tab_by_key(buffer_last_tabs[event.buf])
      if not tab then
        tab = current_tab()
      end
      add_buffer_to_tab(event.buf, tab)
    end,
  })

  vim.api.nvim_create_autocmd({ "TabEnter", "TabNewEntered" }, {
    group = vim.api.nvim_create_augroup("lc_workspace_tab_tracking", { clear = true }),
    callback = function()
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
    end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "WinEnter" }, {
    group = vim.api.nvim_create_augroup("lc_tab_file_routing", { clear = true }),
    callback = function(event)
      local win = vim.api.nvim_get_current_win()
      if valid_win(win) and vim.api.nvim_win_get_buf(win) == event.buf then
        route_duplicate_buffer(event.buf, win)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = vim.api.nvim_create_augroup("lc_tab_buffer_cleanup", { clear = true }),
    callback = function(event)
      for key in pairs(tab_buffers) do
        remove_buffer_from_tab(event.buf, key)
      end
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
end

return M
