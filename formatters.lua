local M = {}

local conform_util = require("conform.util")

local function python_project_root(ctx)
  local bufnr = ctx.bufnr or ctx.buf or 0
  return vim.fs.root(bufnr, { "uv.lock", "pyproject.toml", "pytest.ini", ".git" }) or vim.fn.getcwd()
end

function M.format(opts)
  opts = vim.tbl_extend("force", {
    bufnr = 0,
    lsp_format = "fallback",
    timeout_ms = 3000,
  }, opts or {})

  local did_attempt = require("conform").format(opts)
  if not did_attempt then
    vim.notify("No formatter available for " .. vim.bo[opts.bufnr].filetype, vim.log.levels.WARN)
  end
end

function M.setup()
  require("conform").setup({
    formatters_by_ft = {
      python = { "ruff_fix_imports", "black" },
      javascript = { "prettier" },
      javascriptreact = { "prettier" },
      typescript = { "prettier" },
      typescriptreact = { "prettier" },
      json = { "prettier" },
      html = { "prettier" },
      htmldjango = { "prettier" },
      css = { "prettier" },
      yaml = { "prettier" },
      markdown = { "prettier" },
    },
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
      local disable_filetypes = { c = true, cpp = true }
      local filetype = vim.bo[bufnr].filetype
      return {
        timeout_ms = filetype == "python" and 5000 or 1000,
        lsp_format = disable_filetypes[filetype] and "never" or "fallback",
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
