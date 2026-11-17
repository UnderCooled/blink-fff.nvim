-- Search-latency benchmark for blink-ripgrep (reference project).
-- Usage: nvim --headless -u NONE -l scripts/bench/ripgrep.lua <repo> [cold|warm] [query]
--   cold: time one search (what hyperfine measures)
--   warm: time 'iterations' searches per prefix; ripgrep rescans on every call
local script_path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local project_root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(script_path)))
local reference = project_root .. "/reference"
local repo = assert(arg[1], "repo path required")
local mode = arg[2] or "cold"
local cold_query = arg[3] or "function"
local prefixes = { "function", "return", "static" }
local iterations = 10

vim.opt.rtp:prepend(project_root)
vim.opt.rtp:prepend(reference .. "/blink-ripgrep.nvim")
vim.opt.rtp:prepend(vim.fn.expand("$LOCALAPPDATA/nvim-data/lazy/blink.cmp"))
vim.opt.rtp:prepend(vim.fn.expand("$LOCALAPPDATA/nvim-data/lazy/blink.lib"))
vim.cmd.cd(repo)

local source = require("blink-ripgrep").new({ backend = { use = "ripgrep" } })

local function search(prefix)
  local done, response = false, nil
  local started = vim.uv.hrtime()
  source:get_completions({ line = prefix, cursor = { 1, #prefix } }, function(resp)
    done = true
    response = resp
  end)
  assert(vim.wait(600000, function() return done end, 1), "ripgrep search timed out")
  -- blink-ripgrep already keeps one item per distinct match text.
  local hits = response and response.items and #response.items or 0
  return (vim.uv.hrtime() - started) / 1e6, hits
end

if mode == "cold" then
  local query_ms, hits = search(cold_query)
  print(string.format("plugin=ripgrep mode=cold query_ms=%.1f hits=%d", query_ms, hits))
else
  for _, prefix in ipairs(prefixes) do
    local times, hits = {}, 0
    for _ = 1, iterations do
      local ms, n = search(prefix)
      times[#times + 1] = ms
      hits = n
    end
    table.sort(times)
    local p50 = times[math.max(1, math.floor(#times * 0.5))]
    local p95 = times[math.max(1, math.ceil(#times * 0.95))]
    print(
      string.format(
        "plugin=ripgrep prefix=%s p50_ms=%.1f p95_ms=%.1f max_ms=%.1f hits=%d",
        prefix,
        p50,
        p95,
        times[#times],
        hits
      )
    )
  end
end

vim.cmd("qa!")
