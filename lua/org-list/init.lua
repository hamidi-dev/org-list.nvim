local M = {}

function M.config()
  M.setup()
end

local function get_indent_level(line)
  return #(line:match("^%s*") or "")
end

local function is_checkbox_line(line)
  return line:match("^%s*%- %[.%] ")
end

local function update_parent_checkbox(buf, current_line)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local current_indent = get_indent_level(lines[current_line + 1])

  -- Find parent by looking for the first line with less indentation
  local parent_line = current_line
  while parent_line >= 0 do
    parent_line = parent_line - 1
    if parent_line < 0 then break end

    local line = lines[parent_line + 1]
    if not is_checkbox_line(line) then goto continue end

    local parent_indent = get_indent_level(line)
    if parent_indent < current_indent then
      -- Found the parent, now check all its children
      local all_checked = true
      local any_checked = false
      local partial = false

      -- Look at all children of this parent
      local check_line = parent_line + 1
      while check_line < #lines do
        local check_text = lines[check_line + 1]
        local check_indent = get_indent_level(check_text)

        if check_indent <= parent_indent then break end
        if check_indent == current_indent and is_checkbox_line(check_text) then
          local mark = check_text:match("^%s*%- %[(.?)%]")
          if mark == "x" then
            any_checked = true
          elseif mark == "-" then
            partial = true
          else
            all_checked = false
          end
        end
        check_line = check_line + 1
      end

      -- Update parent's checkbox state
      local parent_text = lines[parent_line + 1]
      local new_mark = " "
      if all_checked then
        new_mark = "x"
      elseif any_checked or partial then
        new_mark = "-"
      end

      local new_line = parent_text:gsub("%[.%]", "[" .. new_mark .. "]")
      vim.api.nvim_buf_set_lines(buf, parent_line, parent_line + 1, false, { new_line })

      -- Recursively update grandparents
      update_parent_checkbox(buf, parent_line)
      break
    end
    ::continue::
  end
end

local function update_children_checkboxes(buf, line_num, indent_level, new_mark)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local current_line = line_num + 1

  while current_line < #lines do
    local check_text = lines[current_line + 1]
    local check_indent = get_indent_level(check_text)

    -- Stop if we reach a line with less or equal indentation
    if check_indent <= indent_level then break end

    -- Update child checkbox if it exists
    if is_checkbox_line(check_text) then
      local new_line = check_text:gsub("%[.%]", "[" .. new_mark .. "]")
      vim.api.nvim_buf_set_lines(buf, current_line, current_line + 1, false, { new_line })
    end

    current_line = current_line + 1
  end
end

