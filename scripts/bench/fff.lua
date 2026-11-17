-- Search-latency benchmark for blink-fff.
-- Usage: nvim --headless -u NONE -l scripts/bench/fff.lua <repo> [cold|warm] [query] [nocap|default]
--   cold: wait for fff's index scan, then time one search (what hyperfine measures)
--   warm: wait for the index once, then time 'iterations' searches per prefix
--   nocap: page_size=10000 and no time budget, for same-volume comparisons
local script_path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local project_root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(script_path)))
local repo = assert(arg[1], "repo path required")
local mode = arg[2] or "cold"
local cold_query = arg[3] or "function"
local prefixes = { "function", "return", "static" }
local iterations = 10
local search_opts = arg[4] == "nocap"
    and { page_size = 10000, time_budget_ms = 0, enforce_time_budget = false }
  or {}

vim.opt.rtp:prepend(project_root)
vim.opt.rtp:prepend(vim.fn.expand("$LOCALAPPDATA/nvim-data/lazy/fff.nvim"))
vim.cmd.cd(repo)

local started = vim.uv.hrtime()
require("fff.core").ensure_initialized()
local picker = require("fff.file_picker")
if not picker.is_initialized() then picker.setup() end
assert(picker.wait_for_initial_scan(600000), "fff index scan timed out")
local index_ms = (vim.uv.hrtime() - started) / 1e6

local config = require("blink-fff.config").new(search_opts)
local searcher = require("blink-fff.searcher")
local tokens = require("blink-fff.tokens")

-- fff returns one record per matched line; blink-fff inserts one item per
-- unique expanded token. Report both so hit counts stay comparable.
local function search(prefix)
  local t = vim.uv.hrtime()
  local result = searcher.default_search(prefix, config)
  local elapsed = (vim.uv.hrtime() - t) / 1e6
  local raw = result and #result.items or 0
  local unique = result and #tokens.candidates(result.items, prefix) or 0
  return elapsed, unique, raw
end

if mode == "cold" then
  local query_ms, hits, raw = search(cold_query)
  print(string.format("plugin=fff mode=cold index_ms=%.1f query_ms=%.1f hits=%d raw=%d", index_ms, query_ms, hits, raw))
else
  for _, prefix in ipairs(prefixes) do
    local times, hits, raw = {}, 0, 0
    for _ = 1, iterations do
      local ms, unique, records = search(prefix)
      times[#times + 1] = ms
      hits, raw = unique, records
    end
    table.sort(times)
    local p50 = times[math.max(1, math.floor(#times * 0.5))]
    local p95 = times[math.max(1, math.ceil(#times * 0.95))]
    print(
      string.format(
        "plugin=fff prefix=%s index_ms=%.1f p50_ms=%.1f p95_ms=%.1f max_ms=%.1f hits=%d raw=%d",
        prefix,
        index_ms,
        p50,
        p95,
        times[#times],
        hits,
        raw
      )
    )
  end
end

vim.cmd("qa!")
