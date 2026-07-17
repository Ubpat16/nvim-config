vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- nvim-treesitter needs `tree-sitter` on PATH (Homebrew: `brew install tree-sitter-cli`).
-- GUI-launched Nvim often omits Homebrew, so prepend when the binary is not found.
if vim.fn.executable("tree-sitter") == 0 and vim.fn.has("macunix") == 1 then
  for _, hb in ipairs({ "/opt/homebrew/bin", "/usr/local/bin" }) do
    if vim.uv.fs_stat(hb) and vim.fn.executable(hb .. "/tree-sitter") == 1 then
      vim.env.PATH = hb .. ":" .. (vim.env.PATH or "")
      break
    end
  end
end

-- Compatibility shim: older plugins (including older Telescope builds) may still
-- call vim.treesitter.language.ft_to_lang(), removed in newer Neovim versions.
if vim.treesitter and vim.treesitter.language and vim.treesitter.language.ft_to_lang == nil then
  vim.treesitter.language.ft_to_lang = function(filetype)
    return vim.treesitter.language.get_lang(filetype)
  end
end

-- Basic options
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.mouse = "a"
vim.opt.clipboard = "unnamedplus"
vim.opt.breakindent = true
vim.opt.undofile = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 200
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.list = true
vim.opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }
vim.opt.inccommand = "split"
vim.opt.cursorline = true
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.softtabstop = 2
vim.opt.smartindent = true
vim.opt.termguicolors = true
vim.opt.showtabline = 2
vim.opt.tabline = "%!v:lua.require('config.tabline').render()"
vim.opt.autowrite = true
vim.opt.autowriteall = true
vim.opt.hidden = true
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.opt.incsearch = true
vim.opt.timeout = true
vim.opt.timeoutlen = 800
vim.opt.ttimeoutlen = 100
vim.opt.completeopt = { "menu", "menuone", "noselect", "popup" }
vim.opt.pumheight = 12
vim.opt.foldmethod = "indent"
vim.opt.foldlevel = 99
vim.opt.foldenable = true


-- Folds --
vim.opt.fillchars = {
  fold = " ",
  foldopen = "",
  foldclose = "",
  foldsep = " ",
}

-- Python uses 4 spaces
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "python" },
  callback = function()
    vim.opt_local.expandtab = true
    vim.opt_local.shiftwidth = 4
    vim.opt_local.tabstop = 4
    vim.opt_local.softtabstop = 4
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "json" },
  callback = function()
    if vim.fn.executable("jq") == 1 then
      vim.opt_local.formatprg = "jq"
    end
    vim.opt_local.expandtab = true
    vim.opt_local.shiftwidth = 4
    vim.opt_local.tabstop = 4
    vim.opt_local.softtabstop = 4
  end,
})

local lc_disposable_ui_group = vim.api.nvim_create_augroup("lc_disposable_ui_buffers", { clear = true })

local function lc_configure_disposable_ui_window(event)
  local buf = event.buf
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  vim.bo[buf].buflisted = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false

  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
    vim.wo[win].winfixbuf = true
  end
end

vim.api.nvim_create_autocmd("FileType", {
  group = lc_disposable_ui_group,
  pattern = {
    "lazy",
    "lazy_backdrop",
    "copilot-chat",
    "snacks_terminal",
    "snacks_win",
  },
  callback = lc_configure_disposable_ui_window,
})

vim.api.nvim_create_autocmd("BufWinEnter", {
  group = lc_disposable_ui_group,
  callback = function(event)
    local buf = event.buf
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    local filetype = vim.bo[buf].filetype
    if filetype == "lazy" or filetype == "lazy_backdrop" or filetype == "copilot-chat" or filetype == "snacks_terminal"
      or filetype == "snacks_win" then
      lc_configure_disposable_ui_window(event)
    end
  end,
})

-- Diagnostics
vim.diagnostic.config({
  virtual_text = true,
  signs = true,
  underline = true,

  update_in_insert = false,
  severity_sort = true,
  float = { border = "rounded", source = "if_many" },
})

--- Walk upward from `start_dir` and return the first usable venv interpreter, or nil.
---@param start_dir string
