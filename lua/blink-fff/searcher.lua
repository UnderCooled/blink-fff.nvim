local debug = require("blink-fff.debug")

local M = {}

---@param handle any uv timer or test double
local function close_timer(handle)
  if handle == nil then
    return
  end
  if type(handle.is_closing) == "function" and handle:is_closing() then
    return
  end
  if type(handle.stop) == "function" then
    handle:stop()
  end
  if type(handle.close) == "function" then
    handle:close()
  end
end

---@param options blink-fff.Options
---@return table fff.ContentSearchOpts
local function search_options(options)
  return {
    mode = options.mode,
    page_size = options.page_size,
    max_matches_per_file = options.max_matches_per_file,
    time_budget_ms = options.time_budget_ms,
    enforce_time_budget = options.enforce_time_budget,
    casing = options.casing,
    trim_whitespace = false,
    classify_definitions = false,
  }
end

--- Search through fff. Never raises into the completion callback.
---@param prefix string
---@param options blink-fff.Options
---@return table|nil result { items: table[], base_path?: string }
function M.default_search(prefix, options)
  local ok, fff = pcall(require, "fff")
  if
    not ok
    or type(fff) ~= "table"
    or type(fff.content_search) ~= "function"
  then
    return nil
  end

  local base_path
  local ok_conf, conf = pcall(require, "fff.conf")
  if ok_conf and type(conf) == "table" and type(conf.get) == "function" then
    local ok_get, value = pcall(conf.get)
    if ok_get and type(value) == "table" then
      base_path = value.base_path
    end
  end

  local ok_search, result =
    pcall(fff.content_search, prefix, search_options(options))
  if not ok_search or type(result) ~= "table" then
    debug.log(options, "search failed: " .. tostring(result))
    return nil
  end

  return { items = result.items or {}, base_path = base_path }
end

--- Start the fff index without performing a search.
function M.prewarm()
  pcall(function()
    local core = require("fff.core")
    if type(core.ensure_initialized) == "function" then
      core.ensure_initialized()
    end
  end)
end

---@class blink-fff.Searcher
---@field options blink-fff.Options
---@field generation integer
---@field timer any
---@field cache table<string, table>
---@field cache_order string[]

local Searcher = {}

local CACHE_LIMIT = 16

---@param self blink-fff.Searcher
---@param key string
local function cache_touch(self, key)
  for i, value in ipairs(self.cache_order) do
    if value == key then
      table.remove(self.cache_order, i)
      break
    end
  end
  self.cache_order[#self.cache_order + 1] = key
end

---@param self blink-fff.Searcher
---@param key string
---@return table|nil
local function cache_get(self, key)
  local value = self.cache[key]
  if value ~= nil then
    cache_touch(self, key)
  end
  return value
end

---@param self blink-fff.Searcher
---@param key string
---@param value table
local function cache_put(self, key, value)
  self.cache[key] = value
  cache_touch(self, key)

  while #self.cache_order > CACHE_LIMIT do
    local evicted = table.remove(self.cache_order, 1)
    self.cache[evicted] = nil
  end
end

---@param options blink-fff.Options
---@param deps? { search?: fun(prefix: string, options: blink-fff.Options): table|nil, defer?: fun(fn: function, ms: integer): any }
---@return blink-fff.Searcher
function M.new(options, deps)
  deps = deps or {}
  return setmetatable({
    options = options,
    generation = 0,
    timer = nil,
    cache = {},
    cache_order = {},
    _search = deps.search or M.default_search,
    _defer = deps.defer or vim.defer_fn,
  }, { __index = Searcher })
end

--- Request completions. Returns a cancel function that only clears the pending
--- debounce timer; a running synchronous fff search cannot be interrupted.
---@param prefix string
---@param bufnr integer
---@param callback fun(result: table|nil)
---@return fun()
function Searcher:request(prefix, bufnr, callback)
  self.generation = self.generation + 1
  local generation = self.generation
  local key = tostring(bufnr) .. ":" .. prefix

  local cached = cache_get(self, key)
  if cached ~= nil then
    callback(cached)
    return function() end
  end

  local handle
  handle = self._defer(function()
    if self.timer == handle then
      self.timer = nil
    end
    if generation ~= self.generation then
      debug.log(self.options, "discarded stale search for " .. prefix)
      return
    end

    local started = type(vim.uv) == "table" and vim.uv.hrtime() or nil
    local result = self._search(prefix, self.options)
    local elapsed_ms
    if started then
      elapsed_ms = (vim.uv.hrtime() - started) / 1e6
    end

    if generation ~= self.generation then
      debug.log(self.options, "discarded stale result for " .. prefix)
      return
    end

    if result ~= nil then
      cache_put(self, key, result)
    end

    debug.log(
      self.options,
      string.format(
        "search %q: %d items%s",
        prefix,
        result and #result.items or 0,
        elapsed_ms and string.format(", %.1f ms", elapsed_ms) or ""
      )
    )

    callback(result)
  end, self.options.debounce_ms)

  self.timer = handle

  return function()
    if self.timer == handle then
      self.timer = nil
      close_timer(handle)
    end
    if self.generation == generation then
      self.generation = self.generation + 1
    end
  end
end

return M
