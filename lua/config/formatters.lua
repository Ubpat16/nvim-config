local M = {}

local conform_util = require("conform.util")
local project_config = require("config.project_config")

local function python_project_root(ctx)
  local bufnr = ctx.bufnr or ctx.buf or 0
  local configured = project_config.get(project_config.start_path(bufnr)).project.root
  if configured then
    return configured
  end
  return vim.fs.root(bufnr, { "uv.lock", "pyproject.toml", "pytest.ini", ".git" }) or vim.fn.getcwd()
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
        command = "ruff",
        stdin = true,
        args = {
          "check",
          "--fix-only",
          "--select",
          "F401,I",
          "--stdin-filename",
          "$FILENAME",
          "-",
        },
        cwd = python_project_root,
      },
      isort = {
        command = "uv",
        args = function(_, ctx)
          local bufnr = ctx.bufnr or ctx.buf or 0
          return {
            "run",
            "--group",
            "dev",
            "isort",
            "--stdout",
            "--line-ending",
            conform_util.buf_line_ending(bufnr),
            "--filename",
            "$FILENAME",
            "-",
          }
        end,
        cwd = python_project_root,
      },
      black = {
        command = "uv",
        args = {
          "run",
          "--group",
          "dev",
          "black",
          "--stdin-filename",
          "$FILENAME",
          "--quiet",
          "-",
        },
        cwd = python_project_root,
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
