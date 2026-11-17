local M = {}

--- Find every plain-text occurrence of needle on one line.
---@param line string
---@param needle string
---@return table[] ranges 1-based inclusive byte ranges
function M.find_all(line, needle)
  local ranges = {}
  if type(line) ~= "string" or type(needle) ~= "string" or needle == "" then
    return ranges
  end

  local init = 1
  while true do
    local start_idx, end_idx = string.find(line, needle, init, true)
    if not start_idx then
      break
    end
    ranges[#ranges + 1] = { start_idx, end_idx }
    init = start_idx + 1
  end

  return ranges
end

local namespace_id

local function namespace()
  if not namespace_id then
    namespace_id = vim.api.nvim_create_namespace("blink-fff-docs")
  end
  return namespace_id
end

--- Mark every occurrence of token in the documentation buffer.
---@param bufnr integer
---@param ns_id integer|nil
---@param token string
---@param lines string[] context lines
---@param row_offset integer 0-based buffer row of the first context line
function M.highlight(bufnr, ns_id, token, lines, row_offset)
  ns_id = ns_id or namespace()

  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  pcall(
    vim.api.nvim_set_hl,
    0,
    "BlinkFffMatch",
    { link = "Search", default = true }
  )

  if type(token) ~= "string" or token == "" then
    return
  end

  for i, line in ipairs(lines or {}) do
    for _, range in ipairs(M.find_all(line, token)) do
      pcall(
        vim.api.nvim_buf_set_extmark,
        bufnr,
        ns_id,
        row_offset + i - 1,
        range[1] - 1,
        {
          end_col = range[2],
          hl_group = "BlinkFffMatch",
        }
      )
    end
  end
end

return M
