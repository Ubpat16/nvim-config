local M = {}

local DEFAULTS = {
  keymap = "<leader>gq",
  selection_keymap = "<leader>gq",
  preview_keymap = "<leader>gp",
  update_keymap = "<leader>gu",
  init_keymap = "<leader>gi",
  allow_override = false,
  commands = {
    open = "Graphify",
    query = "GraphifyQuery",
    path = "GraphifyPath",
    explain = "GraphifyExplain",
    update = "GraphifyUpdate",
    init = "GraphifyInit",
    preview = "GraphifyPreview",
    preview_node = "GraphifyPreviewNode",
    preview_path = "GraphifyPreviewPath",
    preview_result = "GraphifyPreviewResult",
  },
  preview = {
    mode = "browser",
    command = nil,
    backend = nil,
  },
  update = {
    force = false,
    no_cluster = false,
  },
  init = {
    force = false,
    no_cluster = false,
  },
  window = {
    layout = "vertical",
    side = "right",
    width = 0.40,
    provider = "snacks",
    input_height = 3,
  },
  submit_key = "<CR>",
  newline_key = "<S-CR>",
  input_placeholder = "Ask Graphify: query text, :path source -> target, or :explain node",
  unfocus_key = "<C-]>",
}

local INPUT_PREFIX = "› "
local GRAPH_DIR = "graphify-out"
local GRAPH_FILE = "graph.json"
local states = {}
local graph_cache = {}
local config = vim.deepcopy(DEFAULTS)
local setup_done = false
local notify
local valid_buffer
local valid_window
local valid_input_buffer
local valid_input_window
local transcript_lines
local hide_panel
local ensure_window
local style_input_buffer
local cancel_request

