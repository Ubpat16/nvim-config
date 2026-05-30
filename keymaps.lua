-- Keymaps
local django = require("config.django")
local python_config = require("config.python")

local function lc_gitsigns_not_attached()
  vim.notify(
    "Gitsigns is not attached to this file. Open a file inside a Git repo, e.g. Backend, Web, or Mobile.",
    vim.log.levels.WARN
  )
end

vim.keymap.set("n", "<F9>", lc_gitsigns_not_attached, { desc = "Preview git hunk" })
vim.keymap.set("n", "<F10>", lc_gitsigns_not_attached, { desc = "Undo git hunk" })
vim.keymap.set("n", "<F11>", lc_gitsigns_not_attached, { desc = "Undo entire file" })
vim.keymap.set("n", "<F12>", lc_gitsigns_not_attached, { desc = "Next git hunk" })
vim.keymap.set("n", "<S-F12>", lc_gitsigns_not_attached, { desc = "Prev git hunk" })

local function lc_gitsigns_call(action, direction)
  local ok, gs = pcall(require, "gitsigns")
  if not ok or not vim.b.gitsigns_status_dict then
    lc_gitsigns_not_attached()
    return
  end

  if action == "nav_hunk" and gs.nav_hunk then
    gs.nav_hunk(direction)
    return
  end

  local fn = gs[action]
  if type(fn) ~= "function" then
    vim.notify("Gitsigns action is unavailable: " .. action, vim.log.levels.WARN)
    return
  end
  fn()
end

local function lc_first_url(text)
  return text and text:match("https?://[^%s]+") or nil
end

local function lc_open_url(url)
  if not url or url == "" then
    return false
  end

  if vim.ui and vim.ui.open then
    local ok = pcall(vim.ui.open, url)
    if ok then
      return true
    end
  end

  local command
  if vim.fn.has("macunix") == 1 then
    command = { "open", url }
  elseif vim.fn.has("win32") == 1 then
    command = { "cmd", "/c", "start", "", url }
  else
    command = { "xdg-open", url }
  end

  vim.system(command, { text = true }, function(result)
    if result.code ~= 0 then
      vim.schedule(function()
        vim.notify("Could not open PR in browser: " .. (result.stderr or "unknown error"), vim.log.levels.WARN)
      end)
    end
  end)

  return true
end

vim.api.nvim_create_user_command("GitHunkPreview", function()
  lc_gitsigns_call("preview_hunk")
end, {})
vim.api.nvim_create_user_command("GitHunkUndo", function()
  lc_gitsigns_call("reset_hunk")
end, {})
vim.api.nvim_create_user_command("GitFileUndo", function()
  lc_gitsigns_call("reset_buffer")
end, {})
vim.api.nvim_create_user_command("GitHunkNext", function()
  lc_gitsigns_call("nav_hunk", "next")
end, {})
vim.api.nvim_create_user_command("GitHunkPrev", function()
  lc_gitsigns_call("nav_hunk", "prev")
end, {})

vim.keymap.set("x", "<Tab>", ">gv", { desc = "Indent selection" })
vim.keymap.set("x", "<S-Tab>", "<gv", { desc = "Outdent selection" })

-- Move lines up/down
vim.keymap.set("n", "<A-j>", ":m .+1<CR>==", { desc = "Move line down", silent = true })
vim.keymap.set("n", "<A-k>", ":m .-2<CR>==", { desc = "Move line up", silent = true })
vim.keymap.set("i", "<A-j>", "<Esc>:m .+1<CR>==gi", { desc = "Move line down", silent = true })
vim.keymap.set("i", "<A-k>", "<Esc>:m .-2<CR>==gi", { desc = "Move line up", silent = true })
vim.keymap.set("x", "<A-j>", ":m '>+1<CR>gv=gv", { desc = "Move selection down", silent = true })
vim.keymap.set("x", "<A-k>", ":m '<-2<CR>gv=gv", { desc = "Move selection up", silent = true })



local lc_commit_message_cache = {}

-- Initialize OpenAI module
local ok_openai_init, openai_err = pcall(function()
  require("config.ai").setup_openai()
end)
if not ok_openai_init then
  vim.notify("Failed to initialize OpenAI: " .. tostring(openai_err), vim.log.levels.WARN)
end

local function lc_git_commit_message(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local last_content_line = 0

  for index, line in ipairs(lines) do
    if line:match("%S") then
      last_content_line = index
    end
  end

  if last_content_line == 0 then
    return nil
  end

  local message_lines = {}
  for index = 1, last_content_line do
    message_lines[index] = lines[index]
  end

  return table.concat(message_lines, "\n")
end

local function lc_git_run(root, args, callback)
  local command = { "git", "-C", root }
  vim.list_extend(command, args)

  vim.system(command, { text = true, env = python_config.global_python_env() }, function(result)
    result.lc_command = command
    vim.schedule(function()
      callback(result)
    end)
  end)
end

local function lc_shell_command(command)
  local escaped = {}
  for index, arg in ipairs(command) do
    escaped[index] = vim.fn.shellescape(arg)
  end
  return table.concat(escaped, " ")
end

local function lc_git_output(result)
  local output = vim.trim((result.stdout or "") .. "\n" .. (result.stderr or ""))
  if output == "" then
    return "git exited with code " .. result.code
  end
  return output
end

local function lc_append_text_lines(lines, text)
  text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  vim.list_extend(lines, vim.split(text, "\n", { plain = true }))
end

local function lc_show_command_failure(title, details)
  local lines = {
    title,
    string.rep("=", #title),
    "",
    "Press any key to close.",
    "",
  }

  if details.command then
    table.insert(lines, "Command:")
    lc_append_text_lines(lines, lc_shell_command(details.command))
    table.insert(lines, "")
  end

  if details.cwd then
    table.insert(lines, "Working directory:")
    lc_append_text_lines(lines, details.cwd)
    table.insert(lines, "")
  end

  if details.code ~= nil then
    vim.list_extend(lines, {
      "Exit code:",
      tostring(details.code),
      "",
    })
  end

  if details.message and vim.trim(details.message) ~= "" then
    table.insert(lines, "Message:")
    lc_append_text_lines(lines, vim.trim(details.message))
    table.insert(lines, "")
  end

  if details.stdout and vim.trim(details.stdout) ~= "" then
    table.insert(lines, "Stdout:")
    lc_append_text_lines(lines, vim.trim(details.stdout))
    table.insert(lines, "")
  end

  if details.stderr and vim.trim(details.stderr) ~= "" then
    table.insert(lines, "Stderr:")
    lc_append_text_lines(lines, vim.trim(details.stderr))
    table.insert(lines, "")
  end

  if #lines <= 6 then
    table.insert(lines, "No output was captured.")
  end

  local width = math.min(math.max(72, math.floor(vim.o.columns * 0.8)), vim.o.columns - 4)
  local height = math.min(math.max(14, math.floor(vim.o.lines * 0.65)), vim.o.lines - 4)
  local bufnr = vim.api.nvim_create_buf(false, true)
  local winid = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
  })

  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].filetype = "text"
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.wo[winid].wrap = false
  vim.wo[winid].cursorline = true

  local function close()
    if vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_close(winid, true)
    end
  end

  vim.schedule(function()
    vim.cmd("redraw")
    pcall(vim.fn.getcharstr)
    close()
  end)
