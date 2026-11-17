local repo = vim.fn.getcwd()
local with_fff = vim.env.BLINK_FFF_NO_FFF ~= "1"

vim.opt.rtp:append(repo)
if with_fff then
  vim.opt.rtp:append(vim.fn.expand("~/AppData/Local/nvim-data/lazy/fff.nvim"))
end

local failures = {}
local function check(condition, message)
  if not condition then
    failures[#failures + 1] = message
    print("FAIL: " .. message)
  else
    print("ok: " .. message)
  end
end

local calls = 0
if with_fff then
  local fff = require("fff")
  for _ = 1, 100 do
    local result = fff.content_search("function", { time_budget_ms = 80 })
    if result and #result.items > 0 then break end
    vim.wait(200)
  end

  local original = fff.content_search
  fff.content_search = function(...)
    calls = calls + 1
    return original(...)
  end
end

local Source = require("blink-fff")
local source = Source.new({ debounce_ms = 0, prefix_min_len = 3, context_size = 2 }, {})

local function ctx(keyword, bufnr)
  return {
    bufnr = bufnr or 1,
    get_keyword = function()
      return keyword
    end,
  }
end

local function complete(keyword, bufnr)
  local state = { called = false, response = nil, error = nil }
  local ok, cancel = pcall(source.get_completions, source, ctx(keyword, bufnr), function(response)
    state.called = true
    state.response = response
  end)
  if not ok then state.error = cancel end
  vim.wait(2000, function()
    return state.called or state.error ~= nil
  end, 10)
  return state
end

local function file_ctx(query, bufnr)
  local line = "see @" .. query
  return {
    bufnr = bufnr or 1,
    line = line,
    pos = { row = 0, col = #line },
    get_keyword = function()
      return ""
    end,
  }
end

local function complete_file(query, bufnr)
  local state = { called = false, response = nil, error = nil }
  local ok, cancel = pcall(source.get_completions, source, file_ctx(query, bufnr), function(response)
    state.called = true
    state.response = response
  end)
  if not ok then state.error = cancel end
  vim.wait(2000, function()
    return state.called or state.error ~= nil
  end, 10)
  return state
end

if with_fff then
  local first = complete("funct")
  check(first.error == nil, "first completion does not error")
  check(first.called, "first completion calls back")
  check(first.response ~= nil, "first completion returns a response")
  check(first.response and #first.response.items > 0, "first completion returns items")
  check(calls >= 1, "first completion searched fff")

  local item = first.response and first.response.items[1]
  check(item ~= nil and item.source_id == "blink-fff", "item has blink-fff source_id")
  check(item ~= nil and type(item.label) == "string" and item.label ~= "", "item has a label")

  local calls_after_first = calls
  local cached = complete("funct")
  check(cached.called and cached.response ~= nil, "repeated prefix completes")
  check(calls == calls_after_first, "repeated prefix is served from cache")

  local changed = complete("blinkf")
  check(changed.called, "changed prefix calls back")
  check(calls == calls_after_first + 1, "changed prefix searches once")

  local short = complete("fu")
  check(short.called and short.response == nil, "short prefix yields nil response")

  local bare = complete_file("")
  check(bare.error == nil, "bare file trigger does not error")
  check(
    bare.response ~= nil and #bare.response.items > 0,
    "bare file trigger lists files"
  )

  local forward = complete_file("lua/")
  check(forward.called and forward.response ~= nil, "file query calls back")
  check(
    forward.response ~= nil and #forward.response.items > 0,
    "file query returns items"
  )
  local file_item = forward.response and forward.response.items[1]
  check(
    file_item ~= nil and file_item.kind == 17 and file_item.source_id == "blink-fff",
    "file item is a blink-fff File item"
  )

  local file_result =
    require("blink-fff.searcher").default_file_search("lua/", source.config)
  check(
    file_result ~= nil
      and file_result.base_path == require("fff.conf").get().base_path,
    "file search reports the fff index root"
  )
  check(
    file_item ~= nil and file_item.label:find("\\", 1, true) == nil,
    "file label follows the typed '/' separator"
  )

  if vim.fn.has("win32") == 1 then
    local backward = complete_file("lua\\")
    local win_item = backward.response and backward.response.items[1]
    check(
      win_item ~= nil and win_item.label:find("\\", 1, true) ~= nil,
      "file label follows the typed '\\' separator"
    )
  end

  local doc_buf = vim.api.nvim_create_buf(false, true)
  local window = {
    get_buf = function()
      return doc_buf
    end,
    get_width = function()
      return 60
    end,
    get_border_size = function()
      return { horizontal = 0, vertical = 0 }
    end,
  }
  local draw_ok, draw_err = pcall(function()
    item.documentation.draw({ window = window, item = item })
  end)
  check(draw_ok, "documentation draw does not error: " .. tostring(draw_err))
  local lines = vim.api.nvim_buf_get_lines(doc_buf, 0, -1, false)
  check(#lines >= 3, "documentation has a header and context")
  local expected_name = vim.fs.basename(item.documentation.location.relative_path)
  check(
    lines[1]:find(expected_name, 1, true) ~= nil,
    "documentation header has the file path"
  )
  local highlighted = vim.bo[doc_buf].filetype ~= ""
    or (vim.treesitter.highlighter ~= nil
      and vim.treesitter.highlighter.active[doc_buf] ~= nil)
  check(highlighted, "documentation applies syntax or tree-sitter highlighting")
  local ns = vim.api.nvim_get_namespaces()["blink-fff-docs"]
  local marks = ns and vim.api.nvim_buf_get_extmarks(doc_buf, ns, 0, -1, {}) or {}
  check(#marks > 0, "documentation marks the matched token")
  print("doc_extmarks=" .. #marks)
else
  check(require("blink-fff.searcher").default_search("foob", {}) == nil, "default search is nil without fff")
  local state = complete("foob")
  check(state.error == nil, "missing fff does not error")
  check(state.called, "missing fff still calls back")
  check(state.response == nil, "missing fff yields nil response")
end

if #failures > 0 then
  print(#failures .. " failure(s)")
  vim.cmd("cq")
end

print("smoke_ok")
vim.cmd("qa!")