local function normalize(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local expanded = vim.fn.fnamemodify(path, ":p")
  return vim.fs.normalize(vim.uv.fs_realpath(expanded) or expanded)
end

local function directory_for(path)
  local normalized = normalize(path)
  if not normalized then
    return nil
  end
  if vim.fn.isdirectory(normalized) == 1 then
    return normalized
  end
  return vim.fs.dirname(normalized)
end

local function ancestors(start)
  local result = {}
  local current = directory_for(start)
  while current do
    result[#result + 1] = current
    local parent = vim.fs.dirname(current)
    if parent == current then
      break
    end
    current = parent
  end
  return result
end

local function graph_at(root)
  local graph = vim.fs.joinpath(root, GRAPH_DIR, GRAPH_FILE)
  return vim.fn.filereadable(graph) == 1 and normalize(graph) or nil
end

--- Find the nearest Graphify project from a file/directory and cwd fallback.
function M.find_project(start_path, cwd)
  local seen = {}
  local function search(path)
    for _, root in ipairs(ancestors(path) or {}) do
      if not seen[root] then
        seen[root] = true
        local graph = graph_at(root)
        if graph then
          return { root = root, graph = graph }
        end
      end
    end
  end

  local found = search(start_path)
  if found then
    return found
  end
  return search(cwd or vim.uv.cwd() or vim.fn.getcwd())
end

--- Find the nearest sensible project root for initial Graphify extraction.
-- Existing projects are still detected strictly through graphify-out/graph.json;
-- initialization falls back to the nearest Git root, then the source directory.
function M.find_init_root(start_path, cwd)
  local start = directory_for(start_path) or directory_for(cwd) or vim.uv.cwd() or vim.fn.getcwd()
  local git_marker = vim.fs.find(".git", { path = start, upward = true })[1]
  if git_marker then
    return normalize(vim.fs.dirname(git_marker))
  end
  return normalize(start)
end

local function required_string(value, name)
  if type(value) ~= "string" or vim.trim(value) == "" then
    error(name .. " must be a non-empty string")
  end
  return value
end

--- Build an argument list for a Graphify CLI request.
function M.build_argv(kind, input, graph, opts)
  opts = opts or {}
  graph = required_string(graph, "graph")
  input = required_string(input, "input")
  local argv = { "graphify", kind, input }
  if kind == "path" then
    local source, target = input:match("^%s*(.-)%s*%-%>%s*(.-)%s*$")
    if not source or source == "" or target == "" then
      error("path input must use SOURCE -> TARGET")
    end
    argv = { "graphify", "path", source, target }
  elseif kind ~= "query" and kind ~= "explain" then
    error("unsupported Graphify command: " .. tostring(kind))
  end
  if kind == "query" then
    if opts.dfs then
      argv[#argv + 1] = "--dfs"
    end
    if opts.budget ~= nil then
      argv[#argv + 1] = "--budget"
      argv[#argv + 1] = tostring(opts.budget)
    end
  end
  argv[#argv + 1] = "--graph"
  argv[#argv + 1] = graph
  return argv
end

--- Build the official Graphify update argv without shell interpolation.
function M.build_update_argv(root, opts)
  root = required_string(root, "root")
  opts = opts or {}
  local argv = { "graphify", "update", root }
  if opts.force then
    argv[#argv + 1] = "--force"
  end
  if opts.no_cluster then
    argv[#argv + 1] = "--no-cluster"
  end
  return argv
end

--- Build the official Graphify initial extraction argv.
function M.build_init_argv(root, opts)
  root = required_string(root, "root")
  opts = opts or {}
  local argv = { "graphify", "extract", root }
  if opts.force then
    argv[#argv + 1] = "--force"
  end
  if opts.no_cluster then
    argv[#argv + 1] = "--no-cluster"
  end
  return argv
end

--- Parse a line entered in the Graphify prompt.
function M.parse_input(input)
  input = vim.trim(input or "")
  if input == "" then
    return nil
  end
  local command, rest = input:match("^:(%S+)%s*(.*)$")
  if command == "query" or command == "path" or command == "explain" then
    return { kind = command, input = vim.trim(rest) }
  end
  return { kind = "query", input = input }
end

local function encode_uri_component(value)
  return tostring(value):gsub("([^%w%-_%.~])", function(char)
    return string.format("%%%02X", char:byte())
  end)
end

--- Build a safe file URI for a whole-graph, node, or path preview.
function M.build_preview_uri(html_path, target)
  local uri = vim.uri_from_fname(html_path)
  if not target then
    return uri
  end
  if target.kind == "node" then
    return uri .. "#node=" .. encode_uri_component(target.id or target.label)
  end
  if target.kind == "path" then
    return uri .. "#path=" .. encode_uri_component(target.source_id or target.source)
      .. "&" .. encode_uri_component(target.target_id or target.target)
  end
  return uri
end

local function graph_fingerprint(stat)
  local mtime = stat and stat.mtime or {}
  return table.concat({ stat and stat.size or 0, mtime.sec or 0, mtime.nsec or 0 }, ":")
end

local function load_graph_index(project)
  local stat = vim.uv.fs_stat(project.graph)
  local fingerprint = graph_fingerprint(stat)
  local cached = graph_cache[project.graph]
  if cached and cached.fingerprint == fingerprint then
    return cached.index
  end
  local file = io.open(project.graph, "r")
  local content = file and file:read("*a") or nil
  if file then file:close() end
  local ok, decoded = pcall(vim.json.decode, content or "")
  if not ok or type(decoded) ~= "table" then
    notify("Graphify graph.json could not be parsed.", vim.log.levels.ERROR)
    return nil
  end
  local index = { by_id = {}, exact = {}, folded = {} }
  for _, node in ipairs(decoded.nodes or {}) do
    local id = tostring(node.id or node.label or "")
    local label = tostring(node.label or id)
    if id ~= "" then
      local normalized = {
        id = id,
        label = label,
        community = node.community,
        community_name = node.community_name,
      }
      index.by_id[id] = normalized
      index.exact[label] = index.exact[label] or {}
      index.exact[label][#index.exact[label] + 1] = normalized
      local folded = label:lower()
      index.folded[folded] = index.folded[folded] or {}
      index.folded[folded][#index.folded[folded] + 1] = normalized
    end
  end
  graph_cache[project.graph] = { fingerprint = fingerprint, index = index }
  return index
end

local function resolve_node(project, label, callback, community)
  local index = load_graph_index(project)
  if not index then return end
  label = vim.trim(label or "")
  local candidates = index.by_id[label] and { index.by_id[label] } or index.exact[label]
  candidates = candidates or index.folded[label:lower()]
  if candidates and community ~= nil and tostring(community) ~= "" then
    local requested = tostring(community)
    local filtered = {}
    for _, candidate in ipairs(candidates) do
      if tostring(candidate.community or "") == requested
        or tostring(candidate.community_name or "") == requested
        or tostring(candidate.community_name or ""):lower() == requested:lower()
      then
        filtered[#filtered + 1] = candidate
      end
    end
    candidates = filtered
  end
  if not candidates or #candidates == 0 then
    local suffix = community ~= nil and (" in community " .. tostring(community)) or ""
    notify("Graphify node not found: " .. label .. suffix, vim.log.levels.WARN)
    return
  end
  if #candidates == 1 then
    callback(candidates[1])
    return
  end
  vim.ui.select(candidates, {
    prompt = "Select Graphify node: ",
    format_item = function(item)
      local community_text = item.community ~= nil and (", community " .. tostring(item.community)) or ""
      return item.label .. " (" .. item.id .. community_text .. ")"
    end,
  }, function(choice)
    if choice then callback(choice) end
  end)
end

local function preview_html(project, target)
  local html = vim.fs.joinpath(project.root, GRAPH_DIR, "graph.html")
  if vim.fn.filereadable(html) == 0 then
    notify("Graphify preview not found: " .. html, vim.log.levels.WARN)
    return
  end
  local graph_stat = vim.uv.fs_stat(project.graph)
  local html_stat = vim.uv.fs_stat(html)
  if graph_stat and html_stat and (html_stat.mtime.sec or 0) < (graph_stat.mtime.sec or 0) then
    notify("Graphify preview is older than graph.json; showing the existing HTML.", vim.log.levels.WARN)
  end
  local uri = M.build_preview_uri(html, target)
  if config.preview.mode == "backend" then
    if type(config.preview.backend) ~= "function" then
      notify("Graphify preview backend is not configured.", vim.log.levels.WARN)
      return
    end
    local ok, err = pcall(config.preview.backend, uri, project, target)
    if not ok then notify("Graphify preview backend failed: " .. tostring(err), vim.log.levels.ERROR) end
    return
  end
  local argv
  if config.preview.mode == "command" then
    if type(config.preview.command) ~= "table" or #config.preview.command == 0 then
      notify("Graphify preview command must be a non-empty argv list.", vim.log.levels.ERROR)
      return
    end
    argv = vim.deepcopy(config.preview.command)
    argv[#argv + 1] = uri
  elseif vim.fn.has("macunix") == 1 then
    argv = { "open", uri }
  elseif vim.fn.has("win32") == 1 then
    argv = { "cmd.exe", "/c", "start", "", uri }
  else
    argv = { "xdg-open", uri }
  end
  if vim.fn.executable(argv[1]) == 0 then
    notify("Graphify preview browser command was not found: " .. argv[1], vim.log.levels.ERROR)
    return
  end
  vim.system(argv, { text = true }, function(result)
    if result.code ~= 0 then
      notify("Graphify preview browser failed: " .. vim.trim(result.stderr or ""), vim.log.levels.ERROR)
    end
  end)
end

local function preview_project_target(project, target)
  if not target then
    preview_html(project)
    return
  end
  if target.kind == "node" then
  resolve_node(project, target.label or target.id, function(node)
    target.id = node.id
    target.label = node.label
    preview_html(project, target)
    end, target.community)
    return
  end
  resolve_node(project, target.source, function(source)
    resolve_node(project, target.target, function(destination)
      target.source_id = source.id
      target.target_id = destination.id
      target.source = source.label
      target.target = destination.label
      preview_html(project, target)
    end, target.target_community)
  end, target.source_community)
end

local function resolve_candidate(candidate, root)
  candidate = vim.trim(candidate):gsub("^[%[%(<{\"']+", ""):gsub("[%]%)>},;\"']+$", "")
  candidate = candidate:gsub("^file://", "")
  if candidate == "" then
    return nil
  end
  local path = candidate:match("^/") and candidate or vim.fs.joinpath(root, candidate)
  path = normalize(path)
  return path and vim.fn.filereadable(path) == 1 and path or nil
end

local function parse_graphify_location(value)
  local line_number, column_number = tostring(value or ""):match("^L(%d+):(%d+)$")
  if line_number then
    return tonumber(line_number), tonumber(column_number)
  end
  line_number = tostring(value or ""):match("^L(%d+)$")
  return line_number and tonumber(line_number) or nil, 1
end

--- Resolve a source location under a cursor column.
function M.parse_reference(line, column, root)
  if type(line) ~= "string" or type(root) ~= "string" then
    return nil
  end
  column = column or 0

  -- Graphify query output annotates nodes as:
  -- NODE Label [src=path/to/file.py loc=L59 community=43]
  -- Resolve this form before the generic path scanner so loc=L59 is not
  -- mistaken for an ordinary label or omitted as a non-numeric location.
  local metadata_start, metadata_end = line:find("%[src=", 1)
  if metadata_start then
    local source, location = line:match("%[src=(.-)%s+loc=([^%s%]]+)", metadata_start)
    local line_number, column_number = parse_graphify_location(location)
    if source and line_number then
      local source_start = metadata_start + 5
      local source_end = source_start + #source - 1
      local metadata_cursor_end = line:find("]", metadata_start, true) or source_end
      local resolved = resolve_candidate(source, root)
      if resolved and (column == 0 or (column >= metadata_start - 1 and column <= metadata_cursor_end)) then
        return {
          path = resolved,
          line = line_number,
          column = column_number,
          start_col = source_start - 1,
          end_col = source_end,
        }
      end
    end
  end

  local best
  local search_from = 1
  while true do
    local colon_start, colon_end, line_number, column_number = line:find(":(%d+):(%d+)", search_from)
    if not colon_start then
      colon_start, colon_end, line_number = line:find(":(%d+)", search_from)
    end
    if not colon_start then
      break
    end
    local path_end = colon_start - 1
    for path_start = 1, path_end do
      local candidate = line:sub(path_start, path_end)
      local resolved = resolve_candidate(candidate, root)
      if resolved then
        local target_start = path_start - 1
        local target_end = colon_end
        if column >= target_start and column <= target_end then
          best = {
            path = resolved,
            line = tonumber(line_number),
            column = tonumber(column_number),
            start_col = target_start,
            end_col = target_end,
          }
        elseif not best then
          best = {
            path = resolved,
            line = tonumber(line_number),
            column = tonumber(column_number),
            start_col = target_start,
            end_col = target_end,
          }
        end
      end
    end
    search_from = colon_end + 1
  end

  -- Also support a bare readable path, including paths with spaces. This is
  -- useful for Graphify output that reports a source file without a location.
  if not best then
    for path_start = 1, #line do
      for path_end = path_start, #line do
        local candidate = line:sub(path_start, path_end)
        local next_char = line:sub(path_end + 1, path_end + 1)
        if path_end == #line or next_char:match("[%s%]%)}>,;]") then
          local resolved = resolve_candidate(candidate, root)
          if resolved and (column == 0 or (column >= path_start - 1 and column <= path_end)) then
            local reference = {
              path = resolved,
              line = 1,
              column = 1,
              start_col = path_start - 1,
              end_col = path_end,
            }
            if not best or (path_end - path_start) > (best.end_col - best.start_col) then
              best = reference
            end
          end
        end
      end
    end
  end
  return best
end

notify = function(message, level)
  vim.schedule(function()
    vim.notify(message, level or vim.log.levels.INFO, { title = "Graphify" })
  end)
end

local function set_hl()
  local links = {
    GraphifyTitle = "Title",
    GraphifyCommand = "Statement",
    GraphifyTimestamp = "Comment",
    GraphifySuccess = "DiagnosticOk",
    GraphifyFailure = "DiagnosticError",
    GraphifyStderr = "DiagnosticWarn",
    GraphifyHelp = "Comment",
    GraphifyInputTitle = "Special",
    GraphifyInput = "Special",
    GraphifyInputPrompt = "DiagnosticInfo",
    GraphifyInputPlaceholder = "Comment",
    GraphifyInputText = "Normal",
    GraphifyInputContext = "String",
    GraphifyInputNormal = "NormalFloat",
    GraphifyInputNormalNC = "NormalFloat",
    GraphifyPath = "Underlined",
    GraphifyArrow = "Operator",
    GraphifyConfidence = "Number",
  }
  for name, link in pairs(links) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
end

local function current_state()
  local current_buf = vim.api.nvim_get_current_buf()
  for _, existing in pairs(states) do
    if existing.buf == current_buf or existing.transcript_buf == current_buf or existing.input_buf == current_buf then
      return existing
    end
  end
  local root = M.find_project(vim.api.nvim_buf_get_name(0), vim.uv.cwd() or vim.fn.getcwd())
  if not root then
    notify("No Graphify project detected (expected graphify-out/graph.json).", vim.log.levels.WARN)
    return nil
  end
  local state = states[root.root]
  if not state then
    state = {
      root = root.root,
      graph = root.graph,
      history = {},
      history_index = 0,
      references = {},
      requests = {},
      input_cursor = { 1, 0 },
      transcript_cursor = { 1, 0 },
      hidden = true,
      closing = false,
      destroying = false,
    }
    states[root.root] = state
  end
  return state
end

--- Return the text covered by a visual selection.
-- Positions use the one-based row/column shape returned by getpos(). The
-- result stays one string so argv construction preserves spaces and quotes.
function M.extract_selection(bufnr, start_pos, end_pos, selection_mode)
  bufnr = bufnr or 0
  start_pos = start_pos or vim.fn.getpos("'<")
  end_pos = end_pos or vim.fn.getpos("'>")
  if not valid_buffer({ buf = bufnr }) or not start_pos or not end_pos then
    return nil
  end

  local start_row, start_col = start_pos[2] - 1, math.max(0, start_pos[3] - 1)
  local end_row, end_col = end_pos[2] - 1, math.max(0, end_pos[3])
  if selection_mode == "V" then
    start_col = 0
    end_row = end_pos[2]
    end_col = 0
  end
  local ok, lines = pcall(vim.api.nvim_buf_get_text, bufnr, start_row, start_col, end_row, end_col, {})
  if not ok or not lines then
    return nil
  end
  local text = vim.trim(table.concat(lines, "\n"))
  return text ~= "" and text or nil
end

local function sync_buffer_metadata(state)
  if valid_buffer and valid_buffer(state) then
    vim.b[state.buf].graphify_project_root = state.root
    vim.b[state.buf].graphify_graph_path = state.graph
    vim.b[state.buf].graphify_requests = state.requests
    vim.b[state.buf].graphify_group_root = state.root
    vim.b[state.buf].graphify_role = "transcript"
  end
  if valid_input_buffer and valid_input_buffer(state) then
    vim.b[state.input_buf].graphify_project_root = state.root
    vim.b[state.input_buf].graphify_graph_path = state.graph
    vim.b[state.input_buf].graphify_transcript_buffer = state.buf
    vim.b[state.input_buf].graphify_group_root = state.root
    vim.b[state.input_buf].graphify_role = "input"
  end
end

local function request_for_line(state, row)
  for index = #state.requests, 1, -1 do
    local request = state.requests[index]
    if request.completed and row >= (request.result_start or 1) and row <= (request.result_end or row) then
      return request
    end
  end
end

local function result_target_for_line(state, row)
  local lines = transcript_lines(state)
  local line = lines[row] or ""
  local request = request_for_line(state, row)
  if not request then return nil end
  if request.kind == "query" then
    local label, metadata = line:match("^NODE%s+(.+)%s+%[(.-)%]%s*$")
    if label then
      return {
        kind = "node",
        label = vim.trim(label),
        community = metadata and metadata:match("community=([^%s%]]+)") or nil,
      }
    end
  elseif request.kind == "explain" then
    local label = line:match("^Node:%s*(.+)$")
    if label then return { kind = "node", label = vim.trim(label) } end
  elseif request.kind == "path" and (line:find("Shortest path", 1, true) or line:find("--", 1, true) or line:find("<--", 1, true)) then
    local source, target = request.input:match("^%s*(.-)%s*%-%>%s*(.-)%s*$")
    if source and target then
      return { kind = "path", source = vim.trim(source), target = vim.trim(target) }
    end
  end
end

local function result_target_under_cursor(state)
  if not valid_window(state) then return nil end
  local row = vim.api.nvim_win_get_cursor(state.win)[1]
  return result_target_for_line(state, row)
end

local function preview_state_target(state, target)
  local project = { root = state.root, graph = state.graph }
  preview_project_target(project, target)
end

local function preview_result(state)
  for index = #state.requests, 1, -1 do
    local request = state.requests[index]
    if request.completed then
      for row = request.result_end or 1, request.result_start or 1, -1 do
        local target = result_target_for_line(state, row)
        if target then
          preview_state_target(state, target)
          return
        end
      end
    end
  end
  notify("No actionable Graphify result was found.", vim.log.levels.INFO)
end

valid_buffer = function(state)
  return state.buf and vim.api.nvim_buf_is_valid(state.buf)
end

valid_window = function(state)
  return state.win and vim.api.nvim_win_is_valid(state.win)
end

valid_input_buffer = function(state)
  return state.input_buf and vim.api.nvim_buf_is_valid(state.input_buf)
end

valid_input_window = function(state)
  return state.input_win and vim.api.nvim_win_is_valid(state.input_win)
end

transcript_lines = function(state)
  if not valid_buffer(state) then
    return {}
  end
  return vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
end

local function input_lines(state)
  if not valid_input_buffer(state) then
    return { "" }
  end
  return vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)
end

local function input_text(state)
  if vim.b[state.input_buf].graphify_input_placeholder then
    return ""
  end
  local lines = input_lines(state)
  if lines[1] and lines[1]:sub(1, #INPUT_PREFIX) == INPUT_PREFIX then
    lines[1] = lines[1]:sub(#INPUT_PREFIX + 1)
  end
  return table.concat(lines, "\n")
end

local function input_placeholder_line()
  return INPUT_PREFIX .. (config.input_placeholder or DEFAULTS.input_placeholder)
end

local function set_input_placeholder(state)
  if not valid_input_buffer(state) then return end
  vim.bo[state.input_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { input_placeholder_line() })
  vim.b[state.input_buf].graphify_input_placeholder = true
  vim.bo[state.input_buf].modifiable = true
  state.input_cursor = { 1, #INPUT_PREFIX }
  if style_input_buffer then style_input_buffer(state) end
end

local function activate_input(state)
  if not valid_input_buffer(state) or not vim.b[state.input_buf].graphify_input_placeholder then return end
  local current = vim.api.nvim_buf_get_lines(state.input_buf, 0, 1, false)[1] or input_placeholder_line()
  local placeholder = input_placeholder_line()
  local user_text = current
  if current:sub(1, #INPUT_PREFIX) == INPUT_PREFIX then
    user_text = current:sub(#INPUT_PREFIX + 1)
    local placeholder_text = placeholder:sub(#INPUT_PREFIX + 1)
    user_text = user_text:gsub(vim.pesc(placeholder_text), "", 1)
  end
  vim.bo[state.input_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { INPUT_PREFIX .. user_text })
  vim.b[state.input_buf].graphify_input_placeholder = false
  if valid_input_window(state) then
    local cursor = vim.api.nvim_win_get_cursor(state.input_win)
    state.input_cursor = { 1, math.min(cursor[2], #INPUT_PREFIX + #user_text) }
  else
    state.input_cursor = { 1, #INPUT_PREFIX + #user_text }
  end
  if style_input_buffer then style_input_buffer(state) end
end

style_input_buffer = function(state)
  if not valid_input_buffer(state) then return end
  local buf = state.input_buf
  vim.api.nvim_buf_clear_namespace(buf, -1, 0, -1)
  for row, line in ipairs(input_lines(state)) do
    local zero = row - 1
    if vim.b[buf].graphify_input_placeholder then
      vim.api.nvim_buf_add_highlight(buf, -1, "GraphifyInputPlaceholder", zero, #INPUT_PREFIX, -1)
    else
      vim.api.nvim_buf_add_highlight(buf, -1, "GraphifyInputText", zero, #INPUT_PREFIX, -1)
    end
    vim.api.nvim_buf_add_highlight(buf, -1, "GraphifyInputPrompt", zero, 0, #INPUT_PREFIX)
  end
end

local function set_input_text(state, text)
  if not valid_input_buffer(state) then
    return
  end
  text = tostring(text or "")
  if vim.trim(text) == "" then
    set_input_placeholder(state)
    return
  end
  local lines = vim.split(text, "\n", { plain = true })
  if #lines == 0 then lines = { "" } end
  lines[1] = INPUT_PREFIX .. lines[1]
  vim.bo[state.input_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, lines)
  vim.b[state.input_buf].graphify_input_placeholder = false
  vim.bo[state.input_buf].modifiable = true
  style_input_buffer(state)
  if valid_input_window(state) then
    local row = math.min(state.input_cursor and state.input_cursor[1] or 1, #lines)
    local minimum_col = row == 1 and #INPUT_PREFIX or 0
    local col = math.max(minimum_col, math.min(state.input_cursor and state.input_cursor[2] or minimum_col, #lines[row] or 0))
    vim.api.nvim_win_set_cursor(state.input_win, { row, col })
  end
end

local function clear_input(state)
  set_input_placeholder(state)
  if valid_input_window(state) then
    vim.api.nvim_win_set_cursor(state.input_win, { 1, #INPUT_PREFIX })
  end
end

local function clamp_input_cursor(state)
  if not valid_input_window(state) then return end
  local cursor = vim.api.nvim_win_get_cursor(state.input_win)
  local minimum_col = cursor[1] == 1 and #INPUT_PREFIX or 0
  local col = math.max(minimum_col, cursor[2])
  if col ~= cursor[2] then
    vim.api.nvim_win_set_cursor(state.input_win, { cursor[1], col })
  end
  state.input_cursor = { cursor[1], col }
end

local function window_for_buffer(bufnr)
  if not bufnr then return nil end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
      return win
    end
  end
end

local function style_buffer(state)
  if not valid_buffer(state) then
    return
  end
  local buf = state.buf
  state.references = {}
  vim.api.nvim_buf_clear_namespace(buf, -1, 0, -1)
  for index, line in ipairs(transcript_lines(state)) do
    local zero = index - 1
    if line:match("^%[Graphify") then
      vim.api.nvim_buf_add_highlight(buf, -1, "GraphifyTitle", zero, 0, -1)
    elseif line:match("^%s*Command:") then
      vim.api.nvim_buf_add_highlight(buf, -1, "GraphifyCommand", zero, 0, -1)
    elseif line:match("^%s*[%w%-]+%s+%d%d:%d%d:%d%d") then
      vim.api.nvim_buf_add_highlight(buf, -1, "GraphifyTimestamp", zero, 0, -1)
    elseif line:match("^%[exit%s+0%]") then
      vim.api.nvim_buf_add_highlight(buf, -1, "GraphifySuccess", zero, 0, -1)
    elseif line:match("^%[exit") or line:match("^%[cancelled") then
      vim.api.nvim_buf_add_highlight(buf, -1, "GraphifyFailure", zero, 0, -1)
    elseif line:match("^stderr:") then
      vim.api.nvim_buf_add_highlight(buf, -1, "GraphifyStderr", zero, 0, -1)
    elseif line:match("^%s*Graphify commands") or line:match("^%s*Type") then
      vim.api.nvim_buf_add_highlight(buf, -1, "GraphifyHelp", zero, 0, -1)
    end
    for arrow_start in line:gmatch("()(%-%>)") do
      vim.api.nvim_buf_add_highlight(buf, -1, "GraphifyArrow", zero, arrow_start - 1, arrow_start + 1)
    end
    for confidence_start, confidence_text in line:gmatch("()(%[[%w%s%-]+confidence[%w%s%-]*%])") do
      vim.api.nvim_buf_add_highlight(
        buf,
        -1,
        "GraphifyConfidence",
        zero,
        confidence_start - 1,
        confidence_start - 1 + #confidence_text
      )
    end
    local reference = M.parse_reference(line, 0, state.root)
    if reference then
      state.references[index] = reference
      vim.api.nvim_buf_add_highlight(buf, -1, "GraphifyPath", zero, reference.start_col, reference.end_col)
    end
  end
end

local function render(state, lines)
  if not valid_buffer(state) then
    return
  end
  local modified = vim.bo[state.buf].modifiable
  local readonly = vim.bo[state.buf].readonly
  vim.bo[state.buf].modifiable = true
  vim.bo[state.buf].readonly = false
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = modified
  vim.bo[state.buf].readonly = readonly
  style_buffer(state)
end

local function append_lines(state, new_lines)
  if not valid_buffer(state) then
    return
  end
  local lines = transcript_lines(state)
  local cursor = valid_window(state) and vim.api.nvim_win_get_cursor(state.win) or nil
  local normalized_lines = {}
  for _, line in ipairs(new_lines or {}) do
    vim.list_extend(normalized_lines, vim.split(tostring(line), "\n", { plain = true }))
  end
  vim.list_extend(lines, normalized_lines)
  render(state, lines)
  if cursor and valid_window(state) then
    local row = math.min(cursor[1], math.max(1, #lines))
    vim.api.nvim_win_set_cursor(state.win, { row, math.min(cursor[2], #(lines[row] or "")) })
  end
end

local function scroll_transcript_to_end(state)
  if not valid_buffer(state) then
    return
  end
  local last_row = math.max(1, #transcript_lines(state))
  state.transcript_cursor = { last_row, 0 }
  if valid_window(state) then
    vim.api.nvim_win_set_cursor(state.win, state.transcript_cursor)
  end
end

local function restore_transcript_cursor(state)
  if not valid_window(state) or not state.transcript_cursor then
    return
  end
  local lines = transcript_lines(state)
  local row = math.min(state.transcript_cursor[1], math.max(1, #lines))
  local col = math.min(state.transcript_cursor[2], #(lines[row] or ""))
  state.transcript_cursor = { row, col }
  vim.api.nvim_win_set_cursor(state.win, state.transcript_cursor)
end

local function panel_is_visible(state)
  local transcript_visible = state.panel and type(state.panel.valid) == "function"
    and state.panel:valid() or valid_window(state)
  local input_visible = state.input_panel and type(state.input_panel.valid) == "function"
    and state.input_panel:valid() or valid_input_window(state)
  if state.panel or state.input_panel then
    return transcript_visible and input_visible
  end
  return valid_window(state) and valid_input_window(state)
end

hide_panel = function(state)
  if state.closing or state.destroying then return end
  state.closing = true
  local transcript_win = state.transcript_win or state.win
  local input_win = state.input_win
  if transcript_win and vim.api.nvim_win_is_valid(transcript_win) then
    state.transcript_cursor = vim.api.nvim_win_get_cursor(transcript_win)
  end
  if input_win and vim.api.nvim_win_is_valid(input_win) and vim.api.nvim_get_current_win() == input_win then
    state.input_cursor = vim.api.nvim_win_get_cursor(input_win)
  end
  local previous = state.previous_win
  if state.input_panel and type(state.input_panel.hide) == "function" then
    state.input_panel:hide()
  elseif input_win and vim.api.nvim_win_is_valid(input_win) then
    vim.api.nvim_win_close(input_win, false)
  end
  if state.panel and type(state.panel.hide) == "function" then
    state.panel:hide()
  elseif transcript_win and vim.api.nvim_win_is_valid(transcript_win) then
    vim.api.nvim_win_close(transcript_win, false)
  end
  state.win = nil
  state.input_win = nil
  state.transcript_win = nil
  state.hidden = true
  state.closing = false
  if previous and vim.api.nvim_win_is_valid(previous) then
    vim.api.nvim_set_current_win(previous)
  end
end

local function close_managed_window(panel, win)
  if panel and type(panel.close) == "function" then
    pcall(panel.close, panel, { buf = false })
  elseif win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
end

local function destroy_group(state)
  if not state or state.destroying then return end
  state.destroying = true
  state.closing = true
  cancel_request(state)
  local previous = state.previous_win
  close_managed_window(state.input_panel, state.input_win)
  close_managed_window(state.panel, state.win)
  for _, bufnr in ipairs({ state.input_buf, state.buf }) do
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end
  state.input_win = nil
  state.transcript_win = nil
  state.win = nil
  state.input_panel = nil
  state.panel = nil
  if state.lifecycle_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.lifecycle_augroup)
    state.lifecycle_augroup = nil
  end
  states[state.root] = nil
  state.closing = false
  if previous and vim.api.nvim_win_is_valid(previous) then
    vim.api.nvim_set_current_win(previous)
  end
end

function M.group_state(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  for _, state in pairs(states) do
    if state.buf == bufnr or state.transcript_buf == bufnr or state.input_buf == bufnr then
      return state
    end
  end
end

function M.is_graphify_buffer(bufnr)
  return M.group_state(bufnr) ~= nil
end

function M.close_group_for_buffer(bufnr)
  local state = M.group_state(bufnr)
  if not state then return false end
  hide_panel(state)
  return true
end

--- Hide Graphify groups that are visible in the current tab before creating a
--- new tab or workspace. Ordinary navigation and preview actions leave the
--- panel visible; this is an intentional layout boundary.
function M.hide_for_tab_change()
  local current_windows = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    current_windows[win] = true
  end
  for _, state in pairs(states) do
    local transcript_win = state.transcript_win or state.win
    if current_windows[transcript_win] or current_windows[state.input_win] then
      hide_panel(state)
    end
  end
end

cancel_request = function(state)
  if state.process and state.running then
    state.cancel_requested = true
    pcall(state.process.kill, state.process, "sigint")
  end
end

local function open_reference(state, reference)
  if not reference then
    return false
  end
  local previous = state.previous_win
  if previous and vim.api.nvim_win_is_valid(previous) then
    vim.api.nvim_set_current_win(previous)
  end
  vim.cmd("edit " .. vim.fn.fnameescape(reference.path))
  pcall(vim.api.nvim_win_set_cursor, 0, {
    math.max(1, reference.line or 1),
    math.max(0, (reference.column or 1) - 1),
  })
  return true
end

local function reference_under_cursor(state)
  if not valid_window(state) or vim.api.nvim_get_current_win() ~= state.win then
    return nil
  end
  local row, col = unpack(vim.api.nvim_win_get_cursor(state.win))
  local line = vim.api.nvim_buf_get_lines(state.buf, row - 1, row, false)[1] or ""
  return M.parse_reference(line, col, state.root)
end

local function open_result_or_reference(state)
  local target = result_target_under_cursor(state)
  if target then
    preview_state_target(state, target)
    return true
  end
  return open_reference(state, reference_under_cursor(state))
end

local function attach_mappings(state)
  local transcript_buf = state.buf
  local input_buf = state.input_buf
  local function map(buf, mode, lhs, rhs, desc)
    local options = type(desc) == "table" and vim.deepcopy(desc) or { desc = desc }
    options.buffer = buf
    options.silent = true
    vim.keymap.set(mode, lhs, rhs, options)
  end

  local function focus_input()
    ensure_window(state)
    if valid_input_window(state) then
      vim.api.nvim_set_current_win(state.input_win)
      vim.api.nvim_win_set_cursor(state.input_win, state.input_cursor or { 1, #INPUT_PREFIX })
      clamp_input_cursor(state)
      vim.cmd("startinsert")
    end
  end

  map(transcript_buf, "n", "q", function() hide_panel(state) end, "Hide Graphify")
  map(input_buf, "n", "q", function() hide_panel(state) end, "Hide Graphify")
  map(transcript_buf, "n", "<Esc>", function() hide_panel(state) end, "Hide Graphify")
  map(input_buf, "n", "<Esc>", function() hide_panel(state) end, "Hide Graphify")
  local unfocus = function()
    if vim.fn.mode():sub(1, 1) == "i" then vim.cmd("stopinsert") end
    local previous = state.previous_win
    if previous and vim.api.nvim_win_is_valid(previous) then
      vim.api.nvim_set_current_win(previous)
    end
  end
  map(transcript_buf, { "n", "i" }, config.unfocus_key or "<C-]>", unfocus, "Return to previous window")
  map(input_buf, { "n", "i" }, config.unfocus_key or "<C-]>", unfocus, "Return to previous window")
  map(transcript_buf, "n", "<CR>", function() open_result_or_reference(state) end, "Preview result or open source location")
  map(transcript_buf, "n", "gf", function() open_reference(state, reference_under_cursor(state)) end, "Open source location")
  map(transcript_buf, "n", "K", function()
    local target = result_target_under_cursor(state)
    if target and target.kind == "node" then
      M.submit(state, ":explain " .. target.label)
    else
      notify("No Graphify node under the cursor.", vim.log.levels.INFO)
    end
  end, "Explain Graphify node")
  local function open_mouse_reference()
    local mouse = vim.fn.getmousepos()
    if mouse.line > 0 and valid_window(state) then
      local position = vim.api.nvim_win_get_position(state.win)
      local row = mouse.line - position[1]
      local column = mouse.column - position[2]
      if row < 1 or column < 1 then
        return
      end
      vim.cmd("stopinsert")
      vim.api.nvim_win_set_cursor(state.win, { row, column - 1 })
      open_result_or_reference(state)
    end
  end
  map(transcript_buf, "n", "<LeftMouse>", open_mouse_reference, "Open source location")
  map(transcript_buf, "i", "<LeftMouse>", open_mouse_reference, "Open source location")

  for _, lhs in ipairs({ "i", "a", "o", "I", "A", "O", "R", "c", "C", "s", "S" }) do
    map(transcript_buf, "n", lhs, focus_input, "Focus Graphify input")
  end
  local submit_input = function()
    local input = input_text(state)
    vim.schedule(function()
      if valid_input_buffer(state) then M.submit(state, input) end
    end)
  end
  map(input_buf, "i", config.submit_key or "<CR>", submit_input, "Submit Graphify request")
  map(input_buf, "i", config.newline_key or "<S-CR>", "<C-g>u<CR>", "Insert Graphify newline")
  map(input_buf, "i", "<C-c>", function()
    cancel_request(state)
  end, "Cancel Graphify request")
  for _, lhs in ipairs({ "i", "a", "o", "I", "A", "O" }) do
    map(input_buf, "n", lhs, focus_input, "Focus Graphify input")
  end
  map(input_buf, "i", "<BS>", function()
    local cursor = vim.api.nvim_win_get_cursor(state.input_win)
    if cursor[1] == 1 and cursor[2] <= #INPUT_PREFIX then return "" end
    return "<BS>"
  end, { expr = true, desc = "Edit Graphify input" })
  local function history_move(direction)
    if #state.history == 0 or not valid_input_window(state) then return false end
    local row = vim.api.nvim_win_get_cursor(state.input_win)[1]
    local count = #input_lines(state)
    if direction < 0 and row ~= 1 then return false end
    if direction > 0 and row ~= count then return false end
    if direction < 0 then
      state.history_index = math.max(1, (state.history_index == 0 and #state.history + 1 or state.history_index) - 1)
      set_input_text(state, state.history[state.history_index])
      return true
    end
    state.history_index = math.min(#state.history + 1, (state.history_index == 0 and #state.history or state.history_index) + 1)
    set_input_text(state, state.history_index <= #state.history and state.history[state.history_index] or "")
    return true
  end
  map(input_buf, "i", "<Up>", function()
    if not history_move(-1) then return "<Up>" end
    return ""
  end, { expr = true, desc = "Previous Graphify request" })
  map(input_buf, "i", "<Down>", function()
    if not history_move(1) then return "<Down>" end
    return ""
  end, { expr = true, desc = "Next Graphify request" })
  if not state.mappings_attached then
    vim.api.nvim_create_autocmd({ "InsertEnter", "ModeChanged", "BufEnter" }, {
      buffer = transcript_buf,
      callback = function()
        if vim.api.nvim_get_current_buf() == transcript_buf and vim.fn.mode():sub(1, 1) == "i" then
          vim.schedule(focus_input)
        end
      end,
    })
    vim.api.nvim_create_autocmd("CursorMoved", {
      buffer = input_buf,
      callback = function()
        if valid_input_window(state) and vim.api.nvim_get_current_win() == state.input_win then
          clamp_input_cursor(state)
        end
      end,
    })
    vim.api.nvim_create_autocmd({ "CursorMovedI", "InsertEnter" }, {
      buffer = input_buf,
      callback = function()
        clamp_input_cursor(state)
      end,
    })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      buffer = input_buf,
      callback = function()
        if vim.b[input_buf].graphify_input_placeholder
          and vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)[1] ~= input_placeholder_line() then
          if not state.input_activation_scheduled then
            state.input_activation_scheduled = true
            vim.schedule(function()
              state.input_activation_scheduled = false
              if valid_input_buffer(state)
                and vim.b[input_buf].graphify_input_placeholder
                and vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)[1] ~= input_placeholder_line() then
                activate_input(state)
              end
            end)
          end
        end
        style_input_buffer(state)
      end,
    })
    state.lifecycle_augroup = vim.api.nvim_create_augroup("graphify_group_" .. state.buf, { clear = true })
    vim.api.nvim_create_autocmd("WinClosed", {
      group = state.lifecycle_augroup,
      pattern = "*",
      callback = function(event)
        local closed = tonumber(event.match)
        local transcript_win = state.transcript_win or state.win
        if state.closing or state.destroying or (closed ~= transcript_win and closed ~= state.input_win) then return end
        vim.schedule(function()
          if not state.closing and not state.destroying then hide_panel(state) end
        end)
      end,
    })
    for _, bufnr in ipairs({ transcript_buf, input_buf }) do
      vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        group = state.lifecycle_augroup,
        buffer = bufnr,
        callback = function()
          if state.closing or state.destroying then return end
          vim.schedule(function()
            if not state.destroying then destroy_group(state) end
          end)
        end,
      })
    end
    state.mappings_attached = true
  end
end

local function configure_transcript_buffer(state)
  if valid_buffer(state) then return end
  state.buf = vim.api.nvim_create_buf(false, true)
  state.transcript_buf = state.buf
  vim.bo[state.buf].bufhidden = "hide"
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].filetype = "graphify"
  vim.bo[state.buf].swapfile = false
  vim.bo[state.buf].modifiable = false
  vim.bo[state.buf].readonly = true
  vim.api.nvim_buf_set_name(state.buf, "Graphify: " .. state.root)
  render(state, {
    "[Graphify] " .. state.root,
    "Graphify commands: :query text | :path source -> target | :explain node",
    "",
  })
  sync_buffer_metadata(state)
end

local function configure_input_buffer(state)
  if valid_input_buffer(state) then return end
  state.input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.input_buf].bufhidden = "hide"
  vim.bo[state.input_buf].buftype = "nofile"
  vim.bo[state.input_buf].filetype = "graphify_input"
  vim.bo[state.input_buf].swapfile = false
  vim.bo[state.input_buf].modifiable = true
  vim.bo[state.input_buf].readonly = false
  vim.api.nvim_buf_set_name(state.input_buf, "Graphify input: " .. state.root)
  set_input_placeholder(state)
  sync_buffer_metadata(state)
end

local function configure_transcript_window(state)
  vim.wo[state.win].wrap = true
  vim.wo[state.win].cursorline = true
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"
  vim.wo[state.win].winbar = "%#Title# Graphify Results %#Normal#"
  vim.wo[state.win].winfixbuf = true
end

local function configure_input_window(state)
  vim.wo[state.input_win].wrap = true
  vim.wo[state.input_win].cursorline = true
  vim.wo[state.input_win].number = false
  vim.wo[state.input_win].relativenumber = false
  vim.wo[state.input_win].signcolumn = "no"
  vim.wo[state.input_win].winbar = "%#GraphifyInputTitle# Graphify Input %#Normal#"
  local context = vim.fn.fnamemodify(state.root, ":~"):gsub("%%", "%%%%")
  vim.wo[state.input_win].statusline = "%#GraphifyInputContext#  Graphify · " .. context .. "%*"
  vim.wo[state.input_win].winfixbuf = true
  vim.wo[state.input_win].winhighlight = "Normal:GraphifyInputNormal,NormalNC:GraphifyInputNormalNC,WinBar:GraphifyInputTitle"
end

local function show_input_window(state)
  if state.input_panel and not state.input_panel:valid() then
    state.input_panel.opts.win = state.win
    state.input_panel:show()
    state.input_win = state.input_panel.win
  elseif not valid_input_window(state) then
    if state.win then
      vim.api.nvim_win_call(state.win, function()
        vim.cmd("botright split")
      end)
      state.input_win = vim.api.nvim_get_current_win()
      vim.wo[state.input_win].winfixbuf = false
      vim.api.nvim_win_set_buf(state.input_win, state.input_buf)
      vim.api.nvim_win_set_height(state.input_win, config.window.input_height or 3)
      state.win = window_for_buffer(state.buf) or state.win
      state.transcript_win = state.win
    end
  end
  if valid_input_window(state) then
    configure_input_window(state)
  end
end

ensure_window = function(state)
  configure_transcript_buffer(state)
  configure_input_buffer(state)
  if panel_is_visible(state) then
    state.hidden = false
    restore_transcript_cursor(state)
    vim.api.nvim_set_current_win(state.input_win)
    if state.input_cursor then vim.api.nvim_win_set_cursor(state.input_win, state.input_cursor) end
    vim.cmd("startinsert")
    return
  end
  if state.panel and not state.panel:valid() then
    state.previous_win = vim.api.nvim_get_current_win()
    state.panel:show()
    state.win = state.panel.win
    state.transcript_win = state.win
    state.hidden = false
    configure_transcript_window(state)
    show_input_window(state)
    state.win = window_for_buffer(state.buf) or state.win
    state.transcript_win = state.win
    restore_transcript_cursor(state)
    if not state.mappings_attached then attach_mappings(state) end
    vim.api.nvim_set_current_win(state.input_win)
    if state.input_cursor then vim.api.nvim_win_set_cursor(state.input_win, state.input_cursor) end
    vim.cmd("startinsert")
    return
  end
  if not valid_buffer(state) then
    configure_transcript_buffer(state)
  end
  state.previous_win = vim.api.nvim_get_current_win()
  if config.window.layout ~= "vertical" then
    notify("Graphify only supports vertical split layout.", vim.log.levels.WARN)
  end
  local provider = config.window.provider
  if provider == "snacks" or provider == nil then
    local ok, snacks = pcall(require, "snacks")
    local win_factory = ok and snacks and snacks.win
    if win_factory then
      local ok_panel, panel = pcall(win_factory, {
        buf = state.buf,
        position = config.window.side == "left" and "left" or "right",
        width = config.window.width,
        height = 0,
        enter = false,
        minimal = false,
        fixbuf = true,
        wo = {
          wrap = true,
          cursorline = true,
          number = false,
          relativenumber = false,
          signcolumn = "no",
          winbar = "%#Title# Graphify Results %#Normal#",
          winfixbuf = true,
        },
      })
      if ok_panel then
        state.panel = panel
        state.provider = "snacks"
        state.win = panel.win
        state.transcript_win = state.win
        state.hidden = false
        configure_transcript_window(state)
        local ok_input, input_panel = pcall(win_factory, {
          buf = state.input_buf,
          relative = "win",
          win = state.win,
          position = "bottom",
          height = config.window.input_height or 3,
          enter = true,
          minimal = false,
          fixbuf = true,
          wo = { wrap = true, cursorline = true, winfixbuf = true },
        })
        if ok_input then
          state.input_panel = input_panel
          state.input_win = input_panel.win
          configure_input_window(state)
        else
          state.input_panel = nil
          show_input_window(state)
        end
      else
        notify("Graphify Snacks panel failed; using native split.", vim.log.levels.WARN)
      end
    end
  end
  if not state.panel then
    if config.window.side == "left" then
      vim.cmd("topleft vsplit")
    else
      vim.cmd("botright vsplit")
    end
    state.provider = "native"
    state.win = vim.api.nvim_get_current_win()
    state.transcript_win = state.win
    state.hidden = false
    vim.api.nvim_win_set_buf(state.win, state.buf)
    local width = math.max(40, math.floor(vim.o.columns * config.window.width))
    vim.api.nvim_win_set_width(state.win, math.min(width, vim.o.columns - 4))
    vim.wo[state.win].wrap = true
    vim.wo[state.win].cursorline = true
    vim.wo[state.win].number = false
    vim.wo[state.win].relativenumber = false
    vim.wo[state.win].signcolumn = "no"
    configure_transcript_window(state)
    show_input_window(state)
    state.win = window_for_buffer(state.buf) or state.win
    state.transcript_win = state.win
    restore_transcript_cursor(state)
  else
    state.win = state.panel.win
    state.transcript_win = state.win
    state.hidden = false
    show_input_window(state)
    state.win = window_for_buffer(state.buf) or state.win
    state.transcript_win = state.win
    restore_transcript_cursor(state)
  end
  if not state.mappings_attached then
    attach_mappings(state)
  end
  vim.api.nvim_set_current_win(state.input_win)
  if state.input_cursor then vim.api.nvim_win_set_cursor(state.input_win, state.input_cursor) end
  vim.cmd("startinsert")
end

local function append_stream(state, label, data)
  if not data or data == "" then return end
  local lines = vim.split(data:gsub("\r\n", "\n"):gsub("\r", "\n"), "\n", { plain = true })
  if label == "stderr" then
    table.insert(lines, 1, "stderr:")
  end
  append_lines(state, lines)
end

local function run_request(state, request)
  local executable = vim.fn.exepath("graphify")
  if executable == "" then
    append_lines(state, { "[error] graphify executable was not found on PATH." })
    notify("Graphify executable was not found on PATH.", vim.log.levels.ERROR)
    return
  end
  local ok, argv = pcall(M.build_argv, request.kind, request.input, state.graph, request.options)
  if not ok then
    append_lines(state, { "[error] " .. argv })
    return
  end
  local timestamp = os.date("%H:%M:%S")
  append_lines(state, { "", "[Graphify request] " .. timestamp, "Command: " .. request.kind .. " " .. request.input })
  local request_metadata = {
    kind = request.kind,
    input = request.input,
    options = vim.deepcopy(request.options or {}),
    graph = state.graph,
    result_start = #transcript_lines(state),
    completed = false,
  }
  state.requests[#state.requests + 1] = request_metadata
  sync_buffer_metadata(state)
  state.running = true
  state.cancel_requested = false
  state.process = vim.system(argv, {
    text = true,
    stdout = function(_, data)
      vim.schedule(function() append_stream(state, "stdout", data) end)
    end,
    stderr = function(_, data)
      vim.schedule(function() append_stream(state, "stderr", data) end)
    end,
  }, function(result)
    vim.schedule(function()
      state.running = false
      state.process = nil
      request_metadata.completed = true
      request_metadata.result_end = #transcript_lines(state)
      local status = state.cancel_requested and "cancelled" or ("exit " .. tostring(result.code))
      append_lines(state, { "[" .. status .. "]" })
      scroll_transcript_to_end(state)
      if result.code ~= 0 and not state.cancel_requested then
        notify("Graphify " .. request.kind .. " failed with exit code " .. tostring(result.code), vim.log.levels.ERROR)
      end
    end)
  end)
end

local function run_maintenance(state, argv, title, command_text, success_message)
  local executable = vim.fn.exepath("graphify")
  if executable == "" then
    append_lines(state, { "[error] graphify executable was not found on PATH." })
    notify("Graphify executable was not found on PATH.", vim.log.levels.ERROR)
    return
  end
  if state.running then
    notify("A Graphify request is already running.", vim.log.levels.INFO)
    return
  end

  append_lines(state, {
    "",
    "[Graphify " .. title .. "] " .. os.date("%H:%M:%S"),
    "Command: " .. command_text,
  })
  state.running = true
  state.cancel_requested = false
  state.process = vim.system(argv, {
    text = true,
    stdout = function(_, data)
      vim.schedule(function() append_stream(state, "stdout", data) end)
    end,
    stderr = function(_, data)
      vim.schedule(function() append_stream(state, "stderr", data) end)
    end,
  }, function(result)
    vim.schedule(function()
      state.running = false
      state.process = nil
      local status = state.cancel_requested and "cancelled" or ("exit " .. tostring(result.code))
      append_lines(state, { "[" .. status .. "]" })
      scroll_transcript_to_end(state)
      if result.code == 0 and not state.cancel_requested then
        -- The command may replace graph.json while this state is alive. The
        -- next preview/query reloads it through its existing stat fingerprint.
        notify(success_message, vim.log.levels.INFO)
      elseif not state.cancel_requested then
        notify("Graphify " .. title .. " failed with exit code " .. tostring(result.code), vim.log.levels.ERROR)
      end
    end)
  end)
end

local function run_update(state)
  local argv = M.build_update_argv(state.root, config.update or {})
  run_maintenance(state, argv, "update", "graphify update " .. state.root, "Graphify graph updated.")
end

local function run_init(state)
  local argv = M.build_init_argv(state.root, config.init or {})
  run_maintenance(state, argv, "initialization", "graphify extract " .. state.root, "Graphify project initialized.")
end

function M.submit(state, input, options)
  local request = M.parse_input(input)
  if not request then return end
  request.options = options or {}
  if request.kind == "query" then
    local query = request.input
    local dfs = query:match("%s%-%-dfs%s") ~= nil or query:match("^%-%-dfs%s") ~= nil or query:match("%s%-%-dfs$") ~= nil or query:match("^%-%-dfs$") ~= nil
    local budget = query:match("%-%-budget%s+(%d+)")
    request.input = query:gsub("%s%-%-dfs%s", " "):gsub("%s%-%-dfs$", ""):gsub("^%-%-dfs%s*", ""):gsub("%s%-%-budget%s+%d+", " ")
    request.options = vim.tbl_extend("force", request.options, { dfs = dfs, budget = budget })
  end
  if request.kind == "path" and not request.input:find("%-%>") then
    append_lines(state, { "[error] path requests must use SOURCE -> TARGET" })
    return
  end
  state.history[#state.history + 1] = input
  state.history_index = #state.history + 1
  clear_input(state)
  run_request(state, request)
  if valid_input_window(state) then
    vim.api.nvim_set_current_win(state.input_win)
    vim.api.nvim_win_set_cursor(state.input_win, { 1, 0 })
    vim.cmd("startinsert")
  end
end

function M.query_selection()
  local selection = M.extract_selection(0, vim.fn.getpos("'<"), vim.fn.getpos("'>"), vim.fn.visualmode())
  if not selection then
    notify("Select a variable, symbol, or phrase before sending it to Graphify.", vim.log.levels.INFO)
    return
  end
  local state = current_state()
  if not state then return end
  ensure_window(state)
  M.submit(state, selection)
end

function M.open()
  local state = current_state()
  if not state then return end
  if panel_is_visible(state) and valid_window(state) then
    if vim.api.nvim_get_current_win() == state.win or vim.api.nvim_get_current_win() == state.input_win then
      hide_panel(state)
    else
      state.previous_win = vim.api.nvim_get_current_win()
      vim.api.nvim_set_current_win(state.input_win)
      vim.cmd("startinsert")
    end
    return
  end
  ensure_window(state)
end

function M.update()
  local state = current_state()
  if not state then return end
  ensure_window(state)
  run_update(state)
end

function M.initialize()
  local root = M.find_init_root(vim.api.nvim_buf_get_name(0), vim.uv.cwd() or vim.fn.getcwd())
  if not root then
    notify("Could not determine a project root for Graphify initialization.", vim.log.levels.WARN)
    return
  end
  local graph = vim.fs.joinpath(root, GRAPH_DIR, GRAPH_FILE)
  if vim.fn.filereadable(graph) == 1 then
    notify("Graphify is already initialized here; use :GraphifyUpdate instead.", vim.log.levels.INFO)
    return
  end

  vim.ui.select({ "Initialize Graphify", "Cancel" }, {
    prompt = "Initialize Graphify for " .. root .. "?",
  }, function(choice)
    if choice ~= "Initialize Graphify" then return end
    local state = states[root]
    if not state then
      state = {
        root = root,
        graph = normalize(graph),
        history = {},
        history_index = 0,
        references = {},
        requests = {},
        transcript_cursor = { 1, 0 },
        hidden = true,
        closing = false,
        destroying = false,
      }
      states[root] = state
    end
    ensure_window(state)
    run_init(state)
  end)
end

function M.preview()
  local project = current_state()
  if project then
    preview_html(project)
  end
end

function M.preview_node(label, community)
  local project = current_state()
  label = vim.trim(label or "")
  if not project or label == "" then
    if label == "" then notify("GraphifyPreviewNode requires a node label.", vim.log.levels.WARN) end
    return
  end
  preview_project_target(project, { kind = "node", label = label, community = community })
end

function M.preview_path(input)
  local project = current_state()
  local source, target = (input or ""):match("^%s*(.-)%s*%-%>%s*(.-)%s*$")
  if not project or not source or vim.trim(source) == "" or vim.trim(target) == "" then
    if project then notify("GraphifyPreviewPath requires SOURCE -> TARGET.", vim.log.levels.WARN) end
    return
  end
  preview_project_target(project, { kind = "path", source = vim.trim(source), target = vim.trim(target) })
end

function M.preview_result()
  local state = current_state()
  if state and valid_buffer(state) then preview_result(state) end
end

local function command_input(opts)
  return vim.trim(opts.args or "")
end

local function command_request(kind, opts)
  local state = current_state()
  if not state then return end
  ensure_window(state)
  local input = command_input(opts)
  if input == "" then return end
  if kind == "query" then
    local dfs = input:match("%s%-%-dfs%s") ~= nil or input:match("^%-%-dfs%s") ~= nil
    local budget = input:match("%-%-budget%s+(%d+)")
    input = input:gsub("%s%-%-dfs%s", " "):gsub("^%-%-dfs%s*", ""):gsub("%s%-%-budget%s+%d+", " ")
    M.submit(state, input, { dfs = dfs, budget = budget })
  else
    M.submit(state, ":" .. kind .. " " .. input)
  end
end

local function command_preview_node(opts)
  M.preview_node(vim.trim(opts.args or ""))
end

local function command_preview_path(opts)
  M.preview_path(vim.trim(opts.args or ""))
end

local function register_command(name, callback, description)
  if type(name) ~= "string" or name == "" then return end
  local commands = vim.api.nvim_get_commands({ builtin = false })
  if commands[name] and not config.allow_override then return end
  pcall(vim.api.nvim_del_user_command, name)
  vim.api.nvim_create_user_command(name, callback, { nargs = "*", desc = description })
end

function M.setup(opts)
  opts = opts or {}
  config = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), opts)
  if setup_done then return M end
  setup_done = true
  set_hl()
  register_command(config.commands.open, M.open, "Open Graphify")
  register_command(config.commands.query, function(command_opts) command_request("query", command_opts) end, "Run a Graphify query")
  register_command(config.commands.path, function(command_opts) command_request("path", command_opts) end, "Find a Graphify path")
  register_command(config.commands.explain, function(command_opts) command_request("explain", command_opts) end, "Explain a Graphify node")
  register_command(config.commands.update, M.update, "Update the Graphify output")
  register_command(config.commands.init, M.initialize, "Initialize Graphify for the project")
  register_command(config.commands.preview, M.preview, "Open the Graphify HTML preview")
  register_command(config.commands.preview_node, command_preview_node, "Preview a Graphify node")
  register_command(config.commands.preview_path, command_preview_path, "Preview a Graphify path")
  register_command(config.commands.preview_result, M.preview_result, "Preview the latest Graphify result")
  if config.keymap and (config.allow_override or vim.fn.maparg(config.keymap, "n") == "") then
    vim.keymap.set("n", config.keymap, M.open, { desc = "Open Graphify" })
  end
  if config.preview_keymap and (config.allow_override or vim.fn.maparg(config.preview_keymap, "n") == "") then
    vim.keymap.set("n", config.preview_keymap, M.preview, { desc = "Preview Graphify graph" })
  end
  if config.update_keymap and (config.allow_override or vim.fn.maparg(config.update_keymap, "n") == "") then
    vim.keymap.set("n", config.update_keymap, M.update, { desc = "Update Graphify output" })
  end
  if config.init_keymap and (config.allow_override or vim.fn.maparg(config.init_keymap, "n") == "") then
    vim.keymap.set("n", config.init_keymap, M.initialize, { desc = "Initialize Graphify project" })
  end
  if config.selection_keymap and (config.allow_override or vim.fn.maparg(config.selection_keymap, "x") == "") then
    vim.keymap.set("x", config.selection_keymap, M.query_selection, { desc = "Send visual selection to Graphify" })
  end
  return M
end

return M
