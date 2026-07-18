return {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      notifier = { enabled = true },
      input = { enabled = true },
      quickfile = { enabled = true },
      bigfile = { enabled = true },
      dashboard = { enabled = true },
      explorer = { enabled = false },
      image = { enabled = true },
      picker = {
        enabled = true,
        ui_select = true,
      },
      statuscolumn = { enabled = false },
    },
  },

  {
    "zbirenbaum/copilot.lua",
    event = "InsertEnter",
    cmd = { "Copilot" },
    config = function()
      require("config.ai").setup_copilot()
    end,
  },

  {
    "CopilotC-Nvim/CopilotChat.nvim",
    branch = "main",
    cmd = {
      "CopilotChat",
      "CopilotChatOpen",
      "CopilotChatClose",
      "CopilotChatToggle",
      "CopilotChatStop",
      "CopilotChatReset",
      "CopilotChatPrompts",
      "CopilotChatModels",
      "CopilotChatExplain",
      "CopilotChatReview",
      "CopilotChatFix",
      "CopilotChatOptimize",
      "CopilotChatTests",
      "CopilotChatFixDiagnostic",
    },
    dependencies = {
      "zbirenbaum/copilot.lua",
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim",
    },
    -- The upstream Makefile requires a Unix shell and `uname`. CopilotChat
    -- falls back to approximate token counting when the optional native
    -- tiktoken module is unavailable, so keep the optimized build on Unix
    -- without making native Windows plugin syncs fail.
    build = vim.fn.has("win32") == 1 and nil or "make tiktoken",
    config = function()
      require("config.ai").setup_copilot_chat()
    end,
  },

  {
    "ishiooon/codex.nvim",
    cmd = {
      "Codex",
      "CodexFocus",
      "CodexSend",
      "CodexTreeAdd",
    },
    dependencies = { "folke/snacks.nvim" },
    config = function()
      require("config.ai").setup_codex()
    end,
  },


}
