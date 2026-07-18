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
- Snacks notifier, input, quickfile, bigfile, dashboard, explorer, image, and picker modules
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
- A terminal that supports Kitty Graphics Protocol if you want inline image rendering

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

This config keeps Neovim's own Python provider stable while letting project tooling use each project's virtual environment.

Neovim's host interpreter resolves one global interpreter in this order:

1. `NVIM_PYTHON`
2. `vim.g.python3_host_prog`
3. The global `pyenv` version from `~/.pyenv/version`
4. `python3` on `PATH`
5. `python` on `PATH`

That resolved interpreter is assigned to:

- Neovim Python provider through `vim.g.python3_host_prog`

Python project tooling resolves the nearest `.venv`, `venv`, or `env` interpreter from the current file or project root, falling back to the global host interpreter only when no project environment exists. The project interpreter is used for:

- Pyright's `pythonPath`
- `nvim-dap-python`
- `neotest-python`
- Git/PR child commands launched by this config, with the project Python directory first on `PATH`

This keeps Neovim stable while giving Pyright and test/debug integrations the packages and stubs installed in the active project.

To pin a specific interpreter:

```sh
export NVIM_PYTHON=/absolute/path/to/python
```

Explicit project commands that use `uv run`, such as the pytest helpers, still use the project's `uv` environment by design.

## Project Configuration

Project-specific settings can be stored in a JSON file named `nvim.config`. Neovim searches upward from the active file or test position, falling back to the current working directory, so one session can use different settings for different projects.

```json
{
  "project": {
    "root": "."
  },
  "editor": {
    "autosave": true,
    "options": {
      "expandtab": true,
      "shiftwidth": 4,
      "tabstop": 4,
      "softtabstop": 4,
      "textwidth": 100,
      "colorcolumn": "100",
      "wrap": false,
      "spell": false
    }
  },
  "python": {
    "interpreter": ".venv/bin/python"
  },
  "django": {
    "root": ".",
    "manage_py": "manage.py",
    "env_file": ".env.test"
  },
  "neotest": {
    "args": ["--ds=settings.personal_tests"],
    "python": { "runner": "pytest" },
    "jest": { "args": ["--runInBand"] }
  },
  "pytest": {
    "direct_args": ["--reuse-db"],
    "env_file": ".env.test"
  },
  "formatting": {
    "on_save": true,
    "timeout_ms": 5000,
    "by_filetype": {
      "python": ["ruff_fix_imports", "black"]
    }
  },
  "linting": {
    "enabled": true,
    "by_filetype": {
      "typescript": ["eslint_d"]
    }
  },
  "lsp": {
    "settings": {
      "pyright": {
        "python": {
          "analysis": { "typeCheckingMode": "strict" }
        }
      }
    }
  },
  "dap": {
    "python": {
      "just_my_code": false,
      "env_file": ".env.test",
      "django_runserver_args": ["runserver", "--noreload"],
      "celery_app": "config",
      "celery_args": ["worker", "-l", "info", "-P", "solo"],
      "attach_host": "127.0.0.1",
      "attach_port": 5678
    }
  },
  "run": {
    "python": {
      "args": [],
      "env_file": ".env"
    }
  }
}
```

All configured paths are resolved relative to the selected `nvim.config`. `project.root` changes tool and command working directories, but project-scoped tab and recent-file persistence continues to use the detected Git/project root. Env-file paths may point to files containing secrets; literal environment values and arbitrary shell commands are not accepted by the schema.

`neotest.args` remains backward compatible and applies to neotest plus the `<leader>pt`, `<leader>pf`, and `<leader>pa` direct pytest helpers. `pytest.direct_args` applies only to those direct helpers. Run-specific arguments such as `--pdb` or prompted pytest arguments remain appended by the invoking command.

Editor options are buffer-local and limited to `expandtab`, `shiftwidth`, `tabstop`, `softtabstop`, `textwidth`, `colorcolumn`, `wrap`, and `spell`. Formatter and linter entries replace the defaults for the named filetypes while unspecified filetypes keep their normal defaults. LSP settings are merged over the normal server settings, and DAP/neotest values are resolved when an action runs.

The file is checked for changes before each profile read and safe settings are reapplied on buffer and directory events. Missing fields preserve the normal defaults. Invalid or unknown fields produce one warning per changed file version and are ignored without discarding valid sibling settings. `nvim.config` takes precedence over inferred or standard project settings where both provide a value, remains data-only, and cannot execute Lua.

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

