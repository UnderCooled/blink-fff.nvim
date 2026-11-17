local tokens = require("blink-fff.tokens")

local M = {}

local KIND_TEXT = 1
local ICON = "󰈔"

---@param candidate blink-fff.Candidate
---@param base_path string|nil
---@param options blink-fff.Options
---@return table documentation
local function documentation_for(candidate, base_path, options)
  local location = {
    relative_path = candidate.relative_path,
    line_number = candidate.line_number,
    byte_offset = candidate.byte_offset,
    base_path = base_path,
  }

  return {
    kind = "plaintext",
    value = "",
    location = location,
    draw = function(draw_opts)
      require("blink-fff.documentation").render(draw_opts, {
        token = candidate.text,
        relative_path = candidate.relative_path,
        line_number = candidate.line_number,
        byte_offset = candidate.byte_offset,
        base_path = base_path,
      }, options)
    end,
  }
end

--- Map an fff result to blink completion items.
---@param result table|nil { items: table[], base_path?: string }
---@param prefix string
---@param options blink-fff.Options
---@return blink.cmp.CompletionItem[]
function M.build(result, prefix, options)
  if type(result) ~= "table" then
    return {}
  end

  local built = {}
  for _, candidate in ipairs(tokens.candidates(result.items, prefix)) do
    ---@type blink.cmp.CompletionItem
    local item = {
      label = candidate.text,
      filterText = candidate.text,
      insertText = candidate.text,
      source_id = "blink-fff",
      kind = KIND_TEXT,
      documentation = documentation_for(candidate, result.base_path, options),
    }

    if options.customize_icon_highlight then
      item.kind_icon = ICON
      item.kind_hl = "BlinkFffKind"
      item.kind_name = "FFF"
    end

    built[#built + 1] = item
  end

  return built
end

return M
