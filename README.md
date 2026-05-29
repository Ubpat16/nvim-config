# Neovim Configuration

Personal Neovim configuration focused on Python/Django development, Git workflows, AI-assisted editing, testing, formatting, and fast project navigation.

This config is organized as Lua modules under `lua/config` and loaded from a minimal `init.lua`.

## Features

- Lazy-loaded plugin management with `lazy.nvim`
- LSP setup with Mason and `nvim-lspconfig`
- Python tooling with a stable global Python interpreter
- Formatting with `conform.nvim`
- Linting with `nvim-lint`
- Git hunk actions with `gitsigns.nvim`
- Git commit and GitHub PR helpers with OpenAI-generated drafts
- Persistent Git error popups for hook failures and command output
- Telescope project navigation
- Treesitter syntax support
- DAP and DAP UI for debugging
- Neotest for Python and JavaScript test workflows
- Django command helpers
- Copilot, Copilot Chat, and Codex integrations
- Autosave and last-project-file restore helpers
- REST client support for `.http` files

## Requirements

Install these system tools before using the config:

- Neovim 0.11 or newer
- Git
- `curl`
- `rg` from ripgrep
- `fd` or `fdfind`
- Node.js and npm
- Python 3
- `uv`
- GitHub CLI, `gh`
- A Nerd Font for icons

Optional but recommended:

- `pyenv` for a stable global Python install
- `tree-sitter` CLI
- `eslint_d`
- `prettier`

## Installation

Back up any existing config first:

```sh
mv ~/.config/nvim/lua/config ~/.config/nvim/lua/config.backup
```

Clone this config:

```sh
git clone <repo-url> ~/.config/nvim/lua/config
```

Start Neovim:

```sh
nvim
```

`lazy.nvim` will bootstrap itself and install plugins on first launch.

Run health checks after installation:

```vim
:checkhealth
```

## Python Interpreter Policy

This config deliberately avoids relying on each project's `.venv` for Neovim's own Python integrations.

Neovim tooling resolves one global interpreter in this order:

1. `NVIM_PYTHON`
2. `vim.g.python3_host_prog`
3. The global `pyenv` version from `~/.pyenv/version`
4. `python3` on `PATH`
5. `python` on `PATH`

The resolved interpreter is assigned to:

- Neovim Python provider through `vim.g.python3_host_prog`
- Pyright's `pythonPath`
- `nvim-dap-python`
- `neotest-python`
- Git/PR child commands launched by this config, with the global Python directory first on `PATH`

This keeps Neovim stable when project virtual environments are created, deleted, or changed.

To pin a specific interpreter:

```sh
export NVIM_PYTHON=/absolute/path/to/python
```

Explicit project commands that use `uv run`, such as the pytest helpers, still use the project's `uv` environment by design.

## AI Setup

### OpenAI Commit and PR Helpers

The OpenAI helper stores its API key in:

```text
~/.config/nvim/openai_config.json
```

Set it inside Neovim:

```vim
:OpenAISetKey sk-...
```

The OpenAI request path uses Lua plus `curl`; it does not use a Python SDK.

Important: do not commit `openai_config.json`. It contains a secret.

### Copilot and Codex

Copilot and Copilot Chat are configured in `lua/config/ai/init.lua` and loaded from `lua/config/plugins/ai.lua`.

Codex is configured with IDE integration enabled and opens in a right-side terminal split.

## Git Workflow

### Commit Helper

Use:

```vim
<leader>gc
```

This opens a commit-message floating window and asks OpenAI to draft a message from the current repository status and diff.

Inside the commit window:

| Key | Action |
| --- | --- |
| `<C-g>` | Regenerate commit message with OpenAI |
| `<C-s>` | Run `git add .` and `git commit -F <tempfile>` |
| `<CR>` | Run `git add .` and `git commit -F <tempfile>` |
| `q` | Close and cache the draft |

After a successful commit, the config prompts whether to push the current branch.

### PR Helper

Use:

```vim
<leader>gp
```

