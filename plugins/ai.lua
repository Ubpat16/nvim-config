return {
  {
    "folke/snacks.nvim",
    priority = 900,
    lazy = false,
    opts = {
      notifier = { enabled = true },
      input = { enabled = true },
      quickfile = { enabled = true },
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
    build = "make tiktoken",
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
