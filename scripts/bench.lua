local script_path = debug.getinfo(1, "S").source:sub(2)
local project_root = vim.fs.dirname(vim.fs.dirname(script_path))
local repo = vim.fn.getcwd()
vim.opt.rtp:append(project_root)
vim.opt.rtp:append(vim.fn.expand("~/AppData/Local/nvim-data/lazy/fff.nvim"))

local fff = require("fff")
local config = require("blink-fff.config").new({})
local searcher = require("blink-fff.searcher")

for _ = 1, 100 do
  local result = fff.content_search("function", { time_budget_ms = 80 })
  if result and #result.items > 0 then break end
  vim.wait(200)
end

local prefixes = { "blink", "content", "function", "searcher" }
local iterations = 30

print("repo=" .. repo)
for _, prefix in ipairs(prefixes) do
  local times = {}
  local last_hits = 0
  for _ = 1, iterations do
    local started = vim.uv.hrtime()
    local result = searcher.default_search(prefix, config)
    times[#times + 1] = (vim.uv.hrtime() - started) / 1e6
    last_hits = result and #result.items or 0
  end

  table.sort(times)
  local p50 = times[math.max(1, math.floor(#times * 0.5))]
  local p95 = times[math.max(1, math.ceil(#times * 0.95))]
  print(string.format("prefix=%s hits=%d p50_ms=%.2f p95_ms=%.2f max_ms=%.2f", prefix, last_hits, p50, p95, times[#times]))
end

print("bench_done")
vim.cmd("qa!")
