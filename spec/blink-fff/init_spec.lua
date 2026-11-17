describe("blink-fff source", function()
  local saved_searcher
  local saved_source
  local searcher_module

  before_each(function()
    saved_searcher = package.loaded["blink-fff.searcher"]
    saved_source = package.loaded["blink-fff"]
    package.loaded["blink-fff"] = nil
  end)

  after_each(function()
    package.loaded["blink-fff.searcher"] = saved_searcher
    package.loaded["blink-fff"] = saved_source
  end)

  local function install_searcher(request)
    searcher_module = {
      new = function()
        return {
          request = function(_, prefix, bufnr, callback)
            return request(prefix, bufnr, callback)
          end,
        }
      end,
      prewarm = function() end,
    }
    package.loaded["blink-fff.searcher"] = searcher_module
  end

  it("is enabled by default and can be disabled", function()
    install_searcher(function() end)
    local Source = require("blink-fff")

    assert.is_true(Source.new({}, {}):enabled())
    assert.is_false(Source.new({ enabled = false }, {}):enabled())
  end)

  it("short-circuits a short keyword without searching", function()
    install_searcher(function()
      error("searcher must not be called")
    end)
    local Source = require("blink-fff")
    local source = Source.new({ prefix_min_len = 4 }, {})

    local response = "unset"
    local cancel = source:get_completions({
      bufnr = 1,
      get_keyword = function()
        return "foo"
      end,
    }, function(value)
      response = value
    end)

    assert.is_nil(response)
    assert.is_nil(cancel)
  end)

  it("forwards the keyword and maps the result", function()
    local captured
    install_searcher(function(prefix, bufnr, callback)
      captured = { prefix = prefix, bufnr = bufnr, callback = callback }
      return "cancel-handle"
    end)
    local Source = require("blink-fff")
    local source = Source.new({}, {})

    local response
    local cancel = source:get_completions({
      bufnr = 7,
      get_keyword = function()
        return "foob"
      end,
    }, function(value)
      response = value
    end)

    assert.equals("cancel-handle", cancel)
    assert.equals("foob", captured.prefix)
    assert.equals(7, captured.bufnr)

    captured.callback({
      items = {
        {
          relative_path = "a.lua",
          line_number = 1,
          line_content = "foobar",
          match_ranges = { { 0, 3 } },
        },
      },
      base_path = "root",
    })

    assert.equals(1, #response.items)
    assert.equals("foobar", response.items[1].label)
    assert.is_false(response.is_incomplete_forward)
    assert.is_false(response.is_incomplete_backward)
  end)

  it("reports a failed search as nil", function()
    install_searcher(function(_, _, callback)
      callback(nil)
    end)
    local Source = require("blink-fff")
    local source = Source.new({}, {})

    local response = "unset"
    source:get_completions({
      bufnr = 1,
      get_keyword = function()
        return "foob"
      end,
    }, function(value)
      response = value
    end)

    assert.is_nil(response)
  end)

  it("uses get_prefix when provided", function()
    local captured
    install_searcher(function(prefix)
      captured = prefix
      return function() end
    end)
    local Source = require("blink-fff")
    local source = Source.new({
      get_prefix = function()
        return "custom"
      end,
    }, {})

    source:get_completions({
      bufnr = 1,
      get_keyword = function()
        return "ignored"
      end,
    }, function() end)

    assert.equals("custom", captured)
  end)

  it("treats a failing get_keyword as an empty prefix", function()
    install_searcher(function()
      error("searcher must not be called")
    end)
    local Source = require("blink-fff")
    local source = Source.new({}, {})

    local response = "unset"
    source:get_completions({
      bufnr = 1,
      get_keyword = function()
        error("no keyword")
      end,
    }, function(value)
      response = value
    end)

    assert.is_nil(response)
  end)
end)
