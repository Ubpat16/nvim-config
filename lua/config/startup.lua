local function has_normal_startup_window()
  local windows = vim.tbl_filter(function(win)
    return vim.api.nvim_win_get_config(win).relative == ""
  end, vim.api.nvim_list_wins())
  return #windows == 1 and windows[1] == vim.api.nvim_get_current_win()
end

local function directory_argument()
  if vim.fn.argc(-1) ~= 1 then
    return nil
  end

  local argument = vim.fn.argv(0)
  if argument == "" or vim.fn.isdirectory(argument) ~= 1 then
    return nil
  end

  return argument
end

local function open_dashboard_if_blank()
  if #vim.api.nvim_list_uis() == 0 then
    return
  end

  local directory = directory_argument()
  if vim.fn.argc(-1) > 0 and not directory then
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_get_name(bufnr) ~= ""
    and not directory
  then
    return
  end
  if directory and vim.api.nvim_buf_get_name(bufnr) == "" then
    return
  end
  if vim.bo[bufnr].modified
    or vim.bo[bufnr].filetype == "snacks_dashboard"
    or not has_normal_startup_window()
  then
    return
  end

  local snacks = rawget(_G, "Snacks")
  if type(snacks) ~= "table" or not snacks.dashboard then
    return
  end

  local win = vim.api.nvim_get_current_win()
  local dashboard = snacks.dashboard.open({
    buf = directory and nil or bufnr,
    win = win,
  })

  if directory and vim.api.nvim_buf_is_valid(bufnr) and bufnr ~= dashboard.buf then
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end
end

vim.api.nvim_create_autocmd("UIEnter", {
  group = vim.api.nvim_create_augroup("lc_startup_dashboard", { clear = true }),
  once = true,
  callback = function()
    vim.schedule(open_dashboard_if_blank)
  end,
})
