local highlighting = require("blink-fff.highlighting")

local M = {}

local FULL_READ_LIMIT = 64 * 1024
local INITIAL_WINDOW = 16 * 1024
local MAX_ATTEMPTS = 6

local function default_read(path)
  return vim.fn.readfile(path)
end

---@param line string
---@return string
local function clean_line(line)
  if line:sub(-1) == "\r" then
    return line:sub(1, -2)
  end
  return line
end

--- Select the context from a byte window around the match.
---
--- The chunk may start in the middle of a line; that first partial line is
--- dropped. When the chunk does not reach EOF, a trailing line without a
--- newline is also partial and dropped.
---@param chunk string
---@param chunk_start integer 0-based absolute offset of chunk[1]
---@param byte_offset integer 0-based absolute start of the match line
---@param match_line integer 1-based match line
---@param context_size integer
---@param at_eof boolean
---@return string[]|nil context
---@return integer|nil first_line
---@return boolean complete_before
---@return boolean complete_after
function M.context_from_chunk(
  chunk,
  chunk_start,
  byte_offset,
  match_line,
  context_size,
  at_eof
)
  if type(chunk) ~= "string" then
    return nil
  end
  if type(chunk_start) ~= "number" or type(byte_offset) ~= "number" then
    return nil
  end
  if type(match_line) ~= "number" or type(context_size) ~= "number" then
    return nil
  end

  local lines = {}
  local starts = {}
  local pos = 0

  while pos < #chunk do
    local newline = chunk:find("\n", pos + 1, true)
    if newline then
      lines[#lines + 1] = clean_line(chunk:sub(pos + 1, newline - 1))
      starts[#starts + 1] = chunk_start + pos
      pos = newline
    else
      if at_eof then
        lines[#lines + 1] = clean_line(chunk:sub(pos + 1))
        starts[#starts + 1] = chunk_start + pos
      end
      break
    end
  end

  -- A window that does not start at the file start begins mid-line.
  if chunk_start > 0 and #lines > 0 then
    table.remove(lines, 1)
    table.remove(starts, 1)
  end

  if #lines == 0 then
    return nil
  end

  local anchor
  for i, start in ipairs(starts) do
    if start == byte_offset then
      anchor = i
      break
    end
  end
  if not anchor then
    for i, start in ipairs(starts) do
      if start <= byte_offset then
        anchor = i
      else
        break
      end
    end
  end
  if not anchor then
    return nil
  end

  local before = math.min(context_size, anchor - 1)
  local after = math.min(context_size, #lines - anchor)

  local context = {}
  for i = anchor - before, anchor + after do
    context[#context + 1] = lines[i]
  end

  local first_line = match_line - before
  local complete_before = before >= context_size or first_line == 1
  local complete_after = after >= context_size or at_eof

  return context, first_line, complete_before, complete_after
end

--- Read only the byte window needed for the context around a match.
---@param path string
---@param match_line integer 1-based
---@param context_size integer
---@param byte_offset integer 0-based absolute start of the match line
---@param read_blob? fun(offset: integer, size: integer): string|nil, string|nil
---@param file_size? integer
---@return string[]|nil lines
---@return integer|nil first_line
---@return string|nil err
function M.read_context(
  path,
  match_line,
  context_size,
  byte_offset,
  read_blob,
  file_size
)
  if type(byte_offset) ~= "number" or byte_offset < 0 then
    return nil, nil, "no byte offset"
  end

  local size = file_size
  if type(size) ~= "number" then
    size = vim.fn.getfsize(path)
    if size < 0 then
      return nil, nil, "cannot stat " .. path
    end
  end
  if byte_offset > size then
    return nil, nil, "match offset outside file"
  end

  read_blob = read_blob
    or function(offset, count)
      return vim.fn.readblob(path, offset, count)
    end

  local window = INITIAL_WINDOW

  for _ = 1, MAX_ATTEMPTS do
    local from = math.max(0, byte_offset - window)
    local to = math.min(size, byte_offset + window)

    local ok, chunk, read_err = pcall(read_blob, from, to - from)
    if not ok then
      return nil, nil, tostring(chunk)
    end
    if type(chunk) ~= "string" then
      return nil, nil, read_err or ("cannot read " .. path)
    end

    local context, first_line, complete_before, complete_after =
      M.context_from_chunk(
        chunk,
        from,
        byte_offset,
        match_line,
        context_size,
        to >= size
      )

    if context and complete_before and complete_after then
      return context, first_line
    end
    if from == 0 and to >= size then
      return context, first_line
    end

    window = window * 2
  end

  return nil, nil, "context window too small"
end

--- Read the lines around a match.
---@param context_size integer
---@param match_line integer 1-based
---@param path string
---@param read? fun(path: string): string[]|nil, string|nil
---@param byte_offset? integer 0-based absolute start of the match line
---@return string[]|nil lines
---@return integer|nil first_line
---@return string|nil err
function M.get_match_context(context_size, match_line, path, read, byte_offset)
  if not read and type(byte_offset) == "number" then
    local size = vim.fn.getfsize(path)
    if size > FULL_READ_LIMIT then
      local context, first_line =
        M.read_context(path, match_line, context_size, byte_offset, nil, size)
      if context then
        return context, first_line
      end
    end
  end

  local ok, lines, read_err = pcall(read or default_read, path)
  if not ok then
    return nil, nil, tostring(lines)
  end
  if type(lines) ~= "table" then
    return nil, nil, read_err or ("cannot read " .. path)
  end

  local first_line = math.max(1, match_line - context_size)
  local last_line = math.min(#lines, match_line + context_size)
  local context = {}
  for i = first_line, last_line do
    context[#context + 1] = lines[i]
  end

  return context, first_line
end

--- Build the documentation buffer contents.
---@param path string
---@param match_line integer
---@param lines string[]|nil
---@param width integer|nil
---@param err string|nil
---@return string[]
function M.build_text(path, match_line, lines, width, err)
  local divider_width = math.max(1, (width or 40) - 1)
  local text = { path .. ":" .. match_line, string.rep("─", divider_width) }

  if err then
    text[#text + 1] = "blink-fff: " .. err
    return text
  end

  for _, line in ipairs(lines or {}) do
    text[#text + 1] = line
  end

  return text
end

---@param bufnr integer
---@param path string
---@param options blink-fff.Options
local function apply_file_highlighting(bufnr, path, options)
  local ok_type, filetype = pcall(vim.filetype.match, { filename = path })
  if not ok_type or type(filetype) ~= "string" or filetype == "" then
    return
  end

  local ok_lang, lang = pcall(vim.treesitter.language.get_lang, filetype)
  if ok_lang and type(lang) == "string" then
    pcall(vim.treesitter.stop, bufnr)
    if pcall(vim.treesitter.start, bufnr, lang) then
      return
    end
  end

  if options.fallback_to_regex_highlighting then
    pcall(function()
      vim.bo[bufnr].filetype = filetype
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd("syntax on")
      end)
    end)
  end
end

--- Render an item's documentation into blink's documentation window.
---@param draw_opts blink.cmp.CompletionDocumentationDrawOpts
---@param candidate { token: string, relative_path: string, line_number: integer, byte_offset?: integer, base_path?: string }
---@param options blink-fff.Options
function M.render(draw_opts, candidate, options)
  local window = draw_opts and draw_opts.window
  local bufnr = window and window:get_buf()
  if not bufnr or type(candidate) ~= "table" then
    return
  end

  local path = candidate.relative_path
  if candidate.base_path and candidate.base_path ~= "" then
    path = vim.fs.joinpath(candidate.base_path, candidate.relative_path)
  end

  local width = 40
  if window.get_width then
    width = window:get_width()
    if window.get_border_size then
      width = width - window:get_border_size().horizontal
    end
  end
  if width <= 1 and type(window.config) == "table" then
    width = window.config.max_width or width
  end

  local context, err
  if path and path ~= "" then
    context, _, err = M.get_match_context(
      options.context_size,
      candidate.line_number,
      path,
      nil,
      candidate.byte_offset
    )
  else
    err = "no file path"
  end

  local text =
    M.build_text(path or "", candidate.line_number, context, width, err)

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, text)
  apply_file_highlighting(bufnr, path or "", options)

  if not err then
    highlighting.highlight(bufnr, nil, candidate.token, context, 2)
  end
end

return M
