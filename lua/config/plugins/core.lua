local function lc_focus_buffer_window(bufnr)
  require("config.tabs").focus_buffer_window(bufnr)
end

local function lc_image_backend()
  local term = (vim.env.TERM or ""):lower()
  local term_program = (vim.env.TERM_PROGRAM or ""):lower()

  if vim.env.KITTY_WINDOW_ID or term:find("kitty", 1, true) or term_program:find("kitty", 1, true) then
    return "kitty"
  end

  if vim.env.WEZTERM_PANE or term_program:find("wezterm", 1, true) then
    return "kitty"
  end

  if vim.env.SNACKS_GHOSTTY == "true" or term_program:find("ghostty", 1, true) then
    return "kitty"
  end

  if vim.fn.executable("ueberzugpp") == 1 then
    return "ueberzug"
  end

  if vim.fn.executable("ueberzug") == 1 then
    return "ueberzug"
  end

  if vim.env.SNACKS_SIXEL == "true" or term:find("sixel", 1, true) then
    return "sixel"
  end

  return nil
end

return {
  { "nvim-lua/plenary.nvim", lazy = true },
  { "nvim-tree/nvim-web-devicons", lazy = true },

  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      vim.cmd.colorscheme("tokyonight-night")
    end,
  },

  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("config.statusline").setup()
    end,
  },

  {
    "akinsho/bufferline.nvim",
    version = "*",
    event = "VeryLazy",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        mode = "buffers",
        diagnostics = "nvim_lsp",
        separator_style = "thin",
        show_buffer_close_icons = false,
        show_close_icon = false,
        show_tab_indicators = false,
        left_mouse_command = lc_focus_buffer_window,
        custom_filter = function(bufnr)
          local tabs = require("config.tabs")
          return tabs.is_normal_file_buffer(bufnr) and tabs.is_in_current_tab(bufnr)
        end,
        custom_areas = {
          right = function()
            return require("config.tabline").bufferline_workspace_tabs()
          end,
        },
        offsets = {
          {
            filetype = "NvimTree",
            text = "Explorer",
            text_align = "left",
            separator = true,
          },
        },
      },
    },
  },

  {
    "3rd/image.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cond = function()
      return #vim.api.nvim_list_uis() > 0 and lc_image_backend() ~= nil
    end,
    opts = function()
      local backend = lc_image_backend()
      if not backend then
        return nil
      end

      return {
        backend = backend,
        processor = "magick_cli",
        integrations = {
          markdown = {
            enabled = true,
            clear_in_insert_mode = false,
            download_remote_images = false,
            only_render_image_at_cursor = false,
            filetypes = { "markdown", "vimwiki" },
          },
          html = { enabled = true },
          css = { enabled = true },
        },
        max_width = 100,
        max_height = 20,
        max_width_window_percentage = 80,
        max_height_window_percentage = 60,
        window_overlap_clear_enabled = true,
        hijack_file_patterns = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.avif" },
      }
    end,
  },

  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown", "vimwiki" },
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons",
    },
    opts = {
      file_types = { "markdown", "vimwiki" },
    },
  },

  {
    "lukas-reineke/indent-blankline.nvim",
    event = "VeryLazy",
    main = "ibl",
    opts = {},
  },

  {
    "numToStr/Comment.nvim",
    event = "VeryLazy",
    opts = {},
  },

  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    opts = {},
  },

  {
    "kylechui/nvim-surround",
    version = "*",
    event = "VeryLazy",
    opts = {},
  },

  {
    "mg979/vim-visual-multi",
    event = "VeryLazy",
  },

  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {},
    keys = {
      {
        "s",
        mode = { "n", "x", "o" },
        function()
          require("flash").jump()
        end,
        desc = "Flash",
      },
      {
        "S",
        mode = { "n", "x", "o" },
        function()
          require("flash").treesitter()
        end,
        desc = "Flash Treesitter",
      },
      {
        "r",
        mode = "o",
        function()
          require("flash").remote()
        end,
        desc = "Remote Flash",
      },
      {
        "R",
        mode = { "o", "x" },
        function()
          require("flash").treesitter_search()
        end,
        desc = "Treesitter Search",
      },
      {
        "<C-s>",
        mode = "c",
        function()
          require("flash").toggle()
        end,
        desc = "Toggle Flash Search",
      },
    },
  },

  {
    "nvim-tree/nvim-tree.lua",
    cmd = { "NvimTreeToggle", "NvimTreeFindFile", "NvimTreeFocus" },
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      hijack_cursor = true,
      sync_root_with_cwd = true,
      update_focused_file = {
        enable = true,
        update_root = true,
      },
      renderer = {
        root_folder_label = false,
        indent_markers = { enable = true },
        icons = {
          git_placement = "after",
          glyphs = {
            folder = {
              arrow_closed = "▶",
              arrow_open = "▼",
            },
          },
        },
      },
      view = {
        width = 36,
      },
      filters = {
        dotfiles = false,
      },
      git = {
        enable = true,
        ignore = false,
      },
    },
  },

  {
    "nvim-telescope/telescope.nvim",
    cmd = "Telescope",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope-ui-select.nvim",
    },
    config = function()
      require("config.telescope").setup()
    end,
  },

  {
    "nvim-telescope/telescope-ui-select.nvim",
    lazy = true,
  },

  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      signs = {
        add = { text = "+" },
        change = { text = "~" },
        delete = { text = "_" },
      },
      on_attach = function(bufnr)
        local gs = require("gitsigns")

        local map = function(lhs, rhs, desc)
          vim.keymap.set("n", lhs, rhs, { buffer = bufnr, desc = desc })
        end

        local next_hunk = function()
          if gs.nav_hunk then
            gs.nav_hunk("next")
          else
            gs.next_hunk()
          end
        end

        local prev_hunk = function()
          if gs.nav_hunk then
            gs.nav_hunk("prev")
          else
            gs.prev_hunk()
          end
        end

        map("<F9>", gs.preview_hunk, "Preview git hunk")
        map("<F10>", gs.reset_hunk, "Undo git hunk (restore from last commit)")
        map("<F11>", gs.reset_buffer, "Undo entire file (git restore)")
        map("<F12>", next_hunk, "Next git hunk")
        map("<S-F12>", prev_hunk, "Prev git hunk")
        map("<leader>gv", gs.preview_hunk, "Preview git hunk")
        map("<leader>gx", gs.reset_hunk, "Undo git hunk (restore from last commit)")
        map("<leader>gX", gs.reset_buffer, "Undo entire file (git restore)")
        map("<leader>gj", next_hunk, "Next git hunk")
        map("<leader>gk", prev_hunk, "Prev git hunk")
      end,
    },
  },

  {
    "tpope/vim-fugitive",
    cmd = { "Git", "G", "Gdiffsplit", "Gvdiffsplit", "GBlame" },
  },

  {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter").setup()
      require("nvim-treesitter").install({
        "bash",
        "css",
        "dockerfile",
        "gitignore",
        "html",
        "http",
        "javascript",
        "json",
        "kotlin",
        "lua",
        "markdown",
        "markdown_inline",
        "python",
        "regex",
        "tsx",
        "typescript",
        "vim",
        "vimdoc",
        "yaml",
      })

      local augroup = vim.api.nvim_create_augroup("lc_nvim_treesitter_ft", { clear = true })
      vim.api.nvim_create_autocmd("FileType", {
        group = augroup,
        pattern = "*",
        callback = function()
          if not pcall(vim.treesitter.start) then
            return
          end
          vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end,
      })
    end,
  },

  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    event = "VeryLazy",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {
      move = {
        enable = true,
        goto_next_start = {
          ["]m"] = "@function.outer",
          ["]]"] = "@class.outer",
        },
        goto_next_end = {
          ["]M"] = "@function.outer",
          ["]["] = "@class.outer",
        },
        goto_previous_start = {
          ["[m"] = "@function.outer",
          ["[["] = "@class.outer",
        },
        goto_previous_end = {
          ["[M"] = "@function.outer",
          ["[]"] = "@class.outer",
        },
      },
    },
  },
}
