local M = {}

---@class blink-fff.Candidate
---@field text string Expanded identifier
---@field relative_path string File containing the first match
---@field line_number integer First matching line
---@field byte_offset integer|nil 0-based absolute start of the matching line
---@field line_content string Matching line
---@field start_col integer 0-based byte column of the token
---@field end_col integer 0-based exclusive byte column of the token

--- Byte classes match blink-ripgrep: ASCII word characters, hyphen, and every
--- byte >= 128 so continuous UTF-8 sequences stay intact.
---@param byte integer
---@return boolean
local function is_word_byte(byte)
  return (byte >= 48 and byte <= 57)
    or (byte >= 65 and byte <= 90)
    or (byte >= 97 and byte <= 122)
    or byte == 95
    or byte == 45
    or byte >= 128
end

--- Expand a byte range to the surrounding identifier.
---@param line string
---@param start_col integer 0-based inclusive byte column
---@param end_col integer 0-based exclusive byte column
---@return string|nil token
---@return integer|nil start_col
---@return integer|nil end_col
function M.expand(line, start_col, end_col)
  if type(line) ~= "string" then
    return nil
  end
  if type(start_col) ~= "number" or type(end_col) ~= "number" then
    return nil
  end
  if start_col % 1 ~= 0 or end_col % 1 ~= 0 then
    return nil
  end
  if start_col < 0 or start_col >= end_col then
    return nil
  end
  if end_col > #line then
    return nil
  end

  local start = start_col
  while start > 0 and is_word_byte(line:byte(start)) do
    start = start - 1
  end

  local finish = end_col
  while finish < #line and is_word_byte(line:byte(finish + 1)) do
    finish = finish + 1
  end

  return line:sub(start + 1, finish), start, finish
end

--- Expand and deduplicate every match range in an fff result.
---@param items table[]|nil fff content_search items
---@param prefix string Currently typed keyword
---@return blink-fff.Candidate[]
function M.candidates(items, prefix)
  if type(items) ~= "table" then
    return {}
  end

  local lowered_prefix = type(prefix) == "string" and prefix:lower() or ""
  local seen = {}
  local candidates = {}

  for _, item in ipairs(items) do
    local line = item.line_content
    local ranges = item.match_ranges
    if type(line) == "string" and type(ranges) == "table" then
      for _, range in ipairs(ranges) do
        if type(range) == "table" then
          local token, start_col, end_col = M.expand(line, range[1], range[2])
          if token and token ~= "" and token:lower() ~= lowered_prefix then
            if not seen[token] then
              seen[token] = true
              candidates[#candidates + 1] = {
                text = token,
                relative_path = item.relative_path,
                line_number = item.line_number,
                byte_offset = item.byte_offset,
                line_content = line,
                start_col = start_col,
                end_col = end_col,
              }
            end
          end
        end
      end
    end
  end

  return candidates
end

return M