This generates a GitHub PR title and description from commits and diff against `main` or `master`, then opens a preview buffer. Save the preview with `:wq` to create the PR through `gh pr create`.

### Git Error Handling

Git and PR failures open a persistent details popup with:

- command
- exit code
- stdout
- stderr
- fallback message, when available

The popup waits for a keypress before closing. This is useful for Git hook failures, including Python or virtualenv errors from `pre-commit`, `commit-msg`, or project-specific hooks.

## Core Keymaps

Leader is space.

### Files and Search

| Key | Action |
| --- | --- |
| `<leader>e` | Toggle file explorer |
| `<leader>ff` | Find files |
| `<leader>fg` | Live grep |
| `<leader>fb` | Buffers |
| `<leader>fm` | Marks |
| `<leader>fh` | Help tags |
| `<leader>pb` | Browse project files |

### Git

| Key | Action |
| --- | --- |
| `<leader>gs` | Fugitive Git status |
| `<leader>gb` | Git blame |
| `<leader>gc` | AI-assisted commit |
| `<leader>gp` | AI-assisted GitHub PR |
| `<leader>gl` | Git log graph |
| `<leader>gg` | Git all-branches graph |
| `<F9>` | Preview Git hunk |
| `<F10>` | Reset Git hunk |
| `<F11>` | Reset current file |
| `<F12>` | Next Git hunk |
| `<S-F12>` | Previous Git hunk |

### AI

| Key | Action |
| --- | --- |
| `<leader>aa` | Toggle Codex terminal |
| `<leader>af` | Focus Codex terminal |
| `<leader>as` | Send visual selection to Codex |
| `<leader>ac` | Toggle Copilot Chat |
| `<leader>ap` | Copilot Chat prompt palette |
| `<leader>am` | Copilot Chat model picker |
| `<leader>ae` | Explain visual selection |
| `<leader>ar` | Review visual selection |
| `<leader>ai` | Fix visual selection |
| `<leader>ao` | Optimize visual selection |
| `<leader>at` | Generate tests for visual selection |
| `<leader>ad` | Fix diagnostic |
| `<leader>aR` | Reset Copilot Chat |

Copilot insert-mode mappings:

| Key | Action |
| --- | --- |
| `<M-Tab>` | Accept suggestion |
| `<C-y>` | Accept suggestion fallback |
| `<C-g>w` | Accept word |
| `<C-g>l` | Accept line |
| `<C-g>]` | Next suggestion |
| `<C-g>[` | Previous suggestion |
| `<C-g>x` | Dismiss suggestion |

### Buffers, Tabs, and Windows

| Key | Action |
| --- | --- |
| `<leader>bd` | Smart close buffer |
| `<leader>bc` | Clear all buffers and file registry |
| `<leader>bn` / `]b` | Next buffer in tab |
| `<leader>bp` / `[b` | Previous buffer in tab |
| `<leader>tn` | Next tab |
| `<leader>tp` | Previous tab |
| `<leader>to` | New tab |
| `<leader>tq` | Close tab |
| `<leader>tm` | Move window to new tab |
| `<C-h>` | Move to left window |
| `<C-l>` | Move to right window |
| `<C-j>` | Move to lower window |
| `<C-k>` | Move to upper window |

### Editing

| Key | Action |
| --- | --- |
| `<A-j>` | Move line or selection down |
| `<A-k>` | Move line or selection up |
| `<Tab>` in visual mode | Indent selection |
| `<S-Tab>` in visual mode | Outdent selection |
| `<leader>dl` | Duplicate line down |
| `<leader>dL` | Duplicate line up |
| `<leader>ds` | Duplicate visual selection down |
| `<leader>dS` | Duplicate visual selection up |
| `<leader>w` | Save |
| `<leader>qq` | Quit all |
| `<leader>nh` | Clear search highlight |

### Scratch and Clipboard

| Key | Action |
| --- | --- |
| `<leader>ns` | New scratch buffer in a tab |
| `<leader>nhs` | New horizontal scratch split |
| `<leader>nvs` | New vertical scratch split |
| `<leader>yp` | Copy absolute file path |
| `<leader>yr` | Copy relative file path |

