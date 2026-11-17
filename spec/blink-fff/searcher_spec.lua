local config = require("blink-fff.config")
local searcher = require("blink-fff.searcher")

describe("blink-fff.searcher", function()
  local function new_defer(queue)
    return function(fn, ms)
      local handle = {
        stopped = false,
        closed = false,
      }
      function handle:stop()
        self.stopped = true
      end
      function handle:close()
        self.closed = true
      end
      queue[#queue + 1] = { fn = fn, ms = ms, handle = handle }
      return handle
    end
  end

  local function flush(queue, index)
    local entry = assert(queue[index])
    entry.fn()
  end

  it("debounces one search and returns its result", function()
    local queue = {}
    local calls = 0
    local searched_prefix
    local s = searcher.new(config.new({ debounce_ms = 25 }), {
      defer = new_defer(queue),
      search = function(prefix)
        calls = calls + 1
        searched_prefix = prefix
        return { items = { "x" }, base_path = "root" }
      end,
    })

    local received
    s:request("foo", 1, function(value)
      received = value
    end)

    assert.equals(0, calls)
    assert.equals(1, #queue)
    assert.equals(25, queue[1].ms)

    flush(queue, 1)

    assert.equals(1, calls)
    assert.equals("foo", searched_prefix)
    assert.equals("x", received.items[1])
    assert.equals("root", received.base_path)
  end)

  it("serves a repeated prefix from cache without searching again", function()
    local queue = {}
    local calls = 0
    local s = searcher.new(config.new(), {
      defer = new_defer(queue),
      search = function()
        calls = calls + 1
        return { items = {}, base_path = "root" }
      end,
    })

    s:request("foo", 1, function() end)
    flush(queue, 1)

    local received
    s:request("foo", 1, function(value)
      received = value
    end)

    assert.equals(1, calls)
    assert.equals(1, #queue)
    assert.is_table(received)
  end)

  it("keeps earlier prefixes for backspacing", function()
    local queue = {}
    local calls = 0
    local s = searcher.new(config.new(), {
      defer = new_defer(queue),
      search = function(prefix)
        calls = calls + 1
        return { items = { prefix }, base_path = "root" }
      end,
    })

    s:request("foo", 1, function() end)
    flush(queue, 1)
    s:request("foob", 1, function() end)
    flush(queue, 2)

    local received
    s:request("foo", 1, function(value)
      received = value
    end)

    assert.equals(2, calls)
    assert.equals(2, #queue)
    assert.equals("foo", received.items[1])
  end)

  it("does not share a cache entry across buffers", function()
    local queue = {}
    local calls = 0
    local s = searcher.new(config.new(), {
      defer = new_defer(queue),
      search = function()
        calls = calls + 1
        return { items = {}, base_path = "root" }
      end,
    })

    s:request("foo", 1, function() end)
    flush(queue, 1)
    s:request("foo", 2, function() end)
    assert.equals(2, #queue)
    flush(queue, 2)

    assert.equals(2, calls)
  end)

  it("cancels the pending debounce", function()
    local queue = {}
    local received
    local s = searcher.new(config.new(), {
      defer = new_defer(queue),
      search = function()
        return { items = {}, base_path = "root" }
      end,
    })

    local cancel = s:request("foo", 1, function(value)
      received = value
    end)
    cancel()

    assert.is_true(queue[1].handle.stopped)
    assert.is_true(queue[1].handle.closed)

    flush(queue, 1)
    assert.is_nil(received)
  end)

  it("discards a result from an outdated generation", function()
    local queue = {}
    local received = {}
    local s = searcher.new(config.new(), {
      defer = new_defer(queue),
      search = function(prefix)
        return { items = { prefix }, base_path = "root" }
      end,
    })

    s:request("foo", 1, function(value)
      received[#received + 1] = value
    end)
    s:request("foob", 1, function(value)
      received[#received + 1] = value
    end)

    flush(queue, 1)
    assert.equals(0, #received)

    flush(queue, 2)
    assert.equals(1, #received)
    assert.equals("foob", received[1].items[1])
  end)

  it("reports a failed search as nil and does not cache it", function()
    local queue = {}
    local calls = 0
    local s = searcher.new(config.new(), {
      defer = new_defer(queue),
      search = function()
        calls = calls + 1
        return nil
      end,
    })

    local received = "pending"
    s:request("foo", 1, function(value)
      received = value
    end)
    flush(queue, 1)

    assert.is_nil(received)
    assert.equals(1, calls)

    s:request("foo", 1, function() end)
    assert.equals(2, #queue)
  end)

  it("returns nil from the default search when fff is unavailable", function()
    assert.is_nil(searcher.default_search("foo", config.new()))
  end)
end)