local function toggle_checkbox()
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_get_current_line()
  local checkbox_pattern = "^(%s*)%- %[(.?)%] (.*)$"
  local indent, mark, content = line:match(checkbox_pattern)

  if indent and content then
    local new_mark = mark == " " and "x" or mark == "x" and " " or " "
    local new_line = string.format("%s- [%s] %s", indent, new_mark, content)
    local current_line = vim.fn.line(".") - 1

    vim.api.nvim_set_current_line(new_line)

    -- Update all children checkboxes to match parent's state
    update_children_checkboxes(buf, current_line, #indent, new_mark)

    -- Update parent checkboxes state
    update_parent_checkbox(buf, current_line)
  end
end

local function cycle_list_type()
  -- Reset the indent numbers for each new cycle
  indent_numbers = {}
  -- Get the current line and determine the range of the list
  local cursor_line = vim.fn.line(".") - 1
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- Find the start and end of the list
  local start_line, end_line = cursor_line, cursor_line

  -- Check if current line has content (not just whitespace)
  if lines[cursor_line + 1]:match("^%s*$") then
    return
  end

  local function is_org_heading(line)
    return line:match("^%s*%*+%s")
  end

  local function is_list_or_content(line)
    -- Skip org-mode metadata lines
    if line:match("^%s*DEADLINE:") or
        line:match("^%s*SCHEDULED:") or
        line:match("^%s*CLOSED:") or
        line:match("^%s*:%w+:$") or           -- Tags line
        line:match("^%s*%[#[A-Z]%]") or       -- Priority
        line:match("^%s*%[%d?%d?%d?%%%]") then -- Progress
      return false
    end

    -- Check if line is either a list item or non-empty content
    return line:match("^%s*[%-%d]+[%.%s%[%]]") or
        (not line:match("^%s*$") and
          not line:match("^%s*#") and
          not line:match("^%s*:"))
  end

  -- Find start of list
  while start_line >= 0 do
    local line = lines[start_line + 1]
    if is_org_heading(line) or not is_list_or_content(line) then
      break
    end
    start_line = start_line - 1
  end
  start_line = start_line + 1

  -- Find end of list
  while end_line < #lines - 1 do
    local next_line = lines[end_line + 2] -- Look ahead to next line
    local current_line = lines[end_line + 1]

    -- Stop if current line is not a list/content, or if next line is a heading
    if not is_list_or_content(current_line) or
        (next_line and is_org_heading(next_line)) then
      break
    end
    end_line = end_line + 1
  end

  -- Fetch the relevant lines
  local list_lines = vim.api.nvim_buf_get_lines(buf, start_line, end_line + 1, false)

  -- Define patterns to detect list types
  local patterns = {
    checkbox = "^%s*%- %[.%] ",
    numbered = "^%s*%d+%. ",
    bullet = "^%s*%- ",
    plain = "^%s*[^%-%d%[%]][^%s]" -- matches non-empty lines that don't start with list markers
  }

  -- Detect the current list type
  local current_type = nil
  for _, line in ipairs(list_lines) do
    if line:match(patterns.checkbox) then
      current_type = "checkbox"
      break
    elseif line:match(patterns.numbered) then
      current_type = "numbered"
      break
    elseif line:match(patterns.bullet) then
      current_type = "bullet"
      break
    elseif line:match(patterns.plain) then
      current_type = "plain"
      break
    end
  end

  -- Transformation functions
  local function to_numbered(line, prev_line)
    local indent = line:match("^(%s*)")
    local indent_level = #indent
    local content = line
        :gsub("^%s*%- %[.%]%s*", "")
        :gsub("^%s*%- ", "")
        :gsub("^%s*%d+%.%s*", "")

    -- Initialize numbers table for this indent level if needed
    if not indent_numbers[indent_level] then
      indent_numbers[indent_level] = 0
    end

    if prev_line then
      local prev_indent = #(prev_line:match("^%s*") or "")

      -- If we're at a new indentation level, reset the counter
      if prev_indent ~= indent_level then
        -- Only reset if we're going deeper
        if prev_indent < indent_level then
          indent_numbers[indent_level] = 0
        end
        -- If we're returning to a previous level, continue from last number
      end
    end

    -- Increment counter for this level
    indent_numbers[indent_level] = indent_numbers[indent_level] + 1

    return indent .. indent_numbers[indent_level] .. ". " .. content
  end

  local function to_checkbox(line)
    local indent = line:match("^(%s*)")
    local content = line
        :gsub("^%s*%d+%.%s*", "")
        :gsub("^%s*%- ", "")
    return indent .. "- [ ] " .. content
  end

  local function to_bullet(line)
    local indent = line:match("^(%s*)")
    local content = line
        :gsub("^%s*%d+%.%s*", "")
        :gsub("^%s*%- %[.%]%s*", "")
        :gsub("^%s*%-%s+", "")                             -- Remove existing bullet and extra spaces
    return indent .. "- " .. content:match("^%s*(.-)%s*$") -- Trim extra spaces
  end

  local function to_plain(line)
    local indent = line:match("^(%s*)")
    local content = line
        :gsub("^%s*%d+%.%s*", "")
        :gsub("^%s*%- %[.%]%s*", "")
        :gsub("^%s*%- ", "")
    return indent .. content
  end

  -- Transform lines based on the current type
  local new_lines = {}
  local indent_numbers = {} -- Track numbering for each indentation level

  for _, line in ipairs(list_lines) do
    if line:match("^%s*$") then
      -- Preserve empty lines
      table.insert(new_lines, line)
    else
      local indent_level = #(line:match("^%s*") or "")

      if current_type == "bullet" then
        local prev_line = new_lines[#new_lines]
        table.insert(new_lines, to_numbered(line, prev_line))
      elseif current_type == "plain" then
        table.insert(new_lines, to_bullet(line))
      elseif current_type == "numbered" then
        table.insert(new_lines, to_checkbox(line))
      elseif current_type == "checkbox" then
        table.insert(new_lines, to_plain(line))
      else
        -- Default to bullet list if no type is detected
        table.insert(new_lines, to_bullet(line))
      end
    end
  end

  -- Replace the lines in the buffer
  vim.api.nvim_buf_set_lines(buf, start_line, end_line + 1, false, new_lines)
end

function M.setup(opts)
  opts = opts or {}
  local default_opts = {
    mapping = {
      key = '<leader>lt',
      desc = "Cycle through list types for the current list"
    },
    checkbox_toggle = {
      enabled = true,
      key = '<C-Space>',
      desc = "Toggle checkbox state",
      filetypes = { "org", "markdown" } -- default allowed filetypes
    }
  }

  -- Merge user options with defaults
  opts = vim.tbl_deep_extend("force", default_opts, opts or {})

  -- Create the Plug mapping
  vim.keymap.set('n', '<Plug>CycleListType', function()
    cycle_list_type()
    -- Call repeat#set after making changes
    vim.cmd([[silent! call repeat#set("\<Plug>CycleListType", v:count)]])
  end, { silent = true })

  -- Get the mapping configuration
  local mapping = opts.mapping or default_opts.mapping
  local key = type(mapping) == "table" and mapping.key or default_opts.mapping.key
  local desc = type(mapping) == "table" and mapping.desc or default_opts.mapping.desc

  -- Map the key to the Plug mapping
  vim.keymap.set('n', key, '<Plug>CycleListType',
    { silent = true, desc = desc })

  -- Create the Plug mapping for checkbox toggle
  vim.keymap.set('n', '<Plug>OrgListToggleCheckbox', function()
    local current_ft = vim.bo.filetype
    local allowed_fts = opts.checkbox_toggle.filetypes or {}

    -- Check if current filetype is in allowed filetypes
    local is_allowed = false
    for _, ft in ipairs(allowed_fts) do
      if current_ft == ft then
        is_allowed = true
        break
      end
    end

    if is_allowed then
      toggle_checkbox()
      -- Make the toggle repeatable
      vim.cmd([[silent! call repeat#set("\<Plug>OrgListToggleCheckbox", v:count)]])
    end
  end, { silent = true })

  -- Setup checkbox toggle if enabled
  if opts.checkbox_toggle and opts.checkbox_toggle.enabled then
    vim.keymap.set('n', opts.checkbox_toggle.key, '<Plug>OrgListToggleCheckbox', {
      silent = true,
      desc = opts.checkbox_toggle.desc
    })
  end
end

return M
