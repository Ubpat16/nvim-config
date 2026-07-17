local root = vim.fn.tempname()
local nested = vim.fs.joinpath(root, "apps", "personal", "tests")
vim.fn.mkdir(nested, "p")

local function write(path, content)
  local file = assert(io.open(path, "w"))
  file:write(content)
  file:close()
end

local config_path = vim.fs.joinpath(root, "nvim.config")
local test_path = vim.fs.joinpath(nested, "test_profile.py")
write(test_path, "")
write(config_path, [[{"neotest":{"args":["--ds=settings.personal tests","--reuse-db"]}}]])

package.loaded["config.project_config"] = nil
local project_config = require("config.project_config")

local args = project_config.neotest_args(test_path)
assert(vim.deep_equal(args, { "--ds=settings.personal tests", "--reuse-db" }), "loads nearest project args")

vim.uv.sleep(20)
write(config_path, [[{"neotest":{"args":["--ds=settings.changed"]}}]])
args = project_config.neotest_args(test_path)
assert(vim.deep_equal(args, { "--ds=settings.changed" }), "reloads config after it changes")

local notifications = {}
local original_notify = vim.notify
vim.notify = function(message)
  notifications[#notifications + 1] = message
end

vim.uv.sleep(20)
write(config_path, [[{"neotest":{"args":"--ds=settings.invalid"}}]])
assert(vim.deep_equal(project_config.neotest_args(test_path), {}), "invalid schema falls back to defaults")
assert(#notifications == 1, "invalid config warns once per changed version")
project_config.neotest_args(test_path)
assert(#notifications == 1, "unchanged invalid config does not warn repeatedly")

vim.uv.sleep(20)
write(config_path, [[{"neotest":]])
assert(vim.deep_equal(project_config.neotest_args(test_path), {}), "malformed JSON falls back to defaults")
assert(#notifications == 2, "changed malformed JSON produces a new warning")

local unrelated = vim.fn.tempname()
vim.fn.mkdir(unrelated, "p")
assert(vim.deep_equal(project_config.neotest_args(unrelated), {}), "missing config preserves defaults")

vim.notify = original_notify
vim.fn.delete(root, "rf")
vim.fn.delete(unrelated, "rf")