end

local function lc_show_result_failure(title, result, fallback_message)
  lc_show_command_failure(title, {
    command = result.lc_command,
    code = result.code,
    stdout = result.stdout,
    stderr = result.stderr,
    message = fallback_message,
  })
end

local function lc_truncate_text(text, max_chars)
  if #text <= max_chars then
    return text
  end

  return text:sub(1, max_chars) .. "\n\n[diff truncated]"
end

local function lc_clean_commit_message(message)
  message = vim.trim(message or "")
  message = message:gsub("^```[%w_-]*\n", "")
  message = message:gsub("\n```$", "")
  message = vim.trim(message)

  local lines = vim.split(message, "\n", { plain = true })
  while #lines > 0 and vim.trim(lines[1]) == "" do
    table.remove(lines, 1)
  end
  while #lines > 0 and vim.trim(lines[#lines]) == "" do
    table.remove(lines, #lines)
  end

  return lines
end

local function lc_set_commit_prompt_title(winid, title)
  if vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_set_config(winid, { title = title })
  end
end

local function lc_generate_commit_message(bufnr, winid, root)
  if vim.b[bufnr].lc_git_commit_ai_running then
    vim.notify("Commit message generation already running", vim.log.levels.INFO)
    return
  end

  vim.b[bufnr].lc_git_commit_ai_running = true
  lc_set_commit_prompt_title(winid, " Commit message - asking OpenAI ")

  lc_git_run(root, { "status", "--short" }, function(status_result)
    if status_result.code ~= 0 then
      vim.b[bufnr].lc_git_commit_ai_running = false
      lc_set_commit_prompt_title(winid, " Commit message - OpenAI failed ")
      lc_show_result_failure("Git Status Failed", status_result)
      return
    end

    local status = vim.trim(status_result.stdout or "")
    if status == "" then
      vim.b[bufnr].lc_git_commit_ai_running = false
      lc_set_commit_prompt_title(winid, " Commit message ")
      vim.notify("No changes to summarize", vim.log.levels.INFO)
      return
    end

    lc_git_run(root, { "diff", "--no-ext-diff", "--no-color", "--stat", "HEAD", "--" }, function(stat_result)
      local stat = stat_result.code == 0 and vim.trim(stat_result.stdout or "") or ""

      lc_git_run(root, { "diff", "--no-ext-diff", "--no-color", "HEAD", "--" }, function(diff_result)
        local diff = diff_result.code == 0 and vim.trim(diff_result.stdout or "") or ""

        local ok_openai, openai = pcall(require, "config.ai.openai")
        if not ok_openai then
          vim.b[bufnr].lc_git_commit_ai_running = false
          lc_set_commit_prompt_title(winid, " Commit message - OpenAI unavailable ")
          lc_show_command_failure("OpenAI Module Unavailable", {
            message = tostring(openai),
          })
          return
        end

        if not openai.has_api_key() then
          vim.b[bufnr].lc_git_commit_ai_running = false
          lc_set_commit_prompt_title(winid, " Commit message - No API key ")
          vim.notify("No OpenAI API key configured. Use :OpenAISetKey to set one.", vim.log.levels.ERROR)
          return
        end

        local prompt = table.concat({
          "Generate a concise Git commit message for these repository changes.",
          "",
          "Rules:",
          "- Return only the commit message.",
          "- Use imperative mood.",
          "- Keep the subject line under 72 characters.",
          "- Add a short body only if it clarifies multiple meaningful changes.",
          "- Do not wrap the message in quotes or code fences.",
          "",
          "Git status:",
          status,
          "",
          "Diff stat:",
          stat ~= "" and stat or "(none)",
          "",
          "Diff:",
          diff ~= "" and lc_truncate_text(diff, 12000) or "(no tracked diff; summarize from status)",
        }, "\n")

        local ok_generate = openai.generate_commit_message(prompt, function(message, err)
          vim.b[bufnr].lc_git_commit_ai_running = false

          if not vim.api.nvim_buf_is_valid(bufnr) then
            return
          end

          if err then
            lc_set_commit_prompt_title(winid, " Commit message - OpenAI failed ")
            lc_show_command_failure("OpenAI Commit Message Failed", {
              message = err,
            })
            return
          end

          local lines = lc_clean_commit_message(message)
          if #lines == 0 then
            lc_set_commit_prompt_title(winid, " Commit message - OpenAI returned empty ")
            vim.notify("OpenAI returned an empty commit message", vim.log.levels.WARN)
            return
          end

          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
          lc_commit_message_cache[root] = table.concat(lines, "\n")
          lc_set_commit_prompt_title(winid, " Commit message - OpenAI draft ")

          if vim.api.nvim_win_is_valid(winid) then
            vim.api.nvim_set_current_win(winid)
            vim.api.nvim_win_set_cursor(winid, { 1, #lines[1] })
            vim.cmd("startinsert")
          end
        end)

        if not ok_generate then
          vim.b[bufnr].lc_git_commit_ai_running = false
          lc_set_commit_prompt_title(winid, " Commit message - OpenAI failed ")
          lc_show_command_failure("OpenAI Commit Message Failed", {
            message = "Could not start OpenAI commit message generation.",
          })
        end
      end)
    end)
  end)
end


local function lc_git_prompt_push(root)
  lc_git_run(root, { "branch", "--show-current" }, function(branch_result)
    vim.schedule(function()
      if branch_result.code ~= 0 then
        lc_show_result_failure("Git Branch Failed", branch_result)
        return
      end

      local branch = vim.trim(branch_result.stdout or "")
      if branch == "" then
        vim.notify("Cannot push from a detached HEAD", vim.log.levels.WARN)
        return
      end

      vim.ui.select({ "Yes", "No" }, {
        prompt = "Push to origin/" .. branch .. "?",
      }, function(choice)
        if choice ~= "Yes" then
          return
        end

        vim.notify("Pushing to origin/" .. branch .. "...", vim.log.levels.INFO)
        lc_git_run(root, { "push", "origin", branch }, function(push_result)
          vim.schedule(function()
            if push_result.code == 0 then
              vim.notify(lc_git_output(push_result), vim.log.levels.INFO)
              return
            end

            lc_show_result_failure("Git Push Failed", push_result)
          end)
        end)
      end)
    end)
  end)
end

local function lc_git_commit_all(bufnr, winid, root)
  local message = lc_git_commit_message(bufnr)
  if not message then
    vim.notify("Commit message is empty", vim.log.levels.WARN)
    return
  end

  if vim.b[bufnr].lc_git_commit_running then
    vim.notify("Commit already running", vim.log.levels.INFO)
    return
  end

  vim.b[bufnr].lc_git_commit_running = true
  lc_commit_message_cache[root] = message

  if vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_set_config(winid, { title = " Commit message - running git add . " })
  end

  lc_git_run(root, { "add", "." }, function(add_result)
    if add_result.code ~= 0 then
      vim.b[bufnr].lc_git_commit_running = false
      if vim.api.nvim_win_is_valid(winid) then
        vim.api.nvim_win_set_config(winid, { title = " Commit message - git add failed " })
      end
      lc_show_result_failure("Git Add Failed", add_result)
      return
    end

    local message_file = vim.fn.tempname()
    vim.fn.writefile(vim.split(message, "\n", { plain = true }), message_file)

    if vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_set_config(winid, { title = " Commit message - running git commit " })
    end

    lc_git_run(root, { "commit", "-F", message_file }, function(commit_result)
      vim.fn.delete(message_file)
      vim.b[bufnr].lc_git_commit_running = false

      if commit_result.code == 0 then
        lc_commit_message_cache[root] = nil
        if vim.api.nvim_win_is_valid(winid) then
          vim.api.nvim_win_close(winid, true)
        end
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_delete(bufnr, { force = true })
        end
        vim.notify(lc_git_output(commit_result), vim.log.levels.INFO)
        lc_git_prompt_push(root)
        return
      end

      if vim.api.nvim_win_is_valid(winid) then
        vim.api.nvim_win_set_config(winid, { title = " Commit failed - fix/review, then submit again " })
      end
      lc_show_result_failure("Git Commit Failed", commit_result)
    end)
  end)
end

local function lc_generate_pr_with_base(root, current_branch, base_branch, openai)
  -- Get commit log
  vim.system({ "git", "-C", root, "log", "--oneline", base_branch .. ".." .. current_branch }, { text = true }, function(log_result)
    local commits = log_result.code == 0 and vim.trim(log_result.stdout or "") or ""

    -- Get diff
    vim.system({ "git", "-C", root, "diff", "--no-ext-diff", "--no-color", base_branch .. ".." .. current_branch }, { text = true }, function(diff_result)
      local diff = diff_result.code == 0 and vim.trim(diff_result.stdout or "") or ""

      -- Prepare prompt for OpenAI
      local prompt = table.concat({
        "Generate a GitHub Pull Request title and description based on these changes.",
        "",
        "Rules:",
        "- Title should be concise and descriptive (max 72 characters)",
        "- Description should summarize the changes and explain the why, not just the what",
        "- Format: First line is the title, then blank line, then description",
        "- Include any important technical details",
        "- Keep it professional but clear",
        "",
        "Commits:",
        commits ~= "" and commits or "(No commits found)",
        "",
        "Diff:",
        diff ~= "" and diff or "(No diff found)"
      }, "\n")

      -- Show generating notification
      vim.notify("Generating PR description with OpenAI...", vim.log.levels.INFO)

      -- Generate PR description with OpenAI
      local ok_generate = openai.generate_commit_message(prompt, function(message, err)
        if err then
          lc_show_command_failure("OpenAI PR Description Failed", {
            message = err,
          })
          return
        end

        -- Parse the response
        local lines = vim.split(vim.trim(message or ""), "\n", { plain = true })
        if #lines == 0 then
          vim.notify("OpenAI returned empty response", vim.log.levels.WARN)
          return
        end

        local pr_title = vim.trim(lines[1] or "")
        local pr_body_lines = {}
        for i = 2, #lines do
          table.insert(pr_body_lines, lines[i])
        end
        while #pr_body_lines > 0 and pr_body_lines[1] == "" do
          table.remove(pr_body_lines, 1)
        end

        -- Show preview/edit interface
        vim.schedule(function()
          local width = math.min(80, math.max(60, math.floor(vim.o.columns * 0.7)))
          local height = math.min(25, math.max(15, math.floor(vim.o.lines * 0.7)))
          local row = math.floor((vim.o.lines - height) / 2)
          local col = math.floor((vim.o.columns - width) / 2)
          
          local bufnr = vim.api.nvim_create_buf(false, true)
          local preview_name = vim.fn.tempname() .. "-github-pr.md"
          vim.api.nvim_buf_set_name(bufnr, preview_name)
          local winid = vim.api.nvim_open_win(bufnr, true, {
            relative = "editor",
            width = width,
            height = height,
            row = row,
            col = col,
            style = "minimal",
            border = "rounded"
          })
          
          -- Set buffer content with instructions
          local preview_content = {
            "===== PR PREVIEW =====",
            "Review and edit the PR title and description below.",
            "Press Enter or Ctrl-S to create the PR, or q to cancel.",
            "",
            "-------- TITLE --------",
            pr_title,
            "",
            "----- DESCRIPTION ------",
          }
          vim.list_extend(preview_content, pr_body_lines)
          vim.list_extend(preview_content, {
            "",
            "Tip: Edit above, then press Enter or Ctrl-S to create the PR",
          })
          
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, preview_content)
          
          -- Add syntax highlighting
          vim.bo[bufnr].filetype = "markdown"
          vim.bo[bufnr].modifiable = true
          vim.bo[bufnr].buftype = "nofile"
          vim.bo[bufnr].bufhidden = "wipe"
          vim.bo[bufnr].swapfile = false
          vim.bo[bufnr].modified = false

          local function submit_pr()
            if vim.b[bufnr].lc_pr_create_running then
              vim.notify("PR creation already running", vim.log.levels.INFO)
              return
            end

            local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
              
            -- Find title (after "-------- TITLE --------" line)
            local title_line = nil
            for i, line in ipairs(all_lines) do
              if line == "-------- TITLE --------" then
                title_line = i
                break
              end
            end
              
            local title = ""
            local description_lines = {}
              
            if title_line then
              -- Get title (next line after title marker)
              if all_lines[title_line + 1] then
                title = vim.trim(all_lines[title_line + 1])
              end
                
              -- Find description start (after "----- DESCRIPTION ------")
              local desc_start = nil
              for i = title_line + 2, #all_lines do
                if all_lines[i] == "----- DESCRIPTION ------" then
                  desc_start = i
                  break
                end
              end
                
              if desc_start then
                -- Collect description lines after the marker (skip "Tip:" line)
                for i = desc_start + 1, #all_lines do
                  if not string.match(all_lines[i], "^Tip:") then
                    table.insert(description_lines, all_lines[i])
                  end
                end
              end
            end
              
            -- Clean up empty lines at end of description
            while #description_lines > 0 and description_lines[#description_lines] == "" do
              table.remove(description_lines)
            end
              
            local description = table.concat(description_lines, "\n")
              
            if title == "" then
              vim.notify("PR title cannot be empty", vim.log.levels.ERROR)
              return
            end

            vim.b[bufnr].lc_pr_create_running = true
              
            -- Close preview window
            if vim.api.nvim_win_is_valid(winid) then
              vim.api.nvim_win_close(winid, true)
            end
              
            vim.notify("Creating PR...", vim.log.levels.INFO)
              
            -- Create PR using gh CLI
            local pr_command = {
              "gh", "pr", "create",
              "--title", title,
              "--body", description,
              "--base", base_branch
            }
              
            vim.system(pr_command, { text = true, env = python_config.global_python_env() }, function(pr_result)
              pr_result.lc_command = pr_command
              vim.schedule(function()
                if pr_result.code == 0 then
                  vim.notify("PR created successfully!", vim.log.levels.INFO)
                  vim.notify(pr_result.stdout or "", vim.log.levels.INFO)
                  local pr_url = lc_first_url(pr_result.stdout or "")
                  if pr_url then
                    lc_open_url(pr_url)
                  else
                    vim.notify("Created PR, but gh did not return a URL to open.", vim.log.levels.WARN)
                  end
                else
                  lc_show_result_failure("GitHub PR Create Failed", pr_result)
                end
              end)
            end)
          end

          local function close_preview()
            if vim.api.nvim_win_is_valid(winid) then
              vim.api.nvim_win_close(winid, true)
            end
            vim.notify("PR creation cancelled", vim.log.levels.INFO)
          end

          vim.keymap.set("n", "<CR>", submit_pr, { buffer = bufnr, desc = "Create PR" })
          vim.keymap.set({ "n", "i" }, "<C-s>", function()
            vim.cmd("stopinsert")
            submit_pr()
          end, { buffer = bufnr, desc = "Create PR" })
          vim.keymap.set("n", "q", close_preview, { buffer = bufnr, desc = "Cancel PR creation" })
          vim.keymap.set("n", "<Esc>", close_preview, { buffer = bufnr, desc = "Cancel PR creation" })
        end)
      end)

      if not ok_generate then
        lc_show_command_failure("OpenAI PR Description Failed", {
          message = "Could not start OpenAI PR description generation.",
        })
      end
    end)
  end)
end

-- PR creation with OpenAI-generated title and description
local function lc_create_github_pr(root)
  -- Check if we're on a branch
  vim.system({ "git", "-C", root, "branch", "--show-current" }, { text = true }, function(branch_result)
    vim.schedule(function()
      if branch_result.code ~= 0 then
        vim.notify("Failed to get current branch: " .. (branch_result.stderr or "unknown error"), vim.log.levels.ERROR)
        return
      end

      local current_branch = vim.trim(branch_result.stdout or "")
      if current_branch == "" then
        vim.notify("Not on a branch (detached HEAD?)", vim.log.levels.WARN)
        return
      end

      -- Check if OpenAI is available
      local ok_openai, openai = pcall(require, "config.ai.openai")
      if not ok_openai then
        vim.notify("OpenAI module is unavailable", vim.log.levels.ERROR)
        return
      end

      if not openai.has_api_key() then
        vim.notify("No OpenAI API key configured. Use :OpenAISetKey to set one.", vim.log.levels.ERROR)
        return
      end

      -- Get diff between current branch and main/master
      vim.system({ "git", "-C", root, "log", "--oneline", "main.." .. current_branch }, { text = true }, function(log_result)
        if log_result.code ~= 0 then
          -- Try with master instead of main
          vim.system({ "git", "-C", root, "log", "--oneline", "master.." .. current_branch }, { text = true }, function(log_result2)
            if log_result2.code ~= 0 then
              vim.schedule(function()
                vim.notify("Could not find main or master branch to compare with", vim.log.levels.WARN)
                vim.ui.input({
                  prompt = "Base branch to compare with (e.g., main, master, develop): ",
                  default = "main"
                }, function(base_branch)
                  if base_branch and base_branch ~= "" then
                    lc_generate_pr_with_base(root, current_branch, base_branch, openai)
                  end
                end)
              end)
              return
            end
            lc_generate_pr_with_base(root, current_branch, "master", openai)
          end)
          return
        end
        lc_generate_pr_with_base(root, current_branch, "main", openai)
      end)
    end)
  end)
end


local function lc_open_git_commit_float()
  local file = vim.fn.expand("%:p")
  local start_path = file ~= "" and vim.fn.fnamemodify(file, ":h") or vim.fn.getcwd()

  vim.system({ "git", "-C", start_path, "rev-parse", "--show-toplevel" }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        vim.notify("Not inside a Git repo", vim.log.levels.WARN)
        return
      end

      local root = vim.trim(result.stdout or "")
      local width = math.min(72, math.max(48, math.floor(vim.o.columns * 0.55)))
      local height = math.min(10, math.max(6, math.floor(vim.o.lines * 0.22)))
      local row = math.floor((vim.o.lines - height) / 2)
      local col = math.floor((vim.o.columns - width) / 2)
      local bufnr = vim.api.nvim_create_buf(false, true)
      local winid = vim.api.nvim_open_win(bufnr, true, {
        relative = "editor",
        row = row,
        col = col,
        width = width,
        height = height,
        border = "rounded",
        title = " Commit message ",
        title_pos = "center",
        style = "minimal",
      })

      vim.bo[bufnr].bufhidden = "wipe"
      vim.bo[bufnr].filetype = "gitcommit"
      vim.wo[winid].wrap = true

      local cached = lc_commit_message_cache[root]
      if cached and cached ~= "" then
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(cached, "\n", { plain = true }))
      else
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "" })
        lc_generate_commit_message(bufnr, winid, root)
      end

      vim.keymap.set({ "n", "i" }, "<C-g>", function()
        vim.cmd("stopinsert")
        lc_generate_commit_message(bufnr, winid, root)
      end, { buffer = bufnr, desc = "Generate commit message with OpenAI" })
      vim.keymap.set({ "n", "i" }, "<C-s>", function()
        vim.cmd("stopinsert")
        lc_git_commit_all(bufnr, winid, root)
      end, { buffer = bufnr, desc = "Git add all and commit" })
      vim.keymap.set("n", "<CR>", function()
        lc_git_commit_all(bufnr, winid, root)
      end, { buffer = bufnr, desc = "Git add all and commit" })
      vim.keymap.set("n", "q", function()
        local message = lc_git_commit_message(bufnr)
        lc_commit_message_cache[root] = message
        if vim.api.nvim_win_is_valid(winid) then
          vim.api.nvim_win_close(winid, true)
        end
      end, { buffer = bufnr, desc = "Close commit prompt" })

      vim.cmd("startinsert")
    end)
  end)