### Formatting

| Key or Command | Action |
| --- | --- |
| `<leader>cf` | Format current buffer |
| `:Format` | Format current buffer |
| `:FormatWrite` | Format and write current buffer |

Python formatting is handled through `uvx ruff` and `uvx black` from `formatters.lua`.

### Testing and Debugging

| Key | Action |
| --- | --- |
| `<F5>` | Neotest nearest |
| `<F6>` | Neotest current file |
| `<F7>` | Toggle Neotest summary |
| `<F8>` | Open Neotest output |
| `<leader>Tn` | Neotest nearest |
| `<leader>Tf` | Neotest current file |
| `<leader>Ts` | Toggle Neotest summary |
| `<leader>To` | Open Neotest output |
| `<leader>pt` | Run nearest pytest via `uv` |
| `<leader>pf` | Run current pytest file via `uv` |
| `<leader>pa` | Run pytest suite via `uv` |
| `<leader>db` | DAP toggle breakpoint |
| `<leader>Dc` | DAP continue |
| `<leader>Di` | DAP step into |
| `<leader>Do` | DAP step over |
| `<leader>DO` | DAP step out |
| `<leader>Du` | Toggle DAP UI |

### Django

| Key | Action |
| --- | --- |
| `<leader>dc` | Django system check |
| `dm` | `manage.py makemigrations` |
| `dmm` | `manage.py migrate` |
| `dx` | Prompt for a custom Django command |
| `df` | Pick and run a Django script |

Django helpers search upward for `manage.py` and use `.env` files when available.

### REST Files

For `http` filetype buffers:

| Key | Action |
| --- | --- |
| `<leader>rr` | Run request |
| `<leader>rl` | Run last request |
| `<leader>ro` | Open result |
| `<leader>re` | Select env file |
| `<leader>rc` | Show cookies |
| `<leader>rg` | Show logs |

## Commands

| Command | Description |
| --- | --- |
| `:OpenAISetKey <key>` | Save and validate OpenAI API key |
| `:GitCommitAll` | Open AI-assisted commit prompt |
| `:GitCreatePR` | Generate and create GitHub PR |
| `:Format` | Format current buffer |
| `:FormatWrite` | Format and save current buffer |
| `:LastProjectFile` | Show remembered file for current project |
| `:LastProjectFileOpen` | Open remembered file for current project |
| `:LastProjectFileForget` | Forget a remembered project file |
| `:LastProjectFiles` | Show remembered files |
| `:SmartQuit` | Close buffer or quit when appropriate |

## Secrets and Files Not to Commit

Do not commit machine-local or secret files:

```text
openai_config.json
nvim.log
.DS_Store
.stfolder/
```

Recommended `.gitignore` entries:

```gitignore
openai_config.json
nvim.log
.DS_Store
.stfolder/
```

## Troubleshooting

### OpenAI Commit or PR Generation Fails

Check that:

- `openai_config.json` exists locally
- the key was set with `:OpenAISetKey`
- `curl` is installed
- network access is available

### Commit Fails With a Python or Virtualenv Error

The OpenAI generator does not use Python. A Python error during commit usually comes from a Git hook.

Use the persistent error popup to inspect stderr. Check:

```sh
git config --get core.hooksPath
ls .git/hooks
```

If the project uses `pre-commit`, install or repair that hook environment outside Neovim.

### Wrong Python Interpreter

Inside Neovim:

```vim
:lua print(require("config.python").global_python())
```

Override it with:

```sh
export NVIM_PYTHON=/absolute/path/to/python
```

### Plugin Issues

Use:

```vim
:Lazy
:Lazy sync
:checkhealth
```

## Notes

This is a personal config, not a general-purpose distribution. It assumes a Python/Django-heavy workflow, frequent GitHub PR creation, and AI-assisted coding. Treat keymaps and plugin choices as opinionated defaults.
