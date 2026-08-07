local deferred = require("config.deferred")

local bufnr = vim.api.nvim_create_buf(true, false)
local calls = 0

deferred.defer(bufnr, "work", 20, function(target)
  assert(target == bufnr, "deferred callback receives its buffer owner")
  calls = calls + 1
end)
deferred.defer(bufnr, "work", 20, function()
  calls = calls + 10
end)

assert(vim.wait(200, function() return calls == 10 end), "same deferred work should be coalesced")

deferred.defer(bufnr, "cancelled", 20, function()
  calls = calls + 100
end)
deferred.cancel(bufnr, "cancelled")
vim.wait(60)
assert(calls == 10, "cancelled deferred work should not run")

deferred.defer(bufnr, "stale", 20, function()
  calls = calls + 1000
end)
vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname())
vim.wait(60)
assert(calls == 10, "stale work should not run after a buffer changes identity")

vim.api.nvim_buf_delete(bufnr, { force = true })