### Plugin Logs

Use `:AILogs` or `<leader>al` to tail AI logs in a terminal split. This follows:

```text
~/.local/state/nvim/openai.log
~/.local/state/nvim/copilot-lua.log
~/.local/state/nvim/codex/notify.jsonl
```

Use `:PluginLogs [source]` to tail plugin logs. Supported sources are `all`, `ai`, `nvim`, `openai`, `copilot`, and `codex`.

OpenAI request logs include request metadata, response sizes, and errors. They do not include prompts, diffs, responses, or API keys.

### Snacks

Snacks is enabled for notifications, input prompts, quickfile handling, large-file detection, dashboard, explorer, image rendering, and picker-backed `vim.ui.select`.

The existing `<leader>e` file explorer mapping still opens NvimTree, so enabling Snacks explorer does not replace the current explorer workflow.

## Git Workflow

### Commit Helper

Use:

```vim
<leader>gc
```

This opens a commit-message floating window and asks OpenAI to draft a message from the current repository status and diff.

Inside the commit window:

| Key     | Action                                         |
| ------- | ---------------------------------------------- |
| `<C-g>` | Regenerate commit message with OpenAI          |
| `<C-s>` | Run `git add .` and `git commit -F <tempfile>` |
| `<CR>`  | Run `git add .` and `git commit -F <tempfile>` |
| `q`     | Close and cache the draft                      |

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

| Key                                 | Action                          |
| ----------------------------------- | ------------------------------- |
| `<leader>e`                         | Toggle file explorer            |
| `<leader>ff`                        | Find files                      |
| `<leader>fg`                        | Live grep                       |
| `<leader>fp`                        | Pick file to preview            |
| `<leader>fb`                        | Buffers                         |
| `<leader>fm`                        | Marks                           |
| `<leader>fh`                        | Help tags                       |
| `<leader>pb`                        | Browse project files            |
| `s`                                 | Flash jump                      |
| `S`                                 | Flash Treesitter jump           |
| `r` in operator-pending mode        | Remote Flash                    |
| `R` in visual/operator-pending mode | Flash Treesitter search         |
| `<C-s>` while searching             | Toggle Flash search integration |

### Git

| Key          | Action                 |
| ------------ | ---------------------- |
| `<leader>gs` | Fugitive Git status    |
| `<leader>gb` | Git blame              |
| `<leader>gc` | AI-assisted commit     |
| `<leader>gp` | AI-assisted GitHub PR  |
| `<leader>gl` | Git log graph          |
| `<leader>gg` | Git all-branches graph |
| `<F9>`       | Preview Git hunk       |
| `<F10>`      | Reset Git hunk         |
| `<F11>`      | Reset current file     |
| `<F12>`      | Next Git hunk          |
| `<S-F12>`    | Previous Git hunk      |

### AI

| Key          | Action                              |
| ------------ | ----------------------------------- |
| `<leader>aa` | Toggle Codex terminal               |
| `<leader>af` | Focus Codex terminal                |
| `<leader>as` | Send visual selection to Codex      |
| `<leader>ac` | Toggle Copilot Chat                 |
| `<leader>ap` | Copilot Chat prompt palette         |
| `<leader>am` | Copilot Chat model picker           |
| `<leader>al` | Tail AI logs                        |
| `<leader>ae` | Explain visual selection            |
| `<leader>ar` | Review visual selection             |
| `<leader>ai` | Fix visual selection                |
| `<leader>ao` | Optimize visual selection           |
| `<leader>at` | Generate tests for visual selection |
| `<leader>ad` | Fix diagnostic                      |
| `<leader>aR` | Reset Copilot Chat                  |

Copilot insert-mode mappings:

| Key       | Action                     |
| --------- | -------------------------- |
| `<M-Tab>` | Accept suggestion          |
| `<C-y>`   | Accept suggestion fallback |
| `<C-g>w`  | Accept word                |
| `<C-g>l`  | Accept line                |
| `<C-g>]`  | Next suggestion            |
| `<C-g>[`  | Previous suggestion        |
| `<C-g>x`  | Dismiss suggestion         |

### Buffers, Tabs, and Windows

