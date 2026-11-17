local M = {}

local KIND_FILE = 17
local ICON = "󰈔"
local IS_WINDOWS = vim.fn.has("win32") == 1
local NATIVE_SEPARATOR = IS_WINDOWS and "\\" or "/"

---@param left string
---@param right string
---@return boolean
local function path_equals(left, right)
  if IS_WINDOWS then
    return left:lower() == right:lower()
  end
  return left == right
end

--- Make an absolute path relative to 'cwd', walking up with '..' outside it.
--- Only a path on another root stays absolute.
---@param absolute string
---@param cwd string
---@return string
local function relative_to(absolute, cwd)
  absolute = vim.fs.normalize(absolute)
  cwd = vim.fs.normalize(cwd)
  if path_equals(absolute, cwd) then
    return "."
  end

  local up = ""
  while cwd ~= "" and cwd ~= "/" and not cwd:match("^%a:/$") do
    local prefix = cwd .. "/"
    if path_equals(absolute:sub(1, #prefix), prefix) then
      return up .. absolute:sub(#prefix + 1)
    end
    local parent = vim.fs.normalize(vim.fn.fnamemodify(cwd, ":h"))
    if parent == cwd then
      break
    end
    cwd = parent
    up = up .. "../"
  end

  return absolute
end

--- Path separator for the completion text.
---
--- The separator typed in the query wins; otherwise 'completeslash' and
--- 'shellslash' decide, like insert-mode file name completion.
---@param query string|nil
---@return string
function M.separator(query)
  if type(query) == "string" then
    if query:find("\\", 1, true) then
      return "\\"
    end
    if query:find("/", 1, true) then
      return "/"
    end
  end

  local ok, completeslash = pcall(function()
    return vim.o.completeslash
  end)
  if ok then
    if completeslash == "backslash" then
      return "\\"
    end
    if completeslash == "slash" then
      return "/"
    end
  end

  if vim.o.shellslash then
    return "/"
  end
  return NATIVE_SEPARATOR
end

--- Rewrite a path with the given separator.
---@param path string
---@param sep string
---@return string
function M.convert(path, sep)
  if sep == "\\" then
    return (path:gsub("/", "\\"))
  end
  return (path:gsub("\\", "/"))
end

--- Text typed after the last trigger character before the cursor.
---
--- Returns nil when the trigger is absent or the typed token already contains
--- whitespace, which ends the completion context.
---@param line string|nil
---@param cursor_col integer|nil 0-based byte column of the cursor
---@param trigger string
---@return string|nil
function M.query(line, cursor_col, trigger)
  if type(line) ~= "string" or type(trigger) ~= "string" or trigger == "" then
    return nil
  end
  if type(cursor_col) ~= "number" or cursor_col < 0 then
    return nil
  end

  local before = line:sub(1, cursor_col)
  local pos
  local from = 1
  while true do
    local found = before:find(trigger, from, true)
    if not found then
      break
    end
    pos = found
    from = found + #trigger
  end

  if not pos then
    return nil
  end

  local text = before:sub(pos + #trigger)
  if text:find("%s") then
    return nil
  end
  return text
end

--- Resolve an fff index path against the editor working directory.
---
--- fff reports paths relative to its index root, but the inserted text must be
--- relative to 'getcwd()'; a target above it is walked up with '..'.
---@param path string fff file.relative_path
---@param base_path string|nil fff index root
---@return string
function M.relative(path, base_path)
  if type(path) ~= "string" or path == "" then
    return path
  end

  local absolute = path
  local is_absolute = path:sub(1, 1) == "/"
    or path:sub(1, 1) == "\\"
    or path:match("^%a:[/\\]") ~= nil

  if not is_absolute then
    if type(base_path) ~= "string" or base_path == "" then
      return path
    end
    absolute = vim.fs.joinpath(base_path, path)
  end

  return relative_to(absolute, vim.fn.getcwd())
end

--- fff indexes forward-slash paths, so a typed '' is only for insertion.
---@param query string
---@return string
function M.search_query(query)
  return (query:gsub("\\", "/"))
end

--- Map an fff file_search result to blink completion items.
---@param result table|nil { items: table[], base_path?: string }
---@param query string Text typed after the trigger
---@param options blink-fff.Options
---@return blink.cmp.CompletionItem[]
function M.build(result, query, options)
  if type(result) ~= "table" or type(result.items) ~= "table" then
    return {}
  end

  local sep = M.separator(query)
  local seen = {}
  local built = {}

  for _, file in ipairs(result.items) do
    local path = type(file) == "table" and file.relative_path or nil
    local relative = M.relative(path, result.base_path)
    if type(relative) == "string" and relative ~= "" and not seen[relative] then
      seen[relative] = true

      local text = M.convert(relative, sep)

      ---@type blink.cmp.CompletionItem
      local item = {
        label = text,
        filterText = M.convert(relative, "/"),
        insertText = text,
        source_id = "blink-fff",
        kind = KIND_FILE,
      }

      if options.customize_icon_highlight then
        item.kind_icon = ICON
        item.kind_hl = "BlinkFffKind"
        item.kind_name = "FFF"
      end

      built[#built + 1] = item
    end
  end

  return built
end

return M
