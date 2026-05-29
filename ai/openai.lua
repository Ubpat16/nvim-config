local M = {}

local config = {
  api_key = nil,
  model = "gpt-4o-mini",
  max_tokens = 150,
  temperature = 0.3,
  base_url = "https://api.openai.com/v1",
}

local function get_config_path()
  return vim.fn.stdpath("config") .. "/openai_config.json"
end

function M.setup(opts)
  opts = opts or {}
  for k, v in pairs(opts) do
    config[k] = v
  end

  -- Load API key from config file
  local config_path = get_config_path()
  local ok, data = pcall(vim.fn.readfile, config_path)
  if ok and data and #data > 0 then
    local json_ok, json_data = pcall(vim.fn.json_decode, table.concat(data, "\n"))
    if json_ok and json_data and json_data.api_key then
      config.api_key = json_data.api_key
    end
  end
end

function M.has_api_key()
  return config.api_key ~= nil and config.api_key ~= ""
end

function M.set_api_key(key)
  if not key or key == "" then
    return false, "API key cannot be empty"
  end

  -- Test the API key
  local test_ok, test_err = M.test_api_key(key)
  if not test_ok then
    return false, "Invalid API key: " .. test_err
  end

  -- Save the key
  config.api_key = key

  -- Persist to config file
  local config_path = get_config_path()
  local data = { api_key = key }
  local json_str = vim.json.encode(data)
  local ok = pcall(vim.fn.writefile, { json_str }, config_path)
  if not ok then
    return false, "Failed to save API key to config file"
  end

  return true
end

function M.test_api_key(key)
  if not key or key == "" then
    return false, "API key cannot be empty"
  end

  -- OpenAI keys start with sk-
  if not string.match(key, "^sk%-") then
    return false, "Invalid OpenAI API key format (should start with sk-)"
  end

  local result = vim.fn.system({
    "curl",
    "-s",
    "-H",
    "Authorization: Bearer " .. key,
    "-H",
    "Content-Type: application/json",
    config.base_url .. "/models",
  })

  if result and result:match("error") then
    return false, "API key validation failed"
  end

  return true
end

-- Generate commit message using OpenAI
function M.generate_commit_message(prompt, callback)
  if not M.has_api_key() then
    callback(nil, "OpenAI API key not configured. Run :OpenAISetKey first.")
    return false
  end

  local url = config.base_url .. "/chat/completions"
  local body = vim.json.encode({
    model = config.model,
    messages = {
      { role = "system", content = "You are a helpful assistant that generates commit messages." },
      { role = "user", content = prompt }
    },
    max_tokens = config.max_tokens,
    temperature = config.temperature
  })

  local command = {
    "curl",
    "-s",
    "-X",
    "POST",
    url,
    "-H",
    "Content-Type: application/json",
    "-H",
    "Authorization: Bearer " .. config.api_key,
    "--data-binary",
    body,
  }

  vim.system(command, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil, "OpenAI API request failed: " .. (result.stderr or "unknown error"))
        return
      end

      local ok, data = pcall(vim.json.decode, result.stdout)
      if not ok then
        callback(nil, "Failed to parse OpenAI response: " .. vim.trim(result.stdout or ""))
        return
      end

      if data.error then
        callback(nil, "OpenAI API error: " .. (data.error.message or "unknown error"))
        return
      end

      local message = data.choices[1].message.content
      callback(message)
    end)
  end)

  return true
end

-- Git commit generation with OpenAI
local function lc_generate_commit_message(root)
  vim.system({ "git", "-C", root, "diff", "--cached" }, { text = true }, function(diff_result)
    local diff = diff_result.code == 0 and vim.trim(diff_result.stdout or "") or ""

    if diff == "" then
      vim.notify("No staged changes to commit", vim.log.levels.WARN)
      return
    end

    local prompt = table.concat({
      "Generate a commit message based on these staged changes.",
      "",
      "Rules:",
      "- Use conventional commit format: type(scope): description",
      "- Keep it concise but descriptive",
      "- Max 72 characters for the subject line",
      "- Include body if changes are complex",
      "",
      "Changes:",
      diff
    }, "\n")

    vim.notify("Generating commit message with OpenAI...", vim.log.levels.INFO)

    local ok_generate = M.generate_commit_message(prompt, function(message, err)
      if err then
        vim.notify("OpenAI error: " .. err, vim.log.levels.ERROR)
        return
      end

      -- Show commit message in a buffer for editing
      vim.schedule(function()
        local commit_lines = vim.split(vim.trim(message or ""), "\n", { plain = true })
        local commit_msg = table.concat(commit_lines, "\n")

        -- Create temp buffer for commit message
        local bufnr = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { commit_msg })
        vim.api.nvim_buf_set_option(bufnr, "filetype", "gitcommit")

        -- Open in split
        vim.cmd("split")
        vim.api.nvim_win_set_buf(0, bufnr)

        vim.notify("Commit message generated. Edit and :wq to commit, or :q to cancel.", vim.log.levels.INFO)
      end)
    end)

    if not ok_generate then
      vim.notify("Could not generate commit message with OpenAI", vim.log.levels.ERROR)
    end
  end)
end

-- Commit message generation with OpenAI
function lc_create_git_commit(root)
  if not M.has_api_key() then
    vim.notify("OpenAI API key not configured. Run :OpenAISetKey first.", vim.log.levels.ERROR)
    return
  end

  lc_generate_commit_message(root)
end

-- Make functions globally accessible for keymaps
_G.lc_create_git_commit = lc_create_git_commit

-- Create commands
function M.create_commands()
  vim.api.nvim_create_user_command("OpenAISetKey", function(opts)
    local key = opts.args
    if not key or key == "" then
      vim.notify("Usage: OpenAISetKey <api-key>", vim.log.levels.ERROR)
      return
    end

    local ok, err = M.set_api_key(key)
    if ok then
      vim.notify("OpenAI API key saved and validated", vim.log.levels.INFO)
    else
      vim.notify("Failed to save API key: " .. err, vim.log.levels.ERROR)
    end
  end, { nargs = 1 })
end

-- Setup automatically
M.setup()

return M
