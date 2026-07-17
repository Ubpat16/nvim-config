# Agent Notes

This file documents repository-specific conventions for agents working on this
Neovim config. Treat the implementation as the source of truth, but keep this
document updated when changing the window, tab, workspace, buffer, or
project-state model.

## Buffers, Windows, Tabs, and Workspaces

The config intentionally uses four different concepts. Do not use these terms
interchangeably in code, docs, keymap descriptions, or issue summaries.

### Buffer

A buffer is a Neovim buffer: the in-memory handle for a file or other content.
In this repo, most buffer navigation logic only cares about a **normal file
buffer**.

`config.tabs.is_normal_file_buffer(bufnr)` defines a normal file buffer as:

- the buffer is valid
- `buflisted` is true
- `buftype` is empty
- the buffer has a non-empty name

Scratch buffers, terminal buffers, plugin UI buffers, unnamed buffers, help
buffers, quickfix buffers, floating buffers, fixed-window buffers, and other
special buffers are workspace-local when they are shown in a workspace-owned
tab, but they should not be included in Bufferline or normal file-buffer
navigation.

Normal file buffers remember cursor positions per window during the current
session. A tab-local position is used only when a window has not shown that
buffer before. This keeps two splits of the same file independent while still
giving replacement or newly created windows a useful restore position.

File preview floats created by `config.tabs.preview_file()` use unlisted
`nofile` buffers. They may be tracked as workspace-owned special buffers for
cleanup, but they must not be added to `tab_buffers`, shown in Bufferline, or
used for duplicate file routing. `config.tabs.select_file_preview()` opens the
file picker and previews the selected file.

### Window

A window is a Neovim viewport showing a buffer. It is not the same thing as a
buffer.

`config.tabs.is_normal_window(win)` defines a normal window as:

- the window is valid
- the window's buffer has an empty `buftype`
- the window is not `winfixbuf`

Window movement keymaps move the current buffer between split windows. They do
not rename, duplicate, or delete buffers.

### Tab

A tab is a Neovim tabpage: a layout container for one or more windows. This repo
persists tab identity, order, layout, and tracked normal file buffers across
Neovim restarts in `tabs.lua`, while still tracking displayed buffers for
workspace ownership and special-buffer cleanup. Persisted tab state now lives in
project-scoped files under `stdpath("state")/projects/` and is gated by the
startup project root. New tabs start blank and do not inherit the previous tab's
tracked file buffers. Tabs are presented in the tabline, but each workspace only
shows its own tabs there. The statusline shows the active workspace name with
neighbor arrows.

Important details:

- Tabs are assigned stable runtime IDs through the tab-local `lc_tab_id`
  variable.
- `winlayout()` leaf nodes have the shape `{ "leaf", winid }`; tab persistence
  must serialize the buffer displayed by that second value. Restore keeps a
  tracked-buffer fallback for legacy states whose leaf nodes omitted buffers.
- Bufferline owns Neovim's visible `tabline` after its `VeryLazy` setup. Its
  built-in native tab indicators must remain disabled because they enumerate
  every Neovim tab globally. `config.tabline.bufferline_workspace_tabs()`
  supplies the workspace-scoped, locally numbered tab list through
  Bufferline's right-side custom area.
- Bufferline and buffer next/previous navigation are scoped to the current tab's
  tracked normal file buffers.
- A tab's tracked normal file-buffer order is insertion-ordered. Entering,
  leaving, or focusing a buffer must not move it within that list; only adding
  or intentionally removing a buffer changes navigation order.
- Tab next/previous navigation is scoped to the active workspace, so cycling
  tabs never crosses into another workspace.
- A buffer may be loaded globally in Neovim, but this config only shows it in
  the current tab's navigation if it is tracked for that tab.
- Special buffers can be owned by a tab/workspace without appearing in normal
  file-buffer navigation.
- The statusline renders workspace navigation as three Lualine components. Only
  the `<<` and `>>` components are clickable; the workspace label is inert.

### Workspace

A workspace is a runtime-only grouping created by this config. It is not a
native Neovim concept and it is not persisted across Neovim restarts. Tabs are
the persisted unit; workspaces are recreated fresh on launch.

Workspaces group tabs and their tracked buffers inside the current Neovim
session. New workspaces must start as a blank single-window tab with a fresh
unnamed buffer without changing the files, splits, terminals, or plugin panes in
the workspace being left. The workspace state lives in:

- `workspaces`
- `workspace_order`
- `active_workspace`
- `tab_workspaces`

