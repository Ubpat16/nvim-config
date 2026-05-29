local python = require("config.python")
local django = require("config.django")

return {
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    dependencies = { "williamboman/mason.nvim" },
    config = function()
      require("config.formatters").setup()
    end,
  },

  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      local lint = require("lint")
      if vim.fn.executable("eslint_d") == 1 then
        lint.linters_by_ft = {
          javascript = { "eslint_d" },
          javascriptreact = { "eslint_d" },
          typescript = { "eslint_d" },
          typescriptreact = { "eslint_d" },
        }
      else
        lint.linters_by_ft = {}
      end

      local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })
      vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
        group = lint_augroup,
        callback = function()
          lint.try_lint()
        end,
      })
    end,
  },

  {
    "mfussenegger/nvim-dap",
    event = "VeryLazy",
    config = function()
      require("dap").set_log_level("INFO")
    end,
  },

  {
    "mfussenegger/nvim-dap-python",
    event = "VeryLazy",
    dependencies = { "mfussenegger/nvim-dap" },
    config = function()
      local function current_file_dir()
        local path = vim.api.nvim_buf_get_name(0)
        if path ~= "" then
          return vim.fn.fnamemodify(path, ":p:h")
        end
        return vim.fn.getcwd()
      end

      local function global_python()
        return python.global_python() or "python3"
      end

      local function django_root()
        return django.find_manage_py_root(current_file_dir()) or vim.fn.getcwd()
      end

      local function manage_py()
        return vim.fs.joinpath(django_root(), "manage.py")
      end

      require("dap-python").setup(global_python())
      local dap = require("dap")

      table.insert(dap.configurations.python, {
        name = "Django: manage.py runserver",
        type = "python",
        request = "launch",
        program = manage_py,
        args = { "runserver", "--noreload" },
        django = true,
        justMyCode = false,
        console = "integratedTerminal",
        cwd = django_root,
        pythonPath = global_python,
      })

      table.insert(dap.configurations.python, {
        name = "Django: test current file",
        type = "python",
        request = "launch",
        program = manage_py,
        args = function()
          return { "test", vim.fn.expand("%:p") }
        end,
        django = true,
        justMyCode = false,
        console = "integratedTerminal",
        cwd = django_root,
        pythonPath = global_python,
      })

      table.insert(dap.configurations.python, {
        name = "Celery: worker",
        type = "python",
        request = "launch",
        module = "celery",
        args = { "-A", "config", "worker", "-l", "info", "-P", "solo" },
        justMyCode = false,
        console = "integratedTerminal",
        cwd = django_root,
        pythonPath = global_python,
      })

      table.insert(dap.configurations.python, {
        name = "Python: attach debugpy (5678)",
        type = "python",
        request = "attach",
        connect = { host = "127.0.0.1", port = 5678 },
        pythonPath = global_python,
      })
    end,
  },

  {
    "rcarriga/nvim-dap-ui",
    event = "VeryLazy",
    dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" },
    config = function()
      local dap = require("dap")
      local dapui = require("dapui")

      dapui.setup()

      dap.listeners.after.event_initialized["dapui_config"] = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated["dapui_config"] = function()
        dapui.close()
      end
      dap.listeners.before.event_exited["dapui_config"] = function()
        dapui.close()
      end
    end,
  },

  {
    "nvim-neotest/neotest",
    event = "VeryLazy",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      "nvim-neotest/neotest-python",
      "nvim-neotest/neotest-jest",
    },
    config = function()
      require("neotest").setup({
        adapters = {
          require("neotest-python")({
            dap = { justMyCode = false },
            runner = "pytest",
            python = function()
              return python.global_python() or "python3"
            end,
          }),
          require("neotest-jest")({}),
        },
      })
    end,
  },

  {
    "Jamsjz/django.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-telescope/telescope.nvim" },
    opts = {
      telescope_enabled = true,
      floaterm_enabled = false,
      mappings = {},
    },
  },

  {
    "mbbill/undotree",
    cmd = { "UndotreeToggle", "UndotreeShow", "UndotreeHide", "UndotreeFocus" },
  },

  {
    "akinsho/toggleterm.nvim",
    version = "*",
    cmd = { "ToggleTerm", "TermExec" },
    opts = {
      size = 16,
      open_mapping = [[<c-\>]],
      shade_filetypes = {},
      direction = "horizontal",
      close_on_exit = true,
    },
  },

  {
    "rest-nvim/rest.nvim",
    ft = { "http" },
    cmd = { "Rest" },
    build = false,
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      "nvim-neotest/nvim-nio",
      { "lunarmodules/lua-mimetypes", name = "mimetypes" },
      {
        "manoelcampos/xml2lua",
        name = "xml2lua",
        init = function(plugin)
          package.path = table.concat({
            plugin.dir .. "/?.lua",
            plugin.dir .. "/?/init.lua",
            package.path,
          }, ";")
        end,
      },
      {
        "j-hui/fidget.nvim",
        opts = {},
      },
    },
    config = function()
      pcall(function()
        require("nvim-treesitter").install({ "http" })
      end)

      package.preload["rest-nvim.script.javascript"] = function()
        local script = {}
        local logger = require("rest-nvim.logger")

        local node_bridge = [[
const chunks = [];
process.stdin.setEncoding("utf8");
process.stdin.on("data", chunk => chunks.push(chunk));
process.stdin.on("end", () => {
  const payload = JSON.parse(chunks.join("") || "{}");
  const globals = (payload.env && payload.env.globals) || {};
  const locals = (payload.env && payload.env.locals) || {};
  const response = (payload.env && payload.env.response) || {};
  const result = { globals: {}, locals: {}, logs: [], response };
  const stringify = value => {
    if (typeof value === "string") return value;
    try { return JSON.stringify(value); } catch (_) { return String(value); }
  };
  const readVariable = key => {
    key = String(key);
    if (Object.prototype.hasOwnProperty.call(locals, key)) return locals[key];
    if (Object.prototype.hasOwnProperty.call(globals, key)) return globals[key];
    if (Object.prototype.hasOwnProperty.call(process.env, key)) return process.env[key];
    return "";
  };
  const console = {
    log: (...args) => result.logs.push(args.map(stringify).join(" ")),
    info: (...args) => result.logs.push(args.map(stringify).join(" ")),
    warn: (...args) => result.logs.push(args.map(stringify).join(" ")),
    error: (...args) => result.logs.push(args.map(stringify).join(" ")),
  };
  const request = {
    variables: {
      set: (key, value) => {
        key = String(key);
        value = String(value);
        locals[key] = value;
        result.locals[key] = value;
      },
      get: key => String(readVariable(key)),
    },
  };
  const client = {
    global: {
      set: (key, value) => {
        key = String(key);
        value = String(value);
        globals[key] = value;
        result.globals[key] = value;
      },
      get: key => String(readVariable(key)),
    },
  };

  try {
    new Function("client", "request", "response", "console", payload.script || "")(
      client,
      request,
      response,
      console
    );
    result.response = response;
    process.stdout.write("\n__REST_NVIM_JS_RESULT__" + JSON.stringify(result));
  } catch (err) {
    process.stderr.write((err && err.stack) ? err.stack : String(err));
    process.exitCode = 1;
  }
});
]]

        local function node_command()
          local configured = vim.g.rest_nvim_javascript_node
          if type(configured) == "string" and configured ~= "" then
            return configured
          end
          return vim.fn.exepath("node")
        end

        local function collect_env(ctx, response)
          return {
            globals = vim.deepcopy(ctx.vars or {}),
            locals = vim.deepcopy(ctx.lv or {}),
            response = response or {},
          }
        end

        local function apply_result(ctx, result)
          for key, value in pairs(result.locals or {}) do
            ctx:set_local(tostring(key), tostring(value))
          end
          for key, value in pairs(result.globals or {}) do
            vim.env[tostring(key)] = tostring(value)
          end
          for _, line in ipairs(result.logs or {}) do
            vim.notify(line, vim.log.levels.INFO, { title = "rest.nvim JavaScript" })
          end
        end

        local function run_node(source, env)
          local node = node_command()
          if not node or node == "" then
            logger.error("failed to run javascript script. `node` is not executable in Neovim's PATH.")
            return nil
          end

          local payload = vim.json.encode({
            script = source,
            env = env,
          })
          local completed = vim.system({ node, "-e", node_bridge }, {
            text = true,
            stdin = payload,
          }):wait()

          if completed.code ~= 0 then
            logger.error(("javascript script failed: %s"):format(vim.trim(completed.stderr or "")))
            return nil
          end

          local stdout = completed.stdout or ""
          local marker = "__REST_NVIM_JS_RESULT__"
          local marker_start = stdout:find(marker, 1, true)
          if not marker_start then
            return nil
          end

          local json_part = stdout:sub(marker_start + #marker)
          local ok, decoded = pcall(vim.json.decode, json_part)
          if not ok then
            logger.error("failed to decode javascript script result.")
            return nil
          end

          return decoded
        end

        function script.run(source, ctx, response)
          local result = run_node(source, collect_env(ctx, response))
          if not result then
            return response
          end
          apply_result(ctx, result)
          return result.response
        end

        return script
      end

      require("rest-nvim").setup()
    end,
  },
}
