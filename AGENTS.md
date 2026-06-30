# Agent Notes

This file documents repository-specific conventions for agents working on this
Neovim config. Treat the implementation as the source of truth, but keep this
document updated when changing the window, tab, workspace, or buffer model.

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
workspace ownership and special-buffer cleanup. Tabs are presented in the
tabline, while the workspace name is presented in the statusline.

Important details:

- Tabs are assigned stable runtime IDs through the tab-local `lc_tab_id`
  variable.
- Bufferline and buffer next/previous navigation are scoped to the current tab's
  tracked normal file buffers.
- A buffer may be loaded globally in Neovim, but this config only shows it in
  the current tab's navigation if it is tracked for that tab.
- Special buffers can be owned by a tab/workspace without appearing in normal
  file-buffer navigation.

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
file by normalized path:

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
- When changing keymaps, update both `keymaps.lua` and `README.md`.
- When changing terminology or the ownership model, update this file first or in
  the same commit.
