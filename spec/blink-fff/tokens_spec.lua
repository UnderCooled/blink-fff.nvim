local tokens = require("blink-fff.tokens")

describe("blink-fff.tokens", function()
  describe("expand", function()
    it("expands to the surrounding ascii identifier", function()
      local line = "local foo_bar = 1"
      local token, start_col, end_col = tokens.expand(line, 6, 9)

      assert.equals("foo_bar", token)
      assert.equals(6, start_col)
      assert.equals(13, end_col)
    end)

    it("expands across utf-8 bytes without splitting a character", function()
      -- "let " is 4 bytes, then three 3-byte CJK characters
      local line = "let 变量名 = 1"
      local token, start_col, end_col = tokens.expand(line, 4, 7)

      assert.equals("变量名", token)
      assert.equals(4, start_col)
      assert.equals(13, end_col)
    end)

    it("keeps an emoji inside the token", function()
      local line = "x😀y"
      local token, start_col, end_col = tokens.expand(line, 1, 5)

      assert.equals("x😀y", token)
      assert.equals(0, start_col)
      assert.equals(6, end_col)
    end)

    it("stops at punctuation", function()
      local line = "(hello), world"
      local token = tokens.expand(line, 1, 6)

      assert.equals("hello", token)
    end)

    it("rejects zero-width and out-of-range ranges", function()
      assert.is_nil(tokens.expand("abc", 1, 1))
      assert.is_nil(tokens.expand("abc", -1, 2))
      assert.is_nil(tokens.expand("abc", 2, 4))
      assert.is_nil(tokens.expand("abc", 2, 1))
    end)

    it("rejects non-string input", function()
      assert.is_nil(tokens.expand(nil, 0, 1))
    end)
  end)

  describe("candidates", function()
    it("deduplicates by token and keeps the first location", function()
      local items = {
        {
          relative_path = "a.lua",
          line_number = 1,
          line_content = "alpha beta",
          match_ranges = { { 0, 1 }, { 6, 7 } },
        },
        {
          relative_path = "b.lua",
          line_number = 2,
          line_content = "alpha gamma",
          match_ranges = { { 6, 7 } },
        },
      }
      local result = tokens.candidates(items, "al")

      assert.equals(3, #result)
      assert.equals("alpha", result[1].text)
      assert.equals("a.lua", result[1].relative_path)
      assert.equals("beta", result[2].text)
      assert.equals("gamma", result[3].text)
    end)

    it("skips the token that is already typed, ignoring case", function()
      local items = {
        {
          relative_path = "a.lua",
          line_number = 1,
          line_content = "Foo foobar",
          match_ranges = { { 0, 3 }, { 4, 7 } },
        },
      }
      local result = tokens.candidates(items, "FOO")

      assert.equals(1, #result)
      assert.equals("foobar", result[1].text)
    end)

    it("ignores malformed items and ranges", function()
      local items = {
        { line_content = "alpha", match_ranges = { { 10, 12 } } },
        { line_content = 42, match_ranges = { { 0, 1 } } },
        { match_ranges = { { 0, 1 } } },
        { line_content = "alpha" },
      }

      assert.same({}, tokens.candidates(items, "al"))
      assert.same({}, tokens.candidates(nil, "al"))
    end)
  end)
end)