end

vim.api.nvim_create_user_command("GitCommitAll", lc_open_git_commit_float, {})

vim.api.nvim_create_user_command("GitCreatePR", function()
  local file = vim.fn.expand("%:p")
  local start_path = file ~= "" and vim.fn.fnamemodify(file, ":h") or vim.fn.getcwd()
  
  vim.system({ "git", "-C", start_path, "rev-parse", "--show-toplevel" }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        vim.notify("Not inside a Git repo", vim.log.levels.WARN)
        return
      end
      
      local root = vim.trim(result.stdout or "")
      lc_create_github_pr(root)
    end)
  end)
end, { desc = "Create GitHub PR with OpenAI-generated description" })

vim.keymap.set("n", "<leader>e", ":NvimTreeToggle<CR>", { desc = "Explorer" })
vim.keymap.set("n", "<leader>aa", "<cmd>Codex<CR>", { desc = "AI terminal toggle" })
vim.keymap.set("n", "<leader>af", "<cmd>CodexFocus<CR>", { desc = "AI terminal focus" })
vim.keymap.set("v", "<leader>as", "<cmd>CodexSend<CR>", { desc = "AI send selection" })
vim.keymap.set("n", "<leader>ac", "<cmd>CopilotChatToggle<CR>", { desc = "AI chat toggle" })
vim.keymap.set("n", "<leader>ap", "<cmd>CopilotChatPrompts<CR>", { desc = "AI prompt palette" })
vim.keymap.set("n", "<leader>am", function()
  require("CopilotChat").select_model()
end, { desc = "AI model picker" })
vim.keymap.set("v", "<leader>ae", "<cmd>CopilotChatExplain<CR>", { desc = "AI explain selection" })
vim.keymap.set("v", "<leader>ar", "<cmd>CopilotChatReview<CR>", { desc = "AI review selection" })
vim.keymap.set("v", "<leader>ai", "<cmd>CopilotChatFix<CR>", { desc = "AI fix selection" })
vim.keymap.set("v", "<leader>ao", "<cmd>CopilotChatOptimize<CR>", { desc = "AI optimize selection" })
vim.keymap.set("v", "<leader>at", "<cmd>CopilotChatTests<CR>", { desc = "AI generate tests" })
vim.keymap.set("n", "<leader>ad", "<cmd>CopilotChatFixDiagnostic<CR>", { desc = "AI fix diagnostic" })
vim.keymap.set("n", "<leader>aR", "<cmd>CopilotChatReset<CR>", { desc = "AI reset chat" })

