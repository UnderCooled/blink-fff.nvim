local config = require("blink-fff.config")
local documentation = require("blink-fff.documentation")

describe("blink-fff.documentation", function()
  it("reads the requested context window", function()
    local lines = {}
    for i = 1, 10 do
      lines[i] = "line " .. i
    end

    local context, first_line = documentation.get_match_context(
      2,
      5,
      "x.lua",
      function()
        return lines
      end
    )

    assert.equals(3, first_line)
    assert.same({ "line 3", "line 4", "line 5", "line 6", "line 7" }, context)
  end)

  it("clamps the context at the start of the file", function()
    local context, first_line = documentation.get_match_context(
      4,
      2,
      "x.lua",
      function()
        return { "a", "b", "c" }
      end
    )

    assert.equals(1, first_line)
    assert.same({ "a", "b", "c" }, context)
  end)

  it("reports an unreadable file", function()
    local context, first_line, err = documentation.get_match_context(
      2,
      5,
      "missing.lua",
      function()
        return nil, "cannot open"
      end
    )

    assert.is_nil(context)
    assert.is_nil(first_line)
    assert.equals("cannot open", err)
  end)

  it("builds a header, divider, and context lines", function()
    local text =
      documentation.build_text("src/a.lua", 5, { "line 4", "line 5" }, 20)

    assert.equals("src/a.lua:5", text[1])
    assert.equals(string.rep("─", 19), text[2])
    assert.equals("line 4", text[3])
    assert.equals("line 5", text[4])
  end)

  it("shows the read error instead of context", function()
    local text = documentation.build_text("src/a.lua", 5, nil, 20, "missing")

    assert.equals("src/a.lua:5", text[1])
    assert.equals("blink-fff: missing", text[3])
  end)

  it("renders into the documentation window buffer", function()
    local path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "first", "second", "third" }, path)

    local buf = vim.api.nvim_create_buf(false, true)
    local win = {
      get_buf = function()
        return buf
      end,
      get_width = function()
        return 30
      end,
      get_border_size = function()
        return { horizontal = 0, vertical = 0 }
      end,
    }
    local item = {
      token = "second",
      relative_path = path,
      line_number = 2,
      base_path = nil,
    }

    documentation.render(
      { window = win },
      item,
      config.new({
        context_size = 1,
        fallback_to_regex_highlighting = false,
      })
    )

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals(path .. ":2", lines[1])
    assert.equals("─", string.sub(lines[2], 1, 3))
    assert.equals("first", lines[3])
    assert.equals("second", lines[4])
    assert.equals("third", lines[5])
  end)

  it("selects context from a complete byte chunk", function()
    local context, first, before_ok, after_ok =
      documentation.context_from_chunk("aaa\nbbb\nccc\nddd\n", 0, 8, 3, 1, true)

    assert.same({ "bbb", "ccc", "ddd" }, context)
    assert.equals(2, first)
    assert.is_true(before_ok)
    assert.is_true(after_ok)
  end)

  it("reports incomplete edges when a chunk starts mid-file", function()
    local context, first, before_ok, after_ok =
      documentation.context_from_chunk("bbb\nccc\nddd\n", 4, 8, 3, 1, false)

    assert.same({ "ccc", "ddd" }, context)
    assert.equals(3, first)
    assert.is_false(before_ok)
    assert.is_true(after_ok)
  end)

  it("reads only a byte window for a large file", function()
    local lines = {}
    for i = 1, 20000 do
      lines[i] = "line " .. i
    end
    local content = table.concat(lines, "\n") .. "\n"
    local target = 10000
    local byte_offset = 0
    for i = 1, target - 1 do
      byte_offset = byte_offset + #lines[i] + 1
    end

    local calls = 0
    local bytes = 0
    local function read_blob(offset, size)
      calls = calls + 1
      local chunk = content:sub(offset + 1, offset + size)
      bytes = bytes + #chunk
      return chunk
    end

    local context, first = documentation.read_context(
      "fake.txt",
      target,
      2,
      byte_offset,
      read_blob,
      #content
    )

    assert.equals(target - 2, first)
    assert.same({
      "line 9998",
      "line 9999",
      "line 10000",
      "line 10001",
      "line 10002",
    }, context)
    assert.equals(1, calls)
    assert.is_true(bytes < #content)
  end)

  it("loads a large file through readblob", function()
    local lines = {}
    for i = 1, 20000 do
      lines[i] = "line " .. i
    end
    local path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile(lines, path)

    local target = 10000
    local byte_offset = 0
    for i = 1, target - 1 do
      byte_offset = byte_offset + #lines[i] + 1
    end

    local context, first =
      documentation.get_match_context(2, target, path, nil, byte_offset)
    vim.fn.delete(path)

    assert.equals(target - 2, first)
    assert.equals("line 9998", context[1])
    assert.equals("line 10000", context[3])
    assert.equals("line 10002", context[5])
  end)
end)
