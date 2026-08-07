local M = {}

local pending = {}

local function owner_key(owner)
  return tostring(owner)
end

local function cancel_timer(owner, key)
  local owner_pending = pending[owner_key(owner)]
  local timer = owner_pending and owner_pending[key]
  if not timer then
    return
  end

  pcall(timer.stop, timer)
  pcall(timer.close, timer)
  owner_pending[key] = nil
  if next(owner_pending) == nil then
    pending[owner_key(owner)] = nil
  end
end

function M.cancel(owner, key)
  cancel_timer(owner, key)
end

function M.defer(owner, key, delay_ms, callback)
  cancel_timer(owner, key)

  local normalized_owner = owner_key(owner)
  pending[normalized_owner] = pending[normalized_owner] or {}
  local expected_name
  if type(owner) == "number" and vim.api.nvim_buf_is_valid(owner) then
    expected_name = vim.api.nvim_buf_get_name(owner)
  end
  local timer
  timer = vim.defer_fn(function()
    local owner_pending = pending[normalized_owner]
    if owner_pending then
      owner_pending[key] = nil
      if next(owner_pending) == nil then
        pending[normalized_owner] = nil
      end
    end

    if type(owner) == "number" then
      if not vim.api.nvim_buf_is_valid(owner) or vim.api.nvim_buf_get_name(owner) ~= expected_name then
        return
      end
    end
    callback(owner)
  end, delay_ms or 0)
  pending[normalized_owner][key] = timer
end

function M.cancel_owner(owner)
  local normalized_owner = owner_key(owner)
  local owner_pending = pending[normalized_owner]
  if not owner_pending then
    return
  end

  for key in pairs(owner_pending) do
    cancel_timer(owner, key)
  end
end

vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
  group = vim.api.nvim_create_augroup("lc_deferred_buffer_cleanup", { clear = true }),
  callback = function(event)
    M.cancel_owner(event.buf)
  end,
})

return M
