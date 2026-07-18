local python = require("config.python")
local django = require("config.django")
local project_config = require("config.project_config")

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
      lint.linters_by_ft = {}

      local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })
      vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
        group = lint_augroup,
        callback = function(event)
          local profile = project_config.get(project_config.start_path(event.buf))
          if not profile.linting.enabled then
            return
          end
          local configured = vim.deepcopy(profile.linting.by_filetype[vim.bo[event.buf].filetype] or {})
          configured = vim.tbl_filter(function(name)
            return name ~= "eslint_d" or vim.fn.executable("eslint_d") == 1
          end, configured)
          if #configured > 0 then
            lint.try_lint(configured)
          end
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

      local function current_profile()
        return project_config.get(project_config.start_path())
      end

      local function project_python()
        return python.project_python(nil, current_file_dir()) or "python3"
      end

      local function django_root()
        local profile = current_profile()
        return profile.django.root
          or profile.project.root
          or django.find_manage_py_root(current_file_dir())
          or vim.fn.getcwd()
      end

      local function manage_py()
        return current_profile().django.manage_py or vim.fs.joinpath(django_root(), "manage.py")
      end

      local function dap_python()
        return current_profile().dap.python
      end

      local dap_python = require("dap-python")
      dap_python.setup(project_python())
      local dap = require("dap")
      dap.listeners.on_config["lc_project_python_adapter"] = function(config)
        if config.type == "python" or config.type == "debugpy" then
          dap_python.setup(project_python(), { include_configs = false })
        end
        return config
      end

      table.insert(dap.configurations.python, {
        name = "Django: manage.py runserver",
        type = "python",
        request = "launch",
        program = manage_py,
        args = function() return vim.deepcopy(dap_python().django_runserver_args) end,
        django = true,
        justMyCode = function() return dap_python().just_my_code end,
        envFile = function() return dap_python().env_file end,
        console = "integratedTerminal",
        cwd = django_root,
        pythonPath = project_python,
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
        justMyCode = function() return dap_python().just_my_code end,
        envFile = function() return dap_python().env_file end,
        console = "integratedTerminal",
        cwd = django_root,
        pythonPath = project_python,
      })

      table.insert(dap.configurations.python, {
        name = "Celery: worker",
        type = "python",
        request = "launch",
        module = "celery",
        args = function()
          local configured = dap_python()
          local args = { "-A", configured.celery_app }
          vim.list_extend(args, vim.deepcopy(configured.celery_args))
          return args
        end,
        justMyCode = function() return dap_python().just_my_code end,
        envFile = function() return dap_python().env_file end,
        console = "integratedTerminal",
        cwd = django_root,
        pythonPath = project_python,
      })

      table.insert(dap.configurations.python, {
        name = "Python: attach debugpy (5678)",
        type = "python",
        request = "attach",
        connect = function()
          local configured = dap_python()
          return { host = configured.attach_host, port = configured.attach_port }
        end,
        pythonPath = project_python,
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
      if vim.g.lc_neotest_setup_done then
        return
      end
      vim.g.lc_neotest_setup_done = true

      local jest = require("neotest-jest")({})
      local jest_build_spec = jest.build_spec
      jest.build_spec = function(args)
        local data = args.tree and args.tree:data() or {}
        local profile = project_config.get(data.path)
        local configured = vim.deepcopy(profile.neotest.jest.args)
        if args.extra_args then
          vim.list_extend(configured, args.extra_args)
        end
        args = vim.tbl_extend("force", {}, args, { extra_args = configured })
        return jest_build_spec(args)
      end

      require("neotest").setup({
        adapters = {
          require("neotest-python")({
            dap = {
              justMyCode = function()
                return project_config.get(project_config.start_path()).dap.python.just_my_code
              end,
            },
            runner = python.neotest_runner,
            args = function(_, position)
              return project_config.neotest_args(position and position.path or nil)
            end,
            python = python.neotest_python,
          }),
          jest,
        },
        summary = {
          follow = false,
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
          local globals = vim.deepcopy(ctx.vars or {})
          local persisted_globals = vim.g.rest_nvim_javascript_globals or {}
          for key, value in pairs(persisted_globals) do
            if globals[key] == nil then
              globals[key] = value
            end
          end
          for key, value in pairs(vim.env) do
            if globals[key] == nil then
              globals[key] = value
            end
          end

          return {
            globals = globals,
            locals = vim.deepcopy(ctx.lv or {}),
            response = response or {},
          }
        end

        local function apply_result(ctx, result)
          local persisted_globals = vim.g.rest_nvim_javascript_globals or {}
          for key, value in pairs(result.locals or {}) do
            ctx:set_local(tostring(key), tostring(value))
          end
          for key, value in pairs(result.globals or {}) do
            key = tostring(key)
            value = tostring(value)
            persisted_globals[key] = value
            ctx:set_global(key, value)
            vim.env[key] = value
          end
          vim.g.rest_nvim_javascript_globals = persisted_globals
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

        local function run_script(source, ctx, response)
          local result = run_node(source, collect_env(ctx, response))
          if not result then
            return response
          end
          apply_result(ctx, result)
          return result.response
        end

        function script.load_pre_req_hook(source, ctx)
          return function()
            run_script(source, ctx)
          end
        end

        function script.load_post_req_hook(source, ctx)
          return function(response)
            return run_script(source, ctx, response)
          end
        end

        function script.run(source, ctx, response)
          return run_script(source, ctx, response)
        end

        return script
      end

      vim.api.nvim_create_user_command("RestJsGlobals", function()
        vim.print(vim.g.rest_nvim_javascript_globals or {})
      end, {})

      vim.api.nvim_create_user_command("RestJsTestGlobal", function()
        local Context = require("rest-nvim.context").Context
        local script = require("rest-nvim.script.javascript")
        script.load_post_req_hook([[client.global.set("rest_js_test_token", "ok")]], Context:new())({ body = "{}" })
        vim.print(vim.g.rest_nvim_javascript_globals or {})
      end, {})

      do
        local Context = require("rest-nvim.context").Context
        if not Context._rest_nvim_javascript_globals_patched then
          local resolve = Context.resolve
          function Context:resolve(key)
            local value = resolve(self, key)
            if value ~= "" then
              return value
            end

            local globals = vim.g.rest_nvim_javascript_globals or {}
            local persisted = globals[key]
            return persisted ~= nil and tostring(persisted) or ""
          end
          Context._rest_nvim_javascript_globals_patched = true
        end
      end

      require("rest-nvim").setup()
    end,
  },
}