| Key                 | Action                              |
| ------------------- | ----------------------------------- |
| `<leader>bd`        | Close current view or buffer        |
| `<leader>bc`        | Clear current workspace buffers      |
| `<leader>bzc`       | Clear all buffers and file registry   |
| `<leader>bn` / `]b` | Next buffer in tab                  |
| `<leader>bp` / `[b` | Previous buffer in tab              |
| `<leader>bh`        | Move buffer to left split           |
| `<leader>bj`        | Move buffer to lower split          |
| `<leader>bk`        | Move buffer to upper split          |
| `<leader>bl`        | Move buffer to right split          |
| `<leader>bsh`       | Move buffer to new left split       |
| `<leader>bsj`       | Move buffer to new lower split      |
| `<leader>bsk`       | Move buffer to new upper split      |
| `<leader>bsl`       | Move buffer to new right split      |
| `<leader>tn`        | Next tab in workspace               |
| `<leader>tp`        | Previous tab in workspace           |
| `<leader>to`        | New tab from current window         |
| `<leader>tq`        | Close tab                           |
| `<leader>tm`        | Move window to new tab              |
| `<leader>zo`        | New workspace                       |
| `<leader>zn`        | Next workspace                      |
| `<leader>zp`        | Previous workspace                  |
| `<leader>zl`        | List workspaces                     |
| `<leader>zr`        | Rename workspace                    |
| `<leader>zq`        | Close workspace                     |
| `<C-h>`             | Move to left window                 |
| `<C-l>`             | Move to right window                |
| `<C-j>`             | Move to lower window                |
| `<C-k>`             | Move to upper window                |
| `<C-o>`             | Jump to older jumplist position     |
| `<C-i>`             | Jump to newer jumplist position     |

Tabs are persisted across Neovim restarts. A new tab starts blank and does not inherit the previous tab's tracked file buffers. Tab-local buffer navigation stays scoped to normal file buffers in the current tab and follows stable first-added order, so visiting a buffer does not renumber `[b` / `]b` navigation. Cursor positions are session-only and remembered per window and buffer, with a tab-local fallback for a window that has not shown the buffer before; two splits of the same file therefore retain independent cursor positions. When the same buffer is visible in multiple splits, `<leader>bd` closes only the current split; its final view deletes the buffer. Those cursor positions are cleared when the buffer is deleted with `<leader>bd`, `<leader>bc`, or `<leader>bzc`. Tabs remember layouts containing readable normal files when Neovim exits and starts again; plugin, special, directory, and blank windows are not restored. Tab next/previous navigation stays scoped to the active workspace. Workspaces remain runtime-only: after restart, all restored native tabs belong to one fresh `main` workspace.

Bufferline owns the visible tabline. Its buffer list is scoped to the current tab, and its right side shows only tabs from the active workspace, numbered from 1 within that workspace. Bufferline's global native-tab indicators are disabled so tabs from other workspaces remain hidden. The statusline shows the active workspace name with clickable `<<` and `>>` arrows for moving between available workspaces.

### Editing

| Key                      | Action                          |
| ------------------------ | ------------------------------- |
| `<A-j>`                  | Move line or selection down     |
| `<A-k>`                  | Move line or selection up       |
| `<Tab>` in visual mode   | Indent selection                |
| `<S-Tab>` in visual mode | Outdent selection               |
| `<leader>dl`             | Duplicate line down             |
| `<leader>dL`             | Duplicate line up               |
| `<leader>ds`             | Duplicate visual selection down |
| `<leader>dS`             | Duplicate visual selection up   |
| `<leader>w`              | Save                            |
| `<leader>qq`             | Quit all                        |
| `<leader>nh`             | Clear search highlight          |

### Scratch and Clipboard

| Key           | Action                       |
| ------------- | ---------------------------- |
| `<leader>ns`  | New scratch buffer in a tab  |
| `<leader>nhs` | New horizontal scratch split |
| `<leader>nvs` | New vertical scratch split   |
| `<leader>yp`  | Copy absolute file path      |
| `<leader>yr`  | Copy relative file path      |

### Formatting

| Key or Command | Action                          |
| -------------- | ------------------------------- |
| `<leader>cf`   | Format current buffer           |
| `:Format`      | Format current buffer           |
| `:FormatWrite` | Format and write current buffer |

Python formatting is handled through `uvx ruff` and `uvx black` from `formatters.lua`.

### Testing and Debugging