vim.keymap.set("i", "<M-Tab>", function()
  require("copilot.suggestion").accept()
end, { desc = "Copilot accept" })
vim.keymap.set("i", "<C-y>", function()
  require("copilot.suggestion").accept()
end, { desc = "Copilot accept fallback" })
vim.keymap.set("i", "<C-g>w", function()
  require("copilot.suggestion").accept_word()
end, { desc = "Copilot accept word" })
vim.keymap.set("i", "<C-g>l", function()
  require("copilot.suggestion").accept_line()
end, { desc = "Copilot accept line" })
vim.keymap.set("i", "<C-g>]", function()
  require("copilot.suggestion").next()
end, { desc = "Copilot next suggestion" })
vim.keymap.set("i", "<C-g>[", function()
  require("copilot.suggestion").prev()
end, { desc = "Copilot previous suggestion" })
vim.keymap.set("i", "<C-g>x", function()
  require("copilot.suggestion").dismiss()
end, { desc = "Copilot dismiss suggestion" })

vim.keymap.set("n", "<leader>ff", function()
  require("telescope.builtin").find_files()
end, { desc = "Find files", silent = true })
vim.keymap.set("n", "<leader>fg", function()
  require("telescope.builtin").live_grep()
end, { desc = "Live grep", silent = true })
vim.keymap.set("n", "<leader>fb", function()
  require("telescope.builtin").buffers()
end, { desc = "Buffers", silent = true })
vim.keymap.set("n", "<leader>fm", function()
  require("telescope.builtin").marks()
end, { desc = "Marks", silent = true })