Each workspace stores its name and last active tab. Creating, switching,
renaming, listing, and closing workspaces is implemented in `config.tabs`.
Workspace IDs, names, order, and tab membership must not be written to the
project-state file. On restart, persisted native tabs are restored into one
fresh `main` workspace.
Split windows and special plugin panes remain in the workspace where they were
opened. Floating windows are snapshotted when leaving a tab and restored when
returning when their buffers are still valid. Closing a workspace closes its tabs
and wipes workspace-owned special buffers when they are not modified and are not
visible outside the closing tabs.

## Ownership Model

Use this hierarchy when reasoning about navigation:

```text
workspace
  tabpage
    window
      buffer
```

Practical implications:

- A workspace owns zero or more tabs.
- A tab owns a tracked list of normal file buffers for navigation.
- A tab also owns every valid buffer displayed in its normal, floating, and
  special plugin windows for workspace cleanup.
- A window displays exactly one buffer at a time.
- A buffer can exist in Neovim without being part of the current tab's tracked
  buffer list.
- Bufferline is configured to show only normal file buffers that belong to the
  current tab.

## Duplicate File Routing

The config avoids opening the same file in multiple workspace/tab contexts.

When entering a normal file buffer, `config.tabs` checks for an existing matching
file by normalized path. Multiple windows in the same tab may deliberately show
the same buffer and must not be rerouted. For other tabs and workspaces:

1. If the file is visible in another tab in the current workspace, switch to
   that tab/window.
2. If the file is tracked in another tab in the current workspace, switch to
   that tab and focus the buffer.
3. If the file belongs to a tab in another workspace, switch to that workspace
   and tab.
4. Otherwise, track the file in the current tab.

This behavior is implemented by `route_duplicate_buffer()` in `tabs.lua`. When
changing file-opening behavior, preserve this routing unless the requested
change explicitly alters the workspace model.

## Key Files

- `tabs.lua`: source of truth for runtime workspace, tab, window, and buffer
  behavior.
- `project_config.lua`: loads the nearest project-owned JSON `nvim.config` and
  exposes validated project defaults. Version one supports
  `neotest.args` as an array of strings.
- `tabline.lua`: renders workspace-local tab labels for Bufferline's custom
  right-side area. Visible numbering starts at 1 in each workspace, while click
  targets use the underlying native tab number.
- `keymaps.lua`: user-facing keymaps for buffer movement, tab commands,
  workspace commands, and smart quit.
- `plugins/core.lua`: Bufferline configuration and filtering through
  `config.tabs`.
- `README.md`: user-facing keymap and command documentation.

## User-Facing Commands and Keys

Log commands:

- `:AILogs`
- `:PluginLogs [source]`

Workspace commands:

- `:WorkspaceNew [name]`
- `:WorkspaceNext`
- `:WorkspacePrevious`
- `:WorkspaceList`
- `:WorkspaceRename <name>`
- `:WorkspaceClose`

Common keymaps:

- `<leader>bn` / `]b`: next buffer in current tab
- `<leader>bp` / `[b`: previous buffer in current tab
- `<leader>bc`: clear the active workspace's normal file buffers
- `<leader>bzc`: clear all buffers and file registry entries
- `<leader>fp`: pick a file to preview in a floating window
- `<leader>bh`, `<leader>bj`, `<leader>bk`, `<leader>bl`: move buffer to a
  neighboring split
- `<leader>bsh`, `<leader>bsj`, `<leader>bsk`, `<leader>bsl`: move buffer to a
  new split in that direction
- `<leader>tn`, `<leader>tp`, `<leader>to`, `<leader>tq`: tab navigation and
  creation/close
- `<leader>tm`: move current window to a new tab
- `<leader>zn`, `<leader>zj`, `<leader>zk`, `<leader>zl`, `<leader>zr`,
  `<leader>zq`: workspace actions
- `<C-h>`, `<C-j>`, `<C-k>`, `<C-l>`: move between windows
- `<C-o>` / `<C-i>`: older/newer native jumplist navigation; these mappings
  suppress cursor restoration and duplicate routing only while the jump runs

Keep README keymap documentation in sync when adding, removing, or changing
these mappings.

## Change Guidelines

- Prefer adding behavior to `tabs.lua` instead of scattering workspace state
  across unrelated modules.
- Keep "normal file buffer" and "normal window" filtering strict for Bufferline,
  file navigation, and duplicate file routing.
- Track special buffers for workspace ownership, but do not add them to
  `tab_buffers`.
- Do not make workspaces persistent without documenting the storage format,
  restore order, and interaction with existing tab IDs.
- Resolve project configuration from the active file or test position, not only
  from Neovim's startup directory. Keep `nvim.config` data-only; never execute
  it as Lua or a shell script.
- When changing keymaps, update both `keymaps.lua` and `README.md`.
- When changing terminology or the ownership model, update this file first or in
  the same commit.
