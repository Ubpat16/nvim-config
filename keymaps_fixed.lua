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
          vim.notify("OpenAI error: " .. err, vim.log.levels.ERROR)
          return
        end

        -- Parse the response
        local lines = vim.split(vim.trim(message or ""), "\n", { plain = true })
        if #lines == 0 then
          vim.notify("OpenAI returned empty response", vim.log.levels.WARN)
          return
        end

        local pr_title = lines[1]
        local pr_body = table.concat(lines, "\n")

        -- Show preview/edit interface
        vim.schedule(function()
          local width = math.min(80, math.max(60, math.floor(vim.o.columns * 0.7)))
          local height = math.min(25, math.max(15, math.floor(vim.o.lines * 0.7)))
          local row = math.floor((vim.o.lines - height) / 2)
          local col = math.floor((vim.o.columns - width) / 2)
          
          local bufnr = vim.api.nvim_create_buf(false, true)
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
            "Press :wq to create the PR, or :q to cancel.",
            "",
            "-------- TITLE --------",
            pr_title,
            "",
            "----- DESCRIPTION ------",
            pr_body,
            "",
            "Tip: Edit above, then :wq to create or :q to cancel"
          }
          
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, preview_content)
          
          -- Add syntax highlighting
          vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
          vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
          vim.api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
          
          -- Set keymap for confirmation
          vim.api.nvim_buf_set_keymap(bufnr, "n", "<CR>", ":wq<CR>", { noremap = true, silent = true })
          vim.api.nvim_buf_set_keymap(bufnr, "n", "<ESC>", ":q!<CR>", { noremap = true, silent = true })
          vim.api.nvim_buf_set_keymap(bufnr, "n", "q", ":q!<CR>", { noremap = true, silent = true })
          
          -- Add autocommand to handle save (create PR) or quit (cancel)
          vim.api.nvim_create_autocmd("BufWriteCmd", {
            buffer = bufnr,
            callback = function()
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
              
              -- Close preview window
              vim.api.nvim_win_close(winid, true)
              
              vim.notify("Creating PR...", vim.log.levels.INFO)
              
              -- Create PR using gh CLI
              local pr_command = {
                "gh", "pr", "create",
                "--title", title,
                "--body", description,
                "--base", base_branch
              }
              
              vim.system(pr_command, { text = true }, function(pr_result)
                vim.schedule(function()
                  if pr_result.code == 0 then
                    vim.notify("PR created successfully!", vim.log.levels.INFO)
                    vim.notify(pr_result.stdout or "", vim.log.levels.INFO)
                  else
                    vim.notify("Failed to create PR: " .. (pr_result.stderr or "unknown error"), vim.log.levels.ERROR)
                  end
                end)
              end)
            end
          })
          
          -- Cancel on quit
          vim.api.nvim_create_autocmd("BufUnload", {
            buffer = bufnr,
            callback = function()
              -- Only notify if it wasn't saved (BufWriteCmd would have handled it)
              if vim.v.event.abort then
                vim.notify("PR creation cancelled", vim.log.levels.INFO)
              end
            end
          })
        end)
      end)

      if not ok_generate then
        vim.notify("Could not generate PR description with OpenAI", vim.log.levels.ERROR)
      end
    end)
  end)
end