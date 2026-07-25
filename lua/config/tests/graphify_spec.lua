local graphify = require("config.graphify")

local root = vim.fn.tempname()
local nested = vim.fs.joinpath(root, "apps", "service")
local graph_dir = vim.fs.joinpath(root, "graphify-out")
local source_dir = vim.fs.joinpath(root, "src")
vim.fn.mkdir(nested, "p")
vim.fn.mkdir(graph_dir, "p")
vim.fn.mkdir(source_dir, "p")

local graph = vim.fs.joinpath(graph_dir, "graph.json")
local source = vim.fs.joinpath(source_dir, "file with spaces.py")
vim.fn.writefile({ vim.json.encode({
  nodes = {
    { id = "auth", label = "Auth Module", community = 43 },
    { id = "database", label = "Database" },
  },
  links = {},
}) }, graph)
vim.fn.writefile({ "one", "two", "three" }, source)

local project = graphify.find_project(vim.fs.joinpath(nested, "main.py"), vim.fn.tempname())
assert(project and project.root == vim.fs.normalize(root), "finds the nearest Graphify project")
assert(project.graph == vim.fs.normalize(vim.uv.fs_realpath(graph)), "returns the absolute graph path")

local missing_root = vim.fn.tempname()
vim.fn.mkdir(missing_root, "p")
assert(graphify.find_project(vim.fs.joinpath(missing_root, "main.py"), missing_root) == nil, "returns nil without a graph")

local query_argv = graphify.build_argv("query", 'where does "auth" go?', project.graph, { dfs = true, budget = 12 })
assert(vim.deep_equal(query_argv, { "graphify", "query", 'where does "auth" go?', "--dfs", "--budget", "12", "--graph", project.graph }), "builds query argv")

local path_argv = graphify.build_argv("path", "Auth Module -> Database", project.graph)
assert(vim.deep_equal(path_argv, { "graphify", "path", "Auth Module", "Database", "--graph", project.graph }), "builds path argv")

local explain_argv = graphify.build_argv("explain", "RequestRouter", project.graph)
assert(vim.deep_equal(explain_argv, { "graphify", "explain", "RequestRouter", "--graph", project.graph }), "builds explain argv")

local update_argv = graphify.build_update_argv(root, { force = true })
assert(vim.deep_equal(update_argv, { "graphify", "update", root, "--force" }), "builds update argv")
local init_argv = graphify.build_init_argv(root, { no_cluster = true })
assert(vim.deep_equal(init_argv, { "graphify", "extract", root, "--no-cluster" }), "builds initialization argv")

