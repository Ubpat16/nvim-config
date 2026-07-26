local M = {}

local conform_util = require("conform.util")
local project_config = require("config.project_config")
local python = require("config.python")

local function python_project_root(ctx)
  local bufnr = ctx.bufnr or ctx.buf or 0
  local configured = project_config.get(project_config.start_path(bufnr)).project.root
  if configured then
    return configured
  end
  return vim.fs.root(bufnr, { "uv.lock", "pyproject.toml", "pytest.ini", ".git" }) or vim.fn.getcwd()
end

local function python_tool(tool, ctx)
  local bufnr = ctx.bufnr or ctx.buf or 0
  local uv = vim.fn.exepath("uv")
  return python.project_tool(tool, bufnr) or (uv ~= "" and uv or "uv")
end

local function uses_uv(tool, ctx)
  local name = vim.fs.basename(python_tool(tool, ctx)):lower()
  return name == "uv" or name == "uv.exe"
end

local function python_formatter_env(_, ctx)
  return python.project_python_env(ctx.bufnr or ctx.buf or 0)
end

function M.options_for_buffer(bufnr)
  bufnr = bufnr or 0
  local profile = project_config.get(project_config.start_path(bufnr))
  local filetype = vim.bo[bufnr].filetype
  return {
    formatters = vim.deepcopy(profile.formatting.by_filetype[filetype]),
    timeout_ms = profile.formatting.timeout_ms or (filetype == "python" and 5000 or 1000),
    lsp_format = (filetype == "c" or filetype == "cpp") and "never" or "fallback",
    on_save = profile.formatting.on_save,
  }
end

function M.format(opts)
  local bufnr = opts and opts.bufnr or 0
  local configured = M.options_for_buffer(bufnr)
  opts = vim.tbl_extend("force", {
    bufnr = 0,
    formatters = configured.formatters,
    lsp_format = configured.lsp_format,
    timeout_ms = configured.timeout_ms,
  }, opts or {})

  local did_attempt = require("conform").format(opts)
  if not did_attempt then
    vim.notify("No formatter available for " .. vim.bo[opts.bufnr].filetype, vim.log.levels.WARN)
  end
end

function M.setup()
  require("conform").setup({
    formatters_by_ft = project_config.defaults().formatting.by_filetype,
    default_format_opts = {
      lsp_format = "fallback",
    },
    formatters = {
      ruff_fix_imports = {
        command = function(_, ctx)
          return python_tool("ruff", ctx)
        end,
        stdin = true,
        args = function(_, ctx)
          local args = { "check", "--fix-only", "--select", "F401,I", "--stdin-filename", "$FILENAME", "-" }
          if uses_uv("ruff", ctx) then
            args = vim.list_extend({ "tool", "run", "ruff" }, args)
          end
          return args
        end,
        env = python_formatter_env,
        cwd = python_project_root,
      },
      isort = {
        command = function(_, ctx)
          return python_tool("isort", ctx)
        end,
        args = function(_, ctx)
          local bufnr = ctx.bufnr or ctx.buf or 0
          local args = {
            "--stdout",
            "--line-ending",
            conform_util.buf_line_ending(bufnr),
            "--filename",
            "$FILENAME",
            "-",
          }
          if uses_uv("isort", ctx) then
            args = vim.list_extend({ "tool", "run", "isort" }, args)
          end
          return args
        end,
        cwd = python_project_root,
        env = python_formatter_env,
      },
      black = {
        command = function(_, ctx)
          return python_tool("black", ctx)
        end,
        args = function(_, ctx)
          local args = { "--stdin-filename", "$FILENAME", "--quiet", "-" }
          if uses_uv("black", ctx) then
            args = vim.list_extend({ "tool", "run", "black" }, args)
          end
          return args
        end,
        cwd = python_project_root,
        env = python_formatter_env,
      },
    },
    format_on_save = function(bufnr)
      local configured = M.options_for_buffer(bufnr)
      if not configured.on_save then
        return nil
      end
      return {
        formatters = configured.formatters,
        timeout_ms = configured.timeout_ms,
        lsp_format = configured.lsp_format,
      }
    end,
  })

  vim.api.nvim_create_user_command("Format", function()
    M.format()
  end, {
    desc = "Format current buffer",
  })

  vim.api.nvim_create_user_command("FormatWrite", function()
    M.format()
    vim.cmd("write")
  end, {
    desc = "Format current buffer and write",
  })

  vim.keymap.set("n", "<leader>cf", M.format, { desc = "Format current buffer" })
end

return M
