local M = {}

local function codex_notify_path()
  local path = vim.fs.joinpath(vim.fn.stdpath("state"), "codex", "notify.jsonl")
  local directory = vim.fs.dirname(path)
  if directory then
    vim.fn.mkdir(directory, "p")
  end
  return path
end

function M.setup_copilot()
  require("copilot").setup({
    panel = {
      enabled = false,
    },
    suggestion = {
      enabled = true,
      auto_trigger = true,
      hide_during_completion = true,
      debounce = 75,
      keymap = {
        accept = false,
        accept_word = false,
        accept_line = false,
        next = false,
        prev = false,
        dismiss = false,
      },
    },
    filetypes = {
      markdown = true,
      help = false,
      gitcommit = true,
      yaml = true,
      ["*"] = true,
    },
    copilot_node_command = "node",
    server_opts_overrides = {
      settings = {
        telemetry = {
          telemetryLevel = "off",
        },
      },
    },
    logger = {
      file = vim.fn.stdpath("log") .. "/copilot-lua.log",
      file_log_level = vim.log.levels.INFO,
      print_log_level = vim.log.levels.WARN,
    },
  })
end

function M.setup_copilot_chat()
  require("CopilotChat").setup({
    auto_insert_mode = true,
    question_header = "  User ",
    answer_header = "  Copilot ",
    error_header = "  Error ",
    separator = "━━",
    show_help = "yes",
    context = "buffers",
    window = {
      layout = "vertical",
      width = 0.40,
    },
    mappings = {
      complete = {
        detail = "Use completion menu",
        insert = "<Tab>",
      },
      close = {
        normal = "q",
        insert = "<C-c>",
      },
      reset = {
        normal = "<C-l>",
        insert = "<C-l>",
      },
    },
  })
end

function M.setup_codex()
  local notify_path = codex_notify_path()

  require("codex").setup({
    env = {
      CODEX_NVIM_NOTIFY_PATH = notify_path,
      ENABLE_IDE_INTEGRATION = "true",
    },
    terminal = {
      split_side = "right",
      split_width_percentage = 0.40,
      auto_close = true,
      unfocus_key = "<C-]>",
      snacks_win_opts = {
        position = "right",
        width = 0.40,
      },
    },
    status_indicator = {
      cli_notify_path = notify_path,
      turn_active_timeout_ms = 300000,
      turn_idle_grace_ms = 2000,
      inflight_timeout_ms = 300000,
    },
  })
end

function M.setup_openai()
  local openai = require("config.ai.openai")
  openai.setup()
  openai.create_commands()
end

return M