local selection_buf = vim.api.nvim_create_buf(false, true)
local selection_line = 'local selected = "Auth Module/&"'
vim.api.nvim_buf_set_lines(selection_buf, 0, -1, false, { selection_line, "next line" })
local selected = graphify.extract_selection(selection_buf, { 0, 1, 7, 0 }, { 0, 1, #selection_line, 0 }, "v")
assert(selected == 'selected = "Auth Module/&"', "extracts a visual selection without changing its contents")
vim.api.nvim_buf_delete(selection_buf, { force = true })

local html = vim.fs.joinpath(root, "graphify-out", "graph.html")
local node_uri = graphify.build_preview_uri(html, { kind = "node", id = "Auth Module/&\"" })
assert(node_uri:find("#node=Auth%20Module%2F%26%22", 1, true), "encodes focused node preview URI")
local path_uri = graphify.build_preview_uri(html, {
  kind = "path",
  source_id = "Auth Module",
  target_id = "Data&base",
})
assert(path_uri:find("#path=Auth%20Module&Data%26base", 1, true), "encodes focused path preview URI")

vim.fn.writefile({ "<!doctype html>" }, html)
vim.cmd.cd(root)
local captured_preview
graphify.setup({
  keymap = "<leader>gq-graphify-test",
  preview_keymap = "<leader>gp-graphify-test",
  preview = {
    mode = "backend",
    backend = function(uri, detected_project, target)
      captured_preview = { uri = uri, root = detected_project.root, target = target }
    end,
  },
})
assert(vim.fn.exists(":GraphifyUpdate") == 2, "registers the Graphify update command")
assert(vim.fn.maparg("<leader>gu", "n") ~= "", "registers the Graphify update keymap")
assert(vim.fn.exists(":GraphifyInit") == 2, "registers the Graphify initialization command")
assert(vim.fn.maparg("<leader>gi", "n") ~= "", "registers the Graphify initialization keymap")
graphify.preview_node("Auth Module")
assert(captured_preview and captured_preview.target.id == "auth", "resolves preview labels to stable node IDs")
assert(captured_preview.uri:find("#node=auth", 1, true), "opens node preview using the resolved ID")
graphify.preview_node("Auth Module", 43)
assert(captured_preview and captured_preview.target.community == 43, "accepts a community hint for node preview resolution")

local original_system = vim.system
local streamed_stdout
local streamed_callback
local system_argv
vim.system = function(_, opts, callback)
  system_argv = _
  streamed_stdout = opts.stdout
  streamed_callback = callback
  return { kill = function() end }
end
local source_win = vim.api.nvim_get_current_win()
graphify.open()
local input_buf = vim.api.nvim_get_current_buf()
local transcript_buf = vim.b[input_buf].graphify_transcript_buffer
assert(transcript_buf and transcript_buf ~= input_buf, "Graphify creates distinct transcript and input buffers")
assert(graphify.is_graphify_buffer(transcript_buf), "recognizes the Graphify transcript buffer")
assert(graphify.is_graphify_buffer(input_buf), "recognizes the Graphify input buffer")
assert(graphify.group_state(transcript_buf) == graphify.group_state(input_buf), "both buffers share one Graphify group")
assert(not vim.bo[transcript_buf].modifiable and vim.bo[transcript_buf].readonly, "Graphify transcript is permanently read-only")
assert(vim.bo[input_buf].modifiable and not vim.bo[input_buf].readonly, "Graphify input is independently editable")
local input_placeholder = vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)[1]
assert(input_placeholder:find("› Ask Graphify:", 1, true) == 1, "Graphify input shows an actionable command placeholder")
local transcript_text = table.concat(vim.api.nvim_buf_get_lines(transcript_buf, 0, -1, false), "\n")
assert(not transcript_text:find("graphify>", 1, true), "Graphify transcript has no prompt placeholder")
graphify.preview_node("Auth Module")
local preview_kept_panel = false
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  local bufnr = vim.api.nvim_win_get_buf(win)
  preview_kept_panel = preview_kept_panel or bufnr == transcript_buf or bufnr == input_buf
end
assert(preview_kept_panel, "preview actions keep the Graphify panel visible")
graphify.close_group_for_buffer(transcript_buf)
vim.wait(20)
local visible_graphify_buffers = 0
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  local bufnr = vim.api.nvim_win_get_buf(win)
  if bufnr == transcript_buf or bufnr == input_buf then visible_graphify_buffers = visible_graphify_buffers + 1 end
end
assert(visible_graphify_buffers == 0, "closing one Graphify buffer hides the complete group")
graphify.open()
assert(vim.api.nvim_get_current_buf() == input_buf, "reopens the same grouped input buffer")
vim.cmd("GraphifyQuery editability-test")
assert(vim.bo[input_buf].modifiable, "keeps the Graphify input editable after rendering a request")
graphify.open()
streamed_stdout(nil, "delayed output while hidden\n")
vim.wait(20)
streamed_callback({ code = 0, stderr = "" })
vim.wait(20)
local streamed_lines = vim.api.nvim_buf_get_lines(transcript_buf, 0, -1, false)
local retained_stream = false
for _, line in ipairs(streamed_lines) do
  retained_stream = retained_stream or line == "delayed output while hidden"
end
assert(retained_stream, "hidden Graphify retains streamed output")
graphify.open()
vim.cmd("stopinsert")
local transcript_win
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if vim.api.nvim_win_get_buf(win) == transcript_buf then transcript_win = win end
end
assert(transcript_win, "Graphify exposes a navigable transcript window")
local transcript_cursor = vim.api.nvim_win_get_cursor(transcript_win)
assert(transcript_cursor[1] == #streamed_lines, "completed Graphify requests scroll the transcript to the newest result")
vim.api.nvim_set_current_win(transcript_win)
vim.api.nvim_feedkeys("i", "x", false)
vim.wait(20)
assert(vim.api.nvim_get_current_buf() == input_buf, "Insert mode redirects from transcript to Graphify input")
assert(vim.bo[transcript_buf].modifiable == false, "transcript remains non-modifiable after insert redirect")
local input_window_before_close = vim.api.nvim_get_current_win()
vim.cmd("stopinsert")
vim.api.nvim_win_close(input_window_before_close, true)
vim.wait(20)
local transcript_still_visible = false
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  transcript_still_visible = transcript_still_visible or vim.api.nvim_win_get_buf(win) == transcript_buf
end
assert(not transcript_still_visible, "closing the input window hides the transcript sibling")
graphify.open()
assert(vim.api.nvim_get_current_buf() == input_buf, "reopening after a child-window close restores the input field")
local hidden_buf = input_buf
graphify.open()
assert(vim.api.nvim_get_current_win() == source_win, "smart toggle hides a focused Graphify panel")
graphify.open()
assert(vim.api.nvim_get_current_buf() == hidden_buf, "smart toggle reopens the same Graphify buffer")
local panel_win = vim.api.nvim_get_current_win()
assert(vim.bo[input_buf].modifiable, "reopened Graphify panel keeps the input editable")
vim.cmd("stopinsert")
vim.api.nvim_feedkeys("q", "x", false)
assert(vim.api.nvim_get_current_win() == source_win, "q hides Graphify without destroying the previous window")
graphify.open()
assert(vim.api.nvim_get_current_win() == panel_win or vim.api.nvim_get_current_buf() == hidden_buf, "hidden Graphify panel can be shown again")
vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { "› first line", "second line" })
vim.b[input_buf].graphify_input_placeholder = false
vim.api.nvim_set_current_win(vim.api.nvim_get_current_win())
local submit_mapping = vim.fn.maparg("<CR>", "i", false, true)
local newline_mapping = vim.fn.maparg("<S-CR>", "i", false, true)
assert(submit_mapping.callback, "Graphify input exposes an Enter submit mapping")
assert(newline_mapping.rhs == "<C-g>u<CR>", "Graphify input exposes a Shift-Enter newline mapping")
submit_mapping.callback()
vim.wait(20)
assert(system_argv and system_argv[3] == "first line\nsecond line", "Enter submits the complete multiline input")
vim.system = original_system
vim.cmd("stopinsert")
if vim.api.nvim_buf_is_valid(input_buf) then vim.cmd("bwipeout! " .. input_buf) end
vim.wait(20)
assert(not vim.api.nvim_buf_is_valid(transcript_buf), "explicit buffer wipe destroys the complete Graphify group")
assert(not vim.api.nvim_buf_is_valid(input_buf), "explicit buffer wipe removes the triggering Graphify buffer")

assert(graphify.parse_input("plain question").kind == "query", "plain input is a query")
assert(graphify.parse_input(":path A -> B").input == "A -> B", "parses path input")
assert(graphify.parse_input(":explain Node").kind == "explain", "parses explain input")

local reference = graphify.parse_reference("source: " .. source .. ":2:3", 18, root)
assert(reference and reference.path == vim.fs.normalize(vim.uv.fs_realpath(source)), "resolves paths with spaces")
assert(reference.line == 2 and reference.column == 3, "preserves source line and column")
local graphify_reference = graphify.parse_reference(
  "NODE .create() [src=" .. vim.fs.joinpath("src", "file with spaces.py") .. " loc=L59 community=43]",
  31,
  root
)
assert(graphify_reference and graphify_reference.path == vim.fs.normalize(vim.uv.fs_realpath(source)), "resolves Graphify NODE source metadata")
assert(graphify_reference.line == 59 and graphify_reference.column == 1, "converts Graphify loc=L59 to a source cursor position")
local bare_reference = graphify.parse_reference("See " .. source, 12, root)
assert(bare_reference and bare_reference.path == vim.fs.normalize(vim.uv.fs_realpath(source)), "resolves bare source paths")
assert(bare_reference.line == 1, "bare source paths default to line one")
assert(graphify.parse_reference("missing.py:2", 3, root) == nil, "ignores unreadable paths")

vim.fn.delete(root, "rf")
