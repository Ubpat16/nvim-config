local project_config = require("config.project_config")
local autosave_scheduled = {}
local autosave_in_progress = {}

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
  if autosave_in_progress[bufnr] then
    return
  end
  if not project_config.for_buffer(bufnr).editor.autosave then
    return
  end

  autosave_in_progress[bufnr] = true
  pcall(vim.api.nvim_buf_call, bufnr, function()
    vim.cmd("silent update")
  end)
  autosave_in_progress[bufnr] = nil
end

local function schedule_autosave(bufnr)
  if autosave_scheduled[bufnr] then
    return
  end
  autosave_scheduled[bufnr] = true
  vim.schedule(function()
    autosave_scheduled[bufnr] = nil
    lc_autosave_buffer(bufnr)
  end)
end

-- Auto-save file buffers when moving away from them
vim.api.nvim_create_autocmd({ "BufLeave", "BufWinLeave", "FocusLost", "VimLeavePre" }, {
  group = vim.api.nvim_create_augroup("autosave_on_leave", { clear = true }),
  callback = function(args)
    if args.event == "FocusLost" or args.event == "VimLeavePre" then
      lc_autosave_buffer(args.buf)
    else
      schedule_autosave(args.buf)
    end
  end,
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