local function lc_listed_buffers()
  return vim.tbl_filter(function(bufnr)
    return vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted
  end, vim.api.nvim_list_bufs())
end

local function lc_current_tab_listed_buffers()
  local tab = vim.api.nvim_get_current_tabpage()
  local wins = vim.api.nvim_tabpage_list_wins(tab)
  local seen = {}
  local buffers = {}

  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted and not seen[buf] then
        seen[buf] = true
        buffers[#buffers + 1] = buf
      end
    end
  end

  return buffers
end

local function lc_current_tab_normal_windows()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  return vim.tbl_filter(function(win)
    if not vim.api.nvim_win_is_valid(win) then
      return false
    end

    local buf = vim.api.nvim_win_get_buf(win)
    return vim.bo[buf].buftype == "" and not vim.wo[win].winfixbuf
  end, wins)
end

local function lc_focus_tab_buffer(bufnr)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
      vim.api.nvim_set_current_win(win)
      return
    end
  end

  vim.cmd("buffer " .. bufnr)
end

local function lc_tab_buffer_jump(step)
  local current = vim.api.nvim_get_current_buf()
  local buffers = lc_current_tab_listed_buffers()
  if #buffers <= 1 then
    return
  end

  local index = nil
  for i, bufnr in ipairs(buffers) do
    if bufnr == current then
      index = i
      break
    end
  end

  if not index then
    vim.cmd(step > 0 and "bnext" or "bprevious")
    return
  end

  local target = buffers[((index - 1 + step) % #buffers) + 1]
  if target and target ~= current then
    lc_focus_tab_buffer(target)
  end
end

local function lc_move_window_to_new_tab()
  local source_tab = vim.api.nvim_get_current_tabpage()
  local source_win = vim.api.nvim_get_current_win()

  vim.cmd("tab split")
  local target_tab = vim.api.nvim_get_current_tabpage()

  if vim.api.nvim_win_is_valid(source_win) then
    vim.api.nvim_set_current_tabpage(source_tab)
    vim.api.nvim_set_current_win(source_win)
    pcall(vim.cmd, "close")
  end

  if vim.api.nvim_tabpage_is_valid(target_tab) then
    vim.api.nvim_set_current_tabpage(target_tab)
  end
end

local function lc_smart_quit()
  local current_win = vim.api.nvim_get_current_win()
  local current = vim.api.nvim_get_current_buf()
  local listed = lc_listed_buffers()
  local current_name = vim.api.nvim_buf_get_name(current)
  local current_buftype = vim.bo[current].buftype

  if vim.api.nvim_win_is_valid(current_win) and vim.wo[current_win].winfixbuf then
    vim.cmd("close!")
    return
  end

  if current_buftype ~= "" then
    vim.cmd("close!")
    return
  end

  if #lc_current_tab_normal_windows() > 1 then
    pcall(vim.cmd, "confirm close")
    return
  end

  local function forget_current_file()
    if current_name == "" or vim.bo[current].buftype ~= "" then
      return
    end

    vim.b[current].lc_forget_project_file_on_close = true
    vim.cmd("silent! LastProjectFileForget " .. vim.fn.fnameescape(current_name))
  end

  if #listed > 1 then
    forget_current_file()
    vim.cmd("bprevious")
    if vim.api.nvim_get_current_buf() == current then
      vim.cmd("bnext")
    end
    local ok = pcall(vim.cmd, "confirm bdelete " .. current)
    if not ok and vim.api.nvim_buf_is_valid(current) then
      vim.b[current].lc_forget_project_file_on_close = false
    end
    return
  end

  forget_current_file()
  vim.cmd("confirm quit")
end

vim.api.nvim_create_user_command("SmartQuit", lc_smart_quit, {
  desc = "Close current buffer, or quit if it is the last buffer",
})

vim.keymap.set("c", "<CR>", function()
  if vim.fn.getcmdtype() == ":" then
    local command = vim.fn.getcmdline()
    if command == "q" or command == "quit" then
      return "<C-U>SmartQuit<CR>"
    end
  end
  return "<CR>"
end, { expr = true, desc = "Smart quit from command line" })

vim.keymap.set("n", "<leader>bd", lc_smart_quit, { desc = "Close buffer" })
vim.keymap.set("n", "<leader>bc", function()
  -- Get all listed buffers and their names BEFORE deleting them
  local buffer_names = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted then
      local buf_name = vim.api.nvim_buf_get_name(bufnr)
      if buf_name ~= "" then
        table.insert(buffer_names, buf_name)
      end
    end
  end
  
  -- Clear all listed buffers
  vim.cmd("bufdo bd")
  
  -- Clear file registry entries for buffers that were closed
  for _, buf_name in ipairs(buffer_names) do
    -- For buffers with file names, attempt to remove from last visited files
    -- This approach forces cleanup of file registry entries
    vim.cmd("silent! LastProjectFileForget " .. vim.fn.fnameescape(buf_name))
  end
  
  -- Ensure a clean state by clearing any remaining file registry entries
  vim.cmd("silent! LastProjectFileForget")
end, { desc = "Clear all buffers and file registry" })
vim.keymap.set("n", "<leader>bn", function()
  lc_tab_buffer_jump(1)
end, { desc = "Next buffer in tab" })
vim.keymap.set("n", "<leader>bp", function()
  lc_tab_buffer_jump(-1)
end, { desc = "Previous buffer in tab" })
vim.keymap.set("n", "]b", function()
  lc_tab_buffer_jump(1)
end, { desc = "Next buffer in tab" })
vim.keymap.set("n", "[b", function()
  lc_tab_buffer_jump(-1)
end, { desc = "Previous buffer in tab" })
vim.keymap.set("n", "<leader>tn", ":tabnext<CR>", { desc = "Next tab" })
vim.keymap.set("n", "<leader>tp", ":tabprevious<CR>", { desc = "Previous tab" })
vim.keymap.set("n", "<leader>to", ":tabnew<CR>", { desc = "New tab" })
vim.keymap.set("n", "<leader>tq", ":tabclose<CR>", { desc = "Close tab" })
vim.keymap.set("n", "<leader>tm", lc_move_window_to_new_tab, { desc = "Move window to new tab" })

vim.keymap.set("n", "<leader>fh", function()
  require("telescope.builtin").help_tags()
end, { desc = "Help tags", silent = true })
vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, { desc = "Rename symbol" })
vim.keymap.set("n", "<leader>gs", ":Git<CR>", { desc = "Git status" })
vim.keymap.set("n", "<leader>gb", ":GBlame<CR>", { desc = "Git blame" })
vim.keymap.set("n", "<leader>gc", lc_open_git_commit_float, { desc = "Git add all and commit" })
vim.keymap.set("n", "<leader>gl", ":Git log --graph --oneline<CR>", { desc = "Git log graph" })
vim.keymap.set("n", "<leader>gg", ":Git log --all --graph --decorate --oneline<CR>", { desc = "Git all branches graph" })

-- Create GitHub PR with OpenAI-generated description (preview/edit)
vim.keymap.set("n", "<leader>gp", function()
  local file = vim.fn.expand("%:p")
  local start_path = file ~= "" and vim.fn.fnamemodify(file, ":h") or vim.fn.getcwd()
  
  vim.system({ "git", "-C", start_path, "rev-parse", "--show-toplevel" }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        vim.notify("Not inside a Git repo", vim.log.levels.WARN)
        return
      end
      
      local root = vim.trim(result.stdout or "")
      lc_create_github_pr(root)
    end)
  end)
end, { desc = "Create GitHub PR with OpenAI (preview/edit)" })
vim.keymap.set("n", "<leader>qq", ":qa<CR>", { desc = "Quit all" })
vim.keymap.set("n", "<leader>w", ":w<CR>", { desc = "Save" })
vim.keymap.set("n", "<leader>nh", ":nohlsearch<CR>", { desc = "Clear search highlight" })

-- Duplicate lines/selection
vim.keymap.set("n", "<leader>dl", "yyp", { desc = "Duplicate line down" })
vim.keymap.set("n", "<leader>dL", "yyP", { desc = "Duplicate line up" })
vim.keymap.set("x", "<leader>ds", "y'>p", { desc = "Duplicate selection down" })
vim.keymap.set("x", "<leader>dS", "y'<P", { desc = "Duplicate selection up" })

-- Scratch buffer (temporary file)
local function lc_create_scratch_buffer()
  -- Create a new buffer
  local buf = vim.api.nvim_create_buf(true, false)
  
  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(buf, 'buflisted', false)
  
  -- Set buffer name
  vim.api.nvim_buf_set_name(buf, 'scratch://' .. os.date('%Y%m%d-%H%M%S') .. '.md')
  
  -- Create a new tab and set the buffer
  vim.cmd('tabnew')
  vim.api.nvim_set_current_buf(buf)
  
  -- Set filetype to markdown (optional, change as needed)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  
  -- Add a helpful header
  local lines = {
    '# Scratch Buffer',
    'Created: ' .. os.date('%Y-%m-%d %H:%M:%S'),
    '---',
    '',
    'This is a temporary scratch buffer.',
    '- Not saved to disk',
    '- Will disappear when closed',
    '- Use for notes, drafts, calculations',
    '',
    '---',
    '',
  }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  
  -- Move cursor to the end
  vim.api.nvim_win_set_cursor(0, { #lines, 0 })
  
  vim.notify('Scratch buffer created', vim.log.levels.INFO)
end

vim.keymap.set("n", "<leader>ns", lc_create_scratch_buffer, { desc = "New scratch buffer (tab)" })

-- Quick scratch buffers in splits
local function lc_create_horizontal_scratch()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(buf, 'buflisted', false)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  
  vim.cmd('split')
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_name(buf, 'scratch://temp.md')
  
  vim.notify('Horizontal scratch created', vim.log.levels.INFO)
end

local function lc_create_vertical_scratch()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(buf, 'buflisted', false)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  
  vim.cmd('vsplit')
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_name(buf, 'scratch://temp.md')
  
  vim.notify('Vertical scratch created', vim.log.levels.INFO)
end

vim.keymap.set("n", "<leader>nhs", lc_create_horizontal_scratch, { desc = "New horizontal scratch split" })
vim.keymap.set("n", "<leader>nvs", lc_create_vertical_scratch, { desc = "New vertical scratch split" })

vim.keymap.set("n", "<leader>yp", function()
  local path = vim.fn.expand("%:p")
  if path == "" then
    vim.notify("No file path to copy", vim.log.levels.WARN)
    return
  end

  vim.fn.setreg("+", path)
  vim.notify("Copied absolute path: " .. path)
end, { desc = "Copy absolute file path" })

vim.keymap.set("n", "<leader>yr", function()
  local path = vim.fn.expand("%")
  if path == "" then
    vim.notify("No file path to copy", vim.log.levels.WARN)
    return
  end

  vim.fn.setreg("+", path)
  vim.notify("Copied relative path: " .. path)
end, { desc = "Copy relative file path" })

vim.keymap.set("n", "<leader>tt", ":ToggleTerm<CR>", { desc = "Terminal" })
vim.keymap.set("n", "<leader>u", ":UndotreeToggle<CR>", { desc = "Undo history" })
vim.keymap.set("n", "<leader>pb", function()
  vim.cmd("Telescope find_files cwd=" .. vim.fn.getcwd() .. "/")
end, { desc = "Browse project files" })

-- DAP (<leader>D* avoids clash with Django.nvim <leader>d* / manage.py maps)
vim.keymap.set("n", "<leader>db", function()
  require("dap").toggle_breakpoint()
end, { desc = "DAP toggle breakpoint" })
vim.keymap.set("n", "<leader>Dc", function()
  require("dap").continue()
end, { desc = "DAP continue" })
vim.keymap.set("n", "<leader>Di", function()
  require("dap").step_into()
end, { desc = "DAP step into" })
vim.keymap.set("n", "<leader>Do", function()
  require("dap").step_over()
end, { desc = "DAP step over" })
vim.keymap.set("n", "<leader>DO", function()
  require("dap").step_out()
end, { desc = "DAP step out" })
vim.keymap.set("n", "<leader>Du", function()
  require("dapui").toggle()
end, { desc = "DAP UI toggle" })

-- Neotest (VSCode-like runner / summary)
vim.keymap.set("n", "<F5>", function()
  require("neotest").run.run()
end, { desc = "Pytest nearest" })
vim.keymap.set("n", "<F6>", function()
  require("neotest").run.run(vim.fn.expand("%"))
end, { desc = "Pytest this file" })
vim.keymap.set("n", "<F7>", function()
  require("neotest").summary.toggle()
end, { desc = "Pytest summary" })
vim.keymap.set("n", "<F8>", function()
  require("neotest").output.open({ enter = true, auto_close = false })
end, { desc = "Pytest output" })
vim.keymap.set("n", "<leader>Tn", function()
  require("neotest").run.run()
end, { desc = "Neotest nearest" })
vim.keymap.set("n", "<leader>Tf", function()
  require("neotest").run.run(vim.fn.expand("%"))
end, { desc = "Neotest this file" })
vim.keymap.set("n", "<leader>Ts", function()
  require("neotest").summary.toggle()
end, { desc = "Neotest summary" })
vim.keymap.set("n", "<leader>To", function()
  require("neotest").output.open({ enter = true, auto_close = false })
end, { desc = "Neotest output" })

local function lc_find_pytest_root(start_path)
  return vim.fs.find({ "pyproject.toml", "pytest.ini", ".git" }, { path = start_path, upward = true })[1]
end

local function lc_nearest_pytest_target(file)
  local cursor_line = vim.fn.line(".")
  local lines = vim.api.nvim_buf_get_lines(0, 0, cursor_line, false)
  local test_name = nil
  local test_indent = nil

  for index = #lines, 1, -1 do
    local line = lines[index]
    local indent, name = line:match("^(%s*)def%s+(test_[%w_]+)%s*%(")
    if name then
      test_name = name
      test_indent = #indent
      break
    end
  end

  if not test_name then
    for index = #lines, 1, -1 do
      local line = lines[index]
      local _, class_name = line:match("^(%s*)class%s+(Test[%w_]+)")
      if class_name then
        return file .. "::" .. class_name
      end
    end
    return file
  end

  for index = #lines, 1, -1 do
    local line = lines[index]
    local indent, class_name = line:match("^(%s*)class%s+(Test[%w_]+)")
    if class_name and #indent < test_indent then
      return file .. "::" .. class_name .. "::" .. test_name
    end
  end

  return file .. "::" .. test_name
end

local function lc_pytest_command(target)
  local file = vim.fn.expand("%:p")
  local start_path = file ~= "" and vim.fn.fnamemodify(file, ":h") or vim.fn.getcwd()
  local root_marker = lc_find_pytest_root(start_path)
  local root = root_marker and vim.fn.fnamemodify(root_marker, ":h") or vim.fn.getcwd()
  local env_file = django.find_env_file(root)
  local command = "cd " .. vim.fn.shellescape(root) .. " && uv run "

  if env_file then
    command = command .. "--env-file " .. vim.fn.shellescape(env_file) .. " "
  end

  command = command .. "pytest --reuse-db "
  if target == "nearest" then
    command = command .. vim.fn.shellescape(lc_nearest_pytest_target(file))
  elseif target == "file" then
    command = command .. vim.fn.shellescape(file)
  end

  return command
end

local function lc_run_pytest(target)
  local file = vim.fn.expand("%:p")
  if target ~= "suite" and file == "" then
    vim.notify("Save this test file before running pytest", vim.log.levels.WARN)
    return
  end

  if vim.bo.buftype == "" and vim.bo.modifiable and not vim.bo.readonly and vim.api.nvim_buf_get_name(0) ~= "" then
    vim.cmd("silent update")
  end

  django.run_in_shell(lc_pytest_command(target))
end

vim.keymap.set("n", "<leader>pt", function()
  lc_run_pytest("nearest")
end, { desc = "Pytest nearest via uv" })
vim.keymap.set("n", "<leader>pf", function()
  lc_run_pytest("file")
end, { desc = "Pytest file via uv" })
vim.keymap.set("n", "<leader>pa", function()
  lc_run_pytest("suite")
end, { desc = "Pytest suite via uv" })

-- Django.nvim
vim.keymap.set("n", "<leader>dc", function()
  django.run_manage("check")
end, { desc = "Django system check" })
vim.keymap.set("n", "dm", function()
  django.run_manage("makemigrations")
end, { desc = "Django makemigrations" })
vim.keymap.set("n", "dmm", function()
  django.run_manage("migrate")
end, { desc = "Django migrate" })
vim.keymap.set("n", "dx", function()
  django.prompt_manage()
end, { desc = "Django custom command" })
vim.keymap.set("n", "df", function()
  django.pick_script_and_run()
end, { desc = "Django run script in shell" })

vim.keymap.set("n", "<C-h>", "<C-w><C-h>", { desc = "Move to left window" })
vim.keymap.set("n", "<C-l>", "<C-w><C-l>", { desc = "Move to right window" })
vim.keymap.set("n", "<C-j>", "<C-w><C-j>", { desc = "Move to lower window" })
vim.keymap.set("n", "<C-k>", "<C-w><C-k>", { desc = "Move to upper window" })

vim.api.nvim_create_autocmd("FileType", {
  pattern = "http",
  group = vim.api.nvim_create_augroup("lc_rest_keymaps", { clear = true }),
  callback = function(event)
    local map = function(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, {
        buffer = event.buf,
        desc = desc,
        silent = true,
      })
    end

    map("<leader>rr", "<cmd>Rest run<CR>", "REST run request")
    map("<leader>rl", "<cmd>Rest last<CR>", "REST run last request")
    map("<leader>ro", "<cmd>Rest open<CR>", "REST open result")
    map("<leader>re", "<cmd>Rest env select<CR>", "REST select env file")
    map("<leader>rc", "<cmd>Rest cookies<CR>", "REST cookies")
    map("<leader>rg", "<cmd>Rest logs<CR>", "REST logs")
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "neotest-output", "neotest-attach" },
  group = vim.api.nvim_create_augroup("lc_neotest_output_keymaps", { clear = true }),
  callback = function(event)
    local map = function(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, {
        buffer = event.buf,
        desc = desc,
        silent = true,
      })
    end

    map("<CR>", "<cmd>close<CR>", "Close pytest output")
    map("q", "<cmd>close<CR>", "Close pytest output")
  end,
})

vim.keymap.set("n", "<leader>rp", function()
  local content = vim.fn.expand("%")

  if content == "" then
    vim.notify("Nothing to run", vim.log.levels.WARN)
    return
  end

  vim.cmd("!uv run python " .. vim.fn.shellescape(content))
end)

local function safe_cmd(cmd)
  return function()
    pcall(vim.cmd, cmd)
  end
end

vim.keymap.set("n", "]q", safe_cmd("cnext"), { desc = "Next quickfix item" })
vim.keymap.set("n", "[q", safe_cmd("cprevious"), { desc = "Previous quickfix item" })
