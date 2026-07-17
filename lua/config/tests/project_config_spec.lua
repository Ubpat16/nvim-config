local root = vim.fn.tempname()
local project_a = vim.fs.joinpath(root, "project-a")
local project_b = vim.fs.joinpath(root, "project-b")
local nested_a = vim.fs.joinpath(project_a, "apps", "personal", "tests")
vim.fn.mkdir(nested_a, "p")
vim.fn.mkdir(project_b, "p")

local function write(path, content)
  local file = assert(io.open(path, "w"))
  file:write(content)
  file:close()
end

local function normalize(path)
  return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

local config_a = vim.fs.joinpath(project_a, "nvim.config")
local config_b = vim.fs.joinpath(project_b, "nvim.config")
local test_a = vim.fs.joinpath(nested_a, "test_profile.py")
local test_b = vim.fs.joinpath(project_b, "test_other.py")
write(test_a, "")
write(test_b, "")
write(config_a, vim.json.encode({
  project = { root = "backend" },
  editor = {
    autosave = false,
    options = { shiftwidth = 4, expandtab = true, colorcolumn = "100" },
  },
  python = { interpreter = ".venv/bin/python" },
  django = { root = "backend", manage_py = "app/manage.py", env_file = ".env.test" },
  neotest = {
    args = { "--ds=settings.personal tests", "--reuse-db" },
    python = { runner = "pytest" },
    jest = { args = { "--runInBand" } },
  },
  pytest = { direct_args = { "--reuse-db", "-q" }, env_file = ".env.pytest" },
  formatting = {
    on_save = false,
    timeout_ms = 7000,
    by_filetype = { python = { "isort", "black" } },
  },
  linting = { enabled = false, by_filetype = { python = { "ruff" } } },
  lsp = { settings = { pyright = { python = { analysis = { typeCheckingMode = "strict" } } } } },
  dap = {
    python = {
      just_my_code = true,
      env_file = ".env.debug",
      django_runserver_args = { "runserver", "9000" },
      celery_app = "worker.app",
      celery_args = { "worker", "-l", "debug" },
      attach_host = "0.0.0.0",
      attach_port = 9001,
    },
  },
  run = { python = { args = { "--verbose" }, env_file = ".env.run" } },
}))
write(config_b, [[{"neotest":{"args":["--ds=settings.other"]}}]])

package.loaded["config.project_config"] = nil
local project_config = require("config.project_config")

local profile, metadata = project_config.get(test_a)
assert(metadata.config_path == normalize(config_a), "returns the selected config path")
assert(metadata.config_dir == normalize(project_a), "returns the selected config directory")
assert(profile.project.root == vim.fs.joinpath(metadata.config_dir, "backend"), "resolves tool root")
assert(profile.python.interpreter == vim.fs.joinpath(metadata.config_dir, ".venv/bin/python"), "resolves interpreter")
assert(profile.django.root == vim.fs.joinpath(metadata.config_dir, "backend"), "resolves Django root")
assert(profile.django.manage_py == vim.fs.joinpath(metadata.config_dir, "app/manage.py"), "resolves manage.py")
assert(profile.django.env_file == vim.fs.joinpath(metadata.config_dir, ".env.test"), "resolves Django env file")
assert(profile.pytest.env_file == vim.fs.joinpath(metadata.config_dir, ".env.pytest"), "resolves pytest env file")
assert(profile.dap.python.env_file == vim.fs.joinpath(metadata.config_dir, ".env.debug"), "resolves DAP env file")
assert(profile.run.python.env_file == vim.fs.joinpath(metadata.config_dir, ".env.run"), "resolves run env file")
assert(profile.editor.autosave == false, "loads editor settings")
assert(vim.deep_equal(profile.formatting.by_filetype.python, { "isort", "black" }), "loads formatter selection")
assert(vim.deep_equal(profile.formatting.by_filetype.typescript, { "prettier" }), "unspecified formatter defaults remain")
assert(profile.lsp.settings.pyright.python.analysis.typeCheckingMode == "strict", "loads nested LSP settings")
assert(vim.deep_equal(project_config.neotest_args(test_a), { "--ds=settings.personal tests", "--reuse-db" }), "keeps compatibility helper")

vim.cmd("edit " .. vim.fn.fnameescape(test_a))
local notified_settings = nil
local original_get_clients = vim.lsp.get_clients
local client = {
  name = "pyright",
  settings = { python = { analysis = { typeCheckingMode = "basic", autoSearchPaths = true } } },
  notify = function(_, _, payload) notified_settings = payload.settings end,
}
vim.lsp.get_clients = function() return { client } end
project_config.apply_lsp_settings(vim.api.nvim_get_current_buf())
assert(client.settings.python.analysis.typeCheckingMode == "strict", "project LSP settings override defaults")
assert(client.settings.python.analysis.autoSearchPaths == true, "project LSP settings preserve default siblings")
assert(notified_settings == client.settings, "changed LSP settings are sent to the client")
vim.lsp.get_clients = original_get_clients

local other = project_config.get(test_b)
assert(vim.deep_equal(other.neotest.args, { "--ds=settings.other" }), "nearest config is isolated per project")
assert(other.pytest.direct_args[1] == "--reuse-db", "missing sections preserve defaults")
assert(other.editor.autosave == true, "default autosave remains enabled")

profile.editor.options.shiftwidth = 99
assert(project_config.get(test_a).editor.options.shiftwidth == 4, "callers receive deep copies")

local notifications = {}
local original_notify = vim.notify
vim.notify = function(message)
  notifications[#notifications + 1] = message
end

vim.uv.sleep(20)
write(config_a, [[{
  "editor":{"autosave":"yes","options":{"shiftwidth":8,"mystery":true}},
  "neotest":{"args":["--ds=settings.changed"]},
  "unknown_section":{"enabled":true}
}]])
profile = project_config.get(test_a)
assert(profile.editor.autosave == true, "invalid values fall back independently")
assert(profile.editor.options.shiftwidth == 8, "valid sibling fields survive")
assert(vim.deep_equal(profile.neotest.args, { "--ds=settings.changed" }), "valid sections survive partial errors")
assert(#notifications == 1, "partial validation warns once per changed version")
project_config.get(test_a)
assert(#notifications == 1, "unchanged invalid config does not warn repeatedly")

vim.uv.sleep(20)
write(config_a, [[{"neotest":]])
profile = project_config.get(test_a)
assert(vim.deep_equal(profile.neotest.args, {}), "malformed JSON falls back to defaults")
assert(#notifications == 2, "changed malformed JSON produces a new warning")

local unrelated = vim.fn.tempname()
vim.fn.mkdir(unrelated, "p")
local defaults, default_metadata = project_config.get(unrelated)
assert(default_metadata.config_path == nil, "missing config has no metadata path")
assert(defaults.neotest.python.runner == "pytest", "missing config preserves runner default")
assert(defaults.formatting.by_filetype.python[1] == "ruff_fix_imports", "missing config preserves formatter defaults")

vim.notify = original_notify
vim.fn.delete(root, "rf")
vim.fn.delete(unrelated, "rf")
