local M = {}

---@class blink-fff.Options
---@field prefix_min_len? number Minimum keyword length before searching (default 3)
---@field get_prefix? fun(context: blink.cmp.Context): string Override the keyword extraction
---@field mode? 'plain'|'regex'|'fuzzy' fff search mode (default 'plain')
---@field page_size? number Maximum matches returned by fff (default 100)
---@field max_matches_per_file? number Maximum matches per file (default 20)
---@field time_budget_ms? number fff search budget in milliseconds; 0 disables it (default 80)
---@field enforce_time_budget? boolean Apply the budget even when no match exists (default true)
---@field casing? 'smart'|'sensitive'|'insensitive' Search casing (default 'smart')
---@field debounce_ms? number Delay before searching (default 30)
---@field context_size? number Documentation context lines around a match (default 4)
---@field fallback_to_regex_highlighting? boolean Use syntax highlighting when no parser exists (default true)
---@field customize_icon_highlight? boolean Add the fff icon metadata to items (default true)
---@field debug? boolean Log search diagnostics to :messages (default false)
---@field enabled? boolean Enable the source (default true)

---@type blink-fff.Options
M.defaults = {
  prefix_min_len = 3,
  get_prefix = nil,
  mode = "plain",
  page_size = 100,
  max_matches_per_file = 20,
  time_budget_ms = 80,
  enforce_time_budget = true,
  casing = "smart",
  debounce_ms = 30,
  context_size = 4,
  fallback_to_regex_highlighting = true,
  customize_icon_highlight = true,
  debug = false,
  enabled = true,
}

local modes = { plain = true, regex = true, fuzzy = true }
local casings = { smart = true, sensitive = true, insensitive = true }

local integer_options = {
  { "prefix_min_len", 1 },
  { "page_size", 1 },
  { "max_matches_per_file", 0 },
  { "time_budget_ms", 0 },
  { "debounce_ms", 0 },
  { "context_size", 0 },
}

local boolean_options = {
  "enforce_time_budget",
  "fallback_to_regex_highlighting",
  "customize_icon_highlight",
  "debug",
  "enabled",
}

local function fail(name, expected, value)
  error(
    string.format(
      "blink-fff: option %q must be %s, got %s",
      name,
      expected,
      tostring(value)
    ),
    3
  )
end

local function validate(opts)
  for _, entry in ipairs(integer_options) do
    local name, minimum = entry[1], entry[2]
    local value = opts[name]
    if type(value) ~= "number" or value % 1 ~= 0 or value < minimum then
      fail(name, "an integer >= " .. minimum, value)
    end
  end

  for _, name in ipairs(boolean_options) do
    if type(opts[name]) ~= "boolean" then
      fail(name, "a boolean", opts[name])
    end
  end

  if not modes[opts.mode] then
    fail("mode", "'plain', 'regex' or 'fuzzy'", opts.mode)
  end
  if not casings[opts.casing] then
    fail("casing", "'smart', 'sensitive' or 'insensitive'", opts.casing)
  end
  if opts.get_prefix ~= nil and type(opts.get_prefix) ~= "function" then
    fail("get_prefix", "a function", opts.get_prefix)
  end
end

--- Build the effective options from user input and the defaults.
---@param input? blink-fff.Options
---@return blink-fff.Options
function M.new(input)
  local merged = {}
  for key, value in pairs(M.defaults) do
    merged[key] = value
  end

  if input ~= nil then
    if type(input) ~= "table" then
      fail("opts", "a table", input)
    end
    for key in pairs(M.defaults) do
      if input[key] ~= nil then
        merged[key] = input[key]
      end
    end
    -- get_prefix is nil by default, so it is absent from pairs(defaults).
    if input.get_prefix ~= nil then
      merged.get_prefix = input.get_prefix
    end
  end

  validate(merged)
  return merged
end

return M
