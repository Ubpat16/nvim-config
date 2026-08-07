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

When the same normal file buffer is displayed in multiple windows in one tab,
closing the buffer with `<leader>bd` closes only the current window. The shared
buffer is deleted only from its final view.

### Tab

A tab is a Neovim tabpage: a layout container for one or more windows. Tabs,
layouts, tracked normal file buffers, and cursor state are runtime-only and do
not survive Neovim restarts. New launches begin with one blank tab in one fresh
`main` workspace. Tabs are presented in the tabline, but each workspace only
shows its own tabs there. The statusline shows the active workspace name with
neighbor arrows.

Important details:

- Tabs are assigned stable runtime IDs through the tab-local `lc_tab_id`
  variable.
- `winlayout()` leaf nodes have the shape `{ "leaf", winid }`; layout data is
  used only during the current session and is never serialized for restart.
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
native Neovim concept and it is not persisted across Neovim restarts. Tabs and
workspaces are recreated fresh on launch.

Workspaces group tabs and their tracked buffers inside the current Neovim
session. New workspaces must start as a blank single-window tab with a fresh
unnamed buffer without changing the files, splits, terminals, or plugin panes in
the workspace being left. The workspace state lives in:

- `workspaces`
- `workspace_order`
- `active_workspace`
- `tab_workspaces`

Each workspace stores its name and last active tab for the current session.
Creating, switching, renaming, listing, and closing workspaces is implemented
in `config.tabs`. Workspace IDs, names, order, and tab membership are never
written to disk.
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

File opening keeps duplicate routing, buffer ownership, and cursor restoration
synchronous. LSP profile refreshes, linting, Treesitter startup, and Git
decorations are deferred through
`config.deferred`; deferred callbacks must verify that their buffer or tab is
still valid before applying work.

## Key Files

- `tabs.lua`: source of truth for runtime workspace, tab, window, and buffer
  behavior.
- `project_config.lua`: loads the nearest project-owned JSON `nvim.config` and
  exposes a validated, reloadable project profile for editor options, Python,
  Django, tests, formatting, linting, LSP, DAP, and Python run helpers.
- `project_commands.lua`: builds shell-safe commands from the active project
  profile for direct pytest and Python execution.
- `graphify.lua`: detects Graphify projects, builds argument-list CLI requests,
  manages the asynchronous Graphify transcript and its persistent right-side
  panel, and opens source locations.
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

Graphify commands:

- `:Graphify`
- `:GraphifyQuery [question]`
- `:GraphifyPath <source> -> <target>`
- `:GraphifyExplain <node>`
- `:GraphifyUpdate`
- `:GraphifyInit`
- `:GraphifyPreview`
- `:GraphifyPreviewNode <node>`
- `:GraphifyPreviewPath <source> -> <target>`
- `:GraphifyPreviewResult`

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
- `<leader>mj` / `<leader>mk`: move the current line or selection down/up
- `<leader>bc`: clear the active workspace's normal file buffers
- `<leader>bzc`: clear all buffers and file registry entries
- `<leader>fp`: pick a file to preview in a floating window
- `<leader>gq`: smart-toggle the Graphify transcript panel for the nearest
  Graphify project
- visual `<leader>gq`: send the selected text to Graphify as a query
- `<leader>gp`: open the Graphify HTML preview
- `<leader>gu`: update Graphify output for the nearest project
- `<leader>gi`: initialize Graphify for a project without graph output
- `<leader>gP`: open the AI-assisted GitHub PR preview
- `<leader>dm`: run Django `migrate`; `<leader>dM`: run `makemigrations`

Graphify owns one unlisted `nofile` transcript buffer and one unlisted `nofile`
multiline input buffer per detected project. The visible panel has a managed
right-side transcript window and a bottom input window. The window uses
`Snacks.win` when available and managed native splits otherwise. The transcript
is permanently read-only and navigable in Normal mode; the input buffer is the
only editable buffer. `q` and `<Esc>` hide both windows without wiping either
buffer or cancelling a request; `<C-c>` cancels the request; and `<C-]>`
returns focus to the previous window without hiding the panel. `<CR>` submits
the input and `<S-CR>` inserts a newline. Insert/change commands from the
transcript redirect to the input field.
Preview and source-location actions do not hide the group. New tab and new
workspace creation call Graphify's tab-change hook to hide the current group
as part of establishing the new layout.
Graphify's update/watch rebuild already skips oversized HTML while preserving
the graph and report. Full initialization defaults to `extract --no-viz` for
large projects; callers can set `init.no_viz = false` when the project has been
reduced enough to render an interactive HTML preview.

These two child windows and buffers are owned by one Graphify panel group:

```text
workspace
  tabpage
    Graphify panel group
      transcript window → transcript buffer
      input window → input buffer
```

`config.graphify.is_graphify_buffer()` recognizes either child and
`close_group_for_buffer()` hides the complete group. The generic `<leader>bd`
mapping checks this ownership before normal buffer-close routing, so it cannot
leave one child visible. Raw `:bdelete`/`:bwipeout` is explicit destruction:
it cancels running work, closes both windows, wipes both buffers, and removes
the group's history and metadata. Reopening creates a fresh group after such
destruction, while ordinary hide/show restores the existing buffers and state.
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
- Do not make tabs or workspaces persistent without documenting the storage
  format, restore order, and interaction with existing tab IDs.
- Resolve project configuration from the active file or test position, not only
  from Neovim's startup directory. Keep `nvim.config` data-only; never execute
  it as Lua or a shell script.
- Resolve paths in `nvim.config` relative to that file. `project.root` controls
  tool working directories.
- Read project settings at buffer or action time so one Neovim session can host
  multiple projects. Preserve valid fields when another field is invalid and
  warn once per changed invalid config version.
- When changing keymaps, update both `keymaps.lua` and `README.md`.
- When changing terminology or the ownership model, update this file first or in
  the same commit.
