local root = vim.fn.tempname()
local backend = vim.fs.joinpath(root, "backend")
local app = vim.fs.joinpath(backend, "app")
local venv_bin = vim.fs.joinpath(root, ".venv", "bin")
vim.fn.mkdir(app, "p")
vim.fn.mkdir(venv_bin, "p")
vim.fn.mkdir(vim.fs.joinpath(root, ".git"), "p")

local function write(path, lines)
  vim.fn.writefile(type(lines) == "table" and lines or { lines }, path)
end

local function normalize(path)
  return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

local interpreter = vim.fs.joinpath(venv_bin, "python")
write(interpreter, { "#!/bin/sh", "exit 0" })
vim.fn.setfperm(interpreter, "rwxr-xr-x")
local manage_py = vim.fs.joinpath(app, "manage.py")
local test_file = vim.fs.joinpath(app, "test_profile.py")
local run_file = vim.fs.joinpath(app, "script.py")
write(manage_py, "")
write(test_file, "")
write(run_file, "")
write(vim.fs.joinpath(root, ".env.test"), "DJANGO_SETTINGS_MODULE=settings.tests")
write(vim.fs.joinpath(root, ".env.run"), "MODE=dev")
write(vim.fs.joinpath(root, "nvim.config"), vim.json.encode({
  project = { root = "backend" },
  editor = { autosave = false, options = { shiftwidth = 6, expandtab = false } },
  python = { interpreter = ".venv/bin/python" },
  django = { root = "backend", manage_py = "backend/app/manage.py", env_file = ".env.test" },
  neotest = { args = { "--ds=settings.tests", "value with spaces" } },
  pytest = { direct_args = { "--reuse-db", "-q" }, env_file = ".env.test" },
  run = { python = { args = { "--name", "spaced value" }, env_file = ".env.run" } },
}))

package.loaded["config.project_config"] = nil
package.loaded["config.python"] = nil
package.loaded["config.django"] = nil
package.loaded["config.project_commands"] = nil
local project_state = require("config.project_state")
local project_config = require("config.project_config")
local python = require("config.python")
local django = require("config.django")
local commands = require("config.project_commands")

local configured_profile = project_config.get(test_file)
local configured_python = python.project_python(nil, test_file)
assert(configured_python == configured_profile.python.interpreter, "configured interpreter preserves its virtualenv path")
assert(python.neotest_python(backend) == configured_profile.python.interpreter, "neotest resolves Python from its supplied test root")
assert(python.neotest_runner({ interpreter }) == "pytest", "neotest runner resolves from its interpreter project")

local context = assert(django.resolve_context(test_file))
assert(context.root == normalize(backend), "Django uses configured root")
assert(context.manage_py == normalize(manage_py), "Django uses configured manage.py")
assert(context.env_file == normalize(vim.fs.joinpath(root, ".env.test")), "Django uses configured env file")

local pytest_command = commands.pytest({ file = test_file, target = test_file .. "::test_example" })
assert(pytest_command:find(vim.fn.shellescape(normalize(backend)), 1, true), "pytest uses configured root")
assert(pytest_command:find("--env-file " .. vim.fn.shellescape(normalize(vim.fs.joinpath(root, ".env.test"))), 1, true), "pytest uses env file")
assert(pytest_command:find(vim.fn.shellescape("value with spaces"), 1, true), "pytest shell-escapes project args")
assert(pytest_command:find("--reuse-db", 1, true), "pytest keeps direct defaults")

local run_command = commands.python(run_file)
assert(run_command:find(vim.fn.shellescape(normalize(backend)), 1, true), "Python run uses configured root")
assert(run_command:find("--env-file " .. vim.fn.shellescape(normalize(vim.fs.joinpath(root, ".env.run"))), 1, true), "Python run uses env file")
assert(run_command:find(vim.fn.shellescape("spaced value"), 1, true), "Python run shell-escapes args")

local persisted_root = project_state.project_root_for_path(test_file)
assert(persisted_root == project_state.normalize_path(root), "tool root does not change project-state identity")

vim.cmd("edit " .. vim.fn.fnameescape(test_file))
vim.bo.filetype = "python"
project_config.apply_editor_options(0)
assert(vim.bo.shiftwidth == 6 and vim.bo.expandtab == false, "editor options apply buffer-locally")

vim.uv.sleep(20)
local config_path = vim.fs.joinpath(root, "nvim.config")
write(config_path, [[{"editor":{"autosave":true}}]])
project_config.apply_editor_options(0)
assert(vim.bo.shiftwidth ~= 6, "removing an editor override restores the buffer baseline")

vim.fn.delete(root, "rf")
