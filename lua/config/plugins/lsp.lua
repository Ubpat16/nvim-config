local python = require("config.python")
local project_config = require("config.project_config")

return {
  {
    "williamboman/mason.nvim",
    cmd = { "Mason", "MasonInstall", "MasonUpdate" },
    opts = {},
  },

  {
    "williamboman/mason-lspconfig.nvim",
    event = "VeryLazy",
    dependencies = { "williamboman/mason.nvim" },
    opts = {
      automatic_enable = false,
      ensure_installed = {
        "pyright",
        "ts_ls",
        "html",
        "cssls",
        "jsonls",
        "yamlls",
        "tailwindcss",
        "dockerls",
        "bashls",
      },
    },
  },

  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    event = "VeryLazy",
    dependencies = { "williamboman/mason.nvim" },
    opts = {
      ensure_installed = {
        "prettier",
        "ruff",
      },
    },
  },

  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
      "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
      local capabilities = require("cmp_nvim_lsp").default_capabilities()
      local tabs = require("config.tabs")

      local safe_lsp_jump_installed = rawget(vim.g, "lc_safe_lsp_jump_installed")
      if not safe_lsp_jump_installed then
        vim.g.lc_safe_lsp_jump_installed = true

        local original_jump_to_location = vim.lsp.util.jump_to_location

        local function location_range(location)
          return location.range or location.targetSelectionRange or location.targetRange
        end

        local function safe_location(location)
          if type(location) ~= "table" then
            return location
          end

          local target = vim.deepcopy(location)
          local uri = target.uri or target.targetUri
          local range = location_range(target)
          if type(uri) ~= "string" or type(range) ~= "table" or type(range.start) ~= "table" then
            return target
          end

          local start_line = tonumber(range.start.line)
          if not start_line then
            return target
          end

          local bufnr = vim.uri_to_bufnr(uri)
          pcall(vim.fn.bufload, bufnr)
          if not vim.api.nvim_buf_is_loaded(bufnr) then
            return target
          end

          local line_count = vim.api.nvim_buf_line_count(bufnr)
          if line_count <= 0 then
            return target
          end

          local max_line = math.max(line_count - 1, 0)
          range.start.line = math.max(0, math.min(start_line, max_line))
          if type(range["end"]) == "table" and type(range["end"].line) == "number" then
            range["end"].line = math.max(range.start.line, math.min(range["end"].line, max_line))
          end

          return target
        end

        vim.lsp.util.jump_to_location = function(location, ...)
          local results = { pcall(original_jump_to_location, safe_location(location), ...) }
          local ok = results[1]
          if not ok then
            local err = results[2]
            vim.schedule(function()
              vim.notify("LSP jump failed: " .. tostring(err), vim.log.levels.WARN)
            end)
            return nil
          end

          return unpack(results, 2)
        end
      end

      local function location_uri_and_range(location)
        if type(location) ~= "table" then
          return nil, nil
        end

        local uri = location.uri or location.targetUri
        local range = location.range or location.targetSelectionRange or location.targetRange
        if type(uri) ~= "string" or type(range) ~= "table" or type(range.start) ~= "table" then
          return nil, nil
        end

        return uri, range
      end

      local function normalized_location_path(location)
        local uri = location_uri_and_range(location)
        if type(uri) ~= "string" then
          return nil
        end

        local path = vim.uri_to_fname(uri)
        if path == "" then
          return nil
        end

        local real = vim.uv.fs_realpath(path)
        return vim.fs.normalize(real or vim.fn.fnamemodify(path, ":p"))
      end

      local function position_encoding_for(bufnr)
        local clients = vim.lsp.get_clients({ bufnr = bufnr })
        local client = clients[1]
        return client and client.offset_encoding or "utf-16"
      end

      local function preferred_location(locations)
        local fallback = nil

        for _, location in ipairs(locations) do
          fallback = fallback or location
          local path = normalized_location_path(location)
          if path then
            local bufnr = vim.fn.bufnr(path, false)
            if bufnr > 0 and tabs.buffer_owner(bufnr) then
              return location
            end
          end
        end

        return fallback
      end

      local function jump_to_location_in_workspace(location, position_encoding)
        local uri, range = location_uri_and_range(location)
        if not uri or not range then
          return false
        end

        local path = normalized_location_path(location)
        if not path then
          return false
        end

        local bufnr = vim.fn.bufadd(path)
        pcall(vim.fn.bufload, bufnr)
        tabs.focus_buffer_window(bufnr)

        local win = vim.api.nvim_get_current_win()
        if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= bufnr then
          return false
        end

        local line_count = vim.api.nvim_buf_line_count(bufnr)
        if line_count <= 0 then
          return true
        end

        local row = math.max(0, math.min(tonumber(range.start.line) or 0, line_count - 1))
        local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
        local col = 0
        if type(range.start.character) == "number" and range.start.character > 0 then
          local ok, byte_col = pcall(vim.str_byteindex, line, position_encoding, range.start.character, false)
          if ok and type(byte_col) == "number" then
            col = math.max(0, math.min(byte_col, #line))
          end
        end

        pcall(vim.api.nvim_win_set_cursor, win, { row + 1, col })
        vim.cmd("normal! zv")
        return true
      end

      local function jump_request(method, bufnr)
        local position_encoding = position_encoding_for(bufnr)
        local params = vim.lsp.util.make_position_params(0, position_encoding)

        vim.lsp.buf_request_all(bufnr, method, params, function(results)
          local locations = {}
          for _, res in pairs(results or {}) do
            if res and not res.err and res.result then
              if vim.islist(res.result) then
                vim.list_extend(locations, res.result)
              else
                locations[#locations + 1] = res.result
              end
            end
          end

          if #locations == 0 then
            vim.schedule(function()
              vim.notify("No location found", vim.log.levels.INFO)
            end)
            return
          end

          local location = preferred_location(locations)
          if not location then
            return
          end

          vim.schedule(function()
            jump_to_location_in_workspace(location, position_encoding)
          end)
        end)
      end

      vim.lsp.config("*", {
        capabilities = capabilities,
      })

      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("lc_lsp_attach", { clear = true }),
        callback = function(event)
          local bufnr = event.buf
          project_config.apply_lsp_settings(bufnr)
          if vim.bo[bufnr].filetype == "python" then
            vim.schedule(function()
              python.apply_project_python(bufnr)
            end)
          end

          local map = function(keys, func, desc)
            vim.keymap.set("n", keys, func, { buffer = bufnr, desc = desc })
          end

          map("gd", function()
            jump_request("textDocument/definition", bufnr)
          end, "Go to definition")
          map("gD", function()
            jump_request("textDocument/declaration", bufnr)
          end, "Go to declaration")
          map("gi", function()
            jump_request("textDocument/implementation", bufnr)
          end, "Go to implementation")
          map("gr", vim.lsp.buf.references, "References")
          map("K", vim.lsp.buf.hover, "Hover")
          map("<leader>rn", vim.lsp.buf.rename, "Rename")
          map("<leader>ca", vim.lsp.buf.code_action, "Code action")
          map("<leader>fd", vim.diagnostic.open_float, "Line diagnostics")
          map("[d", vim.diagnostic.goto_prev, "Previous diagnostic")
          map("]d", vim.diagnostic.goto_next, "Next diagnostic")
        end,
      })

      vim.lsp.config("pyright", {
        settings = {
          pyright = {
            disableOrganizeImports = true,
          },
          python = {
            analysis = {
              typeCheckingMode = "basic",
              autoSearchPaths = true,
              useLibraryCodeForTypes = true,
            },
          },
        },
      })

      vim.lsp.enable({
        "pyright",
        "ts_ls",
        "html",
        "cssls",
        "jsonls",
        "yamlls",
        "tailwindcss",
        "dockerls",
        "bashls",
      })

      local python_augroup = vim.api.nvim_create_augroup("lc_python_global_interpreter", { clear = true })

      vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
        group = python_augroup,
        pattern = { "*.py", "python" },
        callback = function(args)
          vim.schedule(function()
            python.apply_project_python(args.buf)
          end)
        end,
      })

      vim.api.nvim_create_autocmd("DirChanged", {
        group = python_augroup,
        callback = function()
          local bufnr = vim.api.nvim_get_current_buf()
          vim.schedule(function()
            python.apply_project_python(bufnr)
          end)
        end,
      })
    end,
  },

  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
      "rafamadriz/friendly-snippets",
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")

      require("luasnip.loaders.from_vscode").lazy_load()

      cmp.setup({
        completion = {
          completeopt = "menu,menuone,noselect,popup",
        },
        preselect = cmp.PreselectMode.None,
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        window = {
          completion = cmp.config.window.bordered(),
          documentation = cmp.config.window.bordered(),
        },
        formatting = {
          fields = { "kind", "abbr", "menu" },
          format = function(entry, item)
            local menu_labels = {
              nvim_lsp = "[LSP]",
              luasnip = "[Snip]",
              path = "[Path]",
              buffer = "[Buf]",
            }
            item.menu = menu_labels[entry.source.name] or ("[" .. entry.source.name .. "]")
            return item
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-j>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item({ behavior = cmp.SelectBehavior.Select })
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<C-k>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item({ behavior = cmp.SelectBehavior.Select })
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<CR>"] = cmp.mapping.confirm({ select = false }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item({ behavior = cmp.SelectBehavior.Select })
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item({ behavior = cmp.SelectBehavior.Select })
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp", priority = 1000 },
          { name = "luasnip", priority = 750 },
          { name = "path", priority = 500 },
          { name = "buffer", priority = 250, keyword_length = 3 },
        }),
      })
    end,
  },
}
