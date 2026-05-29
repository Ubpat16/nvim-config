local function lc_focus_buffer_window(bufnr)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
      vim.api.nvim_set_current_win(win)
      return
    end
  end

  vim.cmd("buffer " .. bufnr)
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
        left_mouse_command = lc_focus_buffer_window,
        custom_filter = function(bufnr)
          local current_tab = vim.api.nvim_get_current_tabpage()
          local wins = vim.api.nvim_tabpage_list_wins(current_tab)

          for _, win in ipairs(wins) do
            if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
              return true
            end
          end

          return false
        end,
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
      return #vim.api.nvim_list_uis() > 0
    end,
    opts = {
      backend = "kitty",
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