| Key          | Action                           |
| ------------ | -------------------------------- |
| `<F5>`       | Neotest nearest                  |
| `<F6>`       | Neotest current file             |
| `<F7>`       | Toggle Neotest summary           |
| `<F8>`       | Open Neotest output              |
| `<leader>Tn` | Neotest nearest                  |
| `<leader>Tf` | Neotest current file             |
| `<leader>Ts` | Toggle Neotest summary           |
| `<leader>To` | Open Neotest output              |
| `<leader>mt` | Neotest nearest                  |
| `<leader>mf` | Neotest current file             |
| `<leader>ma` | Neotest suite                    |
| `<leader>ml` | Neotest last run                 |
| `<leader>md` | Debug nearest test               |
| `<leader>mD` | Debug current test file          |
| `<leader>mp` | Neotest nearest with `--pdb`     |
| `<leader>mP` | Neotest current file with `--pdb` |
| `<leader>mx` | Prompt for nearest pytest args   |
| `<leader>mX` | Prompt for current-file pytest args |
| `<leader>ms` | Toggle Neotest summary           |
| `<leader>mo` | Open Neotest output              |
| `<leader>mO` | Toggle Neotest output panel      |
| `<leader>mw` | Toggle Neotest watch             |
| `<leader>mq` | Stop a running Neotest process   |
| `<leader>mi` | Attach to a running Neotest process |
| `]m`         | Next failed test                 |
| `[m`         | Previous failed test             |
| `<leader>pt` | Run nearest pytest via `uv`      |
| `<leader>pf` | Run current pytest file via `uv` |
| `<leader>pa` | Run pytest suite via `uv`        |
| `<leader>db` | DAP toggle breakpoint            |
| `<leader>dn` | DAP next line                    |
| `<leader>di` | DAP step into                    |
| `<leader>do` | DAP step out                     |
| `<leader>du` | Toggle DAP UI                    |
| `<leader>Dc` | DAP continue                     |
| `<leader>Di` | DAP step into                    |
| `<leader>Do` | DAP step over                    |
| `<leader>DO` | DAP step out                     |
| `<leader>Du` | Toggle DAP UI                    |

### Django

| Key          | Action                             |
| ------------ | ---------------------------------- |
| `<leader>dc` | Django system check                |
| `dm`         | `manage.py makemigrations`         |
| `dmm`        | `manage.py migrate`                |
| `dx`         | Prompt for a custom Django command |
| `df`         | Pick and run a Django script       |

Django helpers search upward for `manage.py` and use `.env` files when available.

### REST Files

For `http` filetype buffers:

| Key          | Action           |
| ------------ | ---------------- |
| `<leader>rr` | Run request      |
| `<leader>rl` | Run last request |
| `<leader>ro` | Open result      |
| `<leader>re` | Select env file  |
| `<leader>rc` | Show cookies     |
| `<leader>rg` | Show logs        |

## Commands

| Command                   | Description                               |
| ------------------------- | ----------------------------------------- |
| `:OpenAISetKey <key>`     | Save and validate OpenAI API key          |
| `:GitCommitAll`           | Open AI-assisted commit prompt            |
| `:GitCreatePR`            | Generate and create GitHub PR             |
| `:Format`                 | Format current buffer                     |
| `:FormatWrite`            | Format and save current buffer            |
| `:FilePreview [path]`     | Pick or preview file in a floating window |
| `:FilePreviewClose`       | Close file preview window                 |
| `:LastProjectFile`        | Show remembered file for current project  |
| `:LastProjectFileOpen`    | Open remembered file for current project  |
| `:LastProjectFileForget`  | Forget a remembered project file          |
| `:LastProjectFiles`       | Show remembered files                     |
| `:SmartQuit`              | Close buffer or quit when appropriate     |
| `:WorkspaceNew [name]`    | Create a runtime workspace                |
| `:WorkspaceNext`          | Switch to next workspace                  |
| `:WorkspacePrevious`      | Switch to previous workspace              |
| `:WorkspaceList`          | List and switch workspaces                |
| `:WorkspaceRename <name>` | Rename current workspace                  |
| `:WorkspaceClose`         | Close current workspace                   |

## Secrets and Files Not to Commit

Do not commit machine-local or secret files:

```text
openai_config.json
nvim.log
openai.log
copilot-lua.log
codex/notify.jsonl
.DS_Store
.stfolder/
```

Recommended `.gitignore` entries:

```gitignore
openai_config.json
nvim.log
openai.log
copilot-lua.log
codex/notify.jsonl
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
