local config = require("blink-fff.config")
local files = require("blink-fff.files")
local items = require("blink-fff.items")
local searcher = require("blink-fff.searcher")

---@class blink-fff.Source
---@field config blink-fff.Options
---@field searcher blink-fff.Searcher
---@field file_searcher blink-fff.Searcher
local Source = {}
Source.__index = Source

local function setup_highlights()
  pcall(
    vim.api.nvim_set_hl,
    0,
    "BlinkFffKind",
    { link = "Special", default = true }
  )
  pcall(
    vim.api.nvim_set_hl,
    0,
    "BlinkFffMatch",
    { link = "Search", default = true }
  )
end

---@param input_opts? blink-fff.Options
---@param _ blink.cmp.SourceProviderConfig
---@return blink-fff.Source
function Source.new(input_opts, _)
  local self = setmetatable({}, Source)
  self.config = config.new(input_opts)
  self.searcher = searcher.new(self.config)
  self.file_searcher =
    searcher.new(self.config, { search = searcher.default_file_search })
  setup_highlights()

  vim.schedule(function()
    if type(searcher.prewarm) == "function" then
      searcher.prewarm()
    end
  end)

  return self
end

---@return boolean
function Source:enabled()
  return self.config.enabled ~= false
end

--- The trigger and the path separators keep the context alive while a path
--- is typed; blink hides the menu on any other non-keyword character.
---@return string[]
function Source:get_trigger_characters()
  return { self.config.file_trigger_char, "/", "\\" }
end

---@param context blink.cmp.Context
---@return string
local function get_prefix(self, context)
  local ok, prefix
  if self.config.get_prefix then
    ok, prefix = pcall(self.config.get_prefix, context)
  else
    ok, prefix = pcall(context.get_keyword, context)
  end

  if not ok or type(prefix) ~= "string" then
    return ""
  end
  return prefix
end

---@param context blink.cmp.Context
---@param callback fun(response?: blink.cmp.CompletionResponse)
---@return (fun(): nil)|nil
function Source:get_completions(context, callback)
  local file_query = files.query(
    context.line,
    context.pos and context.pos.col,
    self.config.file_trigger_char
  )

  if file_query ~= nil then
    local file_range = files.range(
      context.line,
      context.pos and context.pos.row,
      context.pos and context.pos.col,
      self.config.file_trigger_char
    )

    return self.file_searcher:request(
      files.search_query(file_query),
      context.bufnr or 0,
      function(result)
        if not result then
          callback(nil)
          return
        end

        callback({
          items = files.build(result, file_query, self.config, file_range),
          is_incomplete_forward = true,
          is_incomplete_backward = true,
        })
      end
    )
  end

  local prefix = get_prefix(self, context)

  if #prefix < self.config.prefix_min_len then
    callback(nil)
    return
  end

  local bufnr = context.bufnr or 0

  return self.searcher:request(prefix, bufnr, function(result)
    if not result then
      callback(nil)
      return
    end

    callback({
      items = items.build(result, prefix, self.config),
      is_incomplete_forward = false,
      is_incomplete_backward = false,
    })
  end)
end

return Source
