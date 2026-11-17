local config = require("blink-fff.config")

local M = {}

local function health()
  return vim.health or require("vim.health")
end

function M.check()
  local h = health()
  h.start("blink-fff")

  local ok_blink, blink = pcall(require, "blink.cmp")
  if ok_blink then
    local ok_version, version = pcall(function()
      return blink.version
    end)
    h.ok(
      "blink.cmp is available"
        .. (ok_version and version and (" (" .. tostring(version) .. ")") or "")
    )
  else
    h.warn("blink.cmp is not available: " .. tostring(blink))
  end

  local ok_fff, fff = pcall(require, "fff")
  if not ok_fff then
    h.error("fff.nvim is required but not available: " .. tostring(fff))
  else
    h.ok("fff.nvim is available")

    local initialized = type(fff) == "table"
      and type(fff.state) == "table"
      and fff.state.initialized
    if initialized then
      h.info("fff is initialized (the background scan may still be running)")
    else
      h.info("fff has not been initialized yet")
    end

    local ok_conf, conf = pcall(require, "fff.conf")
    if ok_conf and type(conf) == "table" and type(conf.get) == "function" then
      local ok_get, value = pcall(conf.get)
      if ok_get and type(value) == "table" then
        if type(value.base_path) == "string" then
          h.info("base path: " .. value.base_path)
        else
          h.warn("fff has no base_path; the index is not ready")
        end
      end
    end
  end

  local defaults = config.defaults
  if defaults.time_budget_ms == 0 then
    h.warn("time_budget_ms = 0 can block the editor; use a positive budget")
  else
    h.info("search budget: " .. defaults.time_budget_ms .. " ms")
  end

  h.info("prefix_min_len: " .. defaults.prefix_min_len)
end

return M
