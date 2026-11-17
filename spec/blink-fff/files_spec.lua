local config = require("blink-fff.config")
local files = require("blink-fff.files")

describe("blink-fff.files", function()
  describe("separator", function()
    it("follows the separator typed in the query", function()
      assert.equals("/", files.separator("lua/bl"))
      assert.equals("\\", files.separator("lua\\bl"))
      assert.equals("\\", files.separator("lua/bl\\x"))
    end)

    it("falls back to 'shellslash' when the query has none", function()
      local shellslash = vim.o.shellslash
      vim.o.shellslash = true
      assert.equals("/", files.separator("lua"))

      vim.o.shellslash = false
      local native = vim.fn.has("win32") == 1 and "\\" or "/"
      assert.equals(native, files.separator("lua"))

      vim.o.shellslash = shellslash
    end)

    it("prefers 'completeslash' over 'shellslash'", function()
      if vim.fn.exists("+completeslash") ~= 1 then
        return
      end

      local completeslash = vim.o.completeslash
      local shellslash = vim.o.shellslash

      vim.o.shellslash = false
      vim.o.completeslash = "slash"
      assert.equals("/", files.separator("lua"))

      vim.o.shellslash = true
      vim.o.completeslash = "backslash"
      assert.equals("\\", files.separator("lua"))

      vim.o.completeslash = completeslash
      vim.o.shellslash = shellslash
    end)
  end)

  describe("convert", function()
    it("rewrites separators in both directions", function()
      assert.equals(
        "lua\\blink-fff\\init.lua",
        files.convert("lua/blink-fff/init.lua", "\\")
      )
      assert.equals(
        "lua/blink-fff/init.lua",
        files.convert("lua\\blink-fff\\init.lua", "/")
      )
    end)
  end)

  describe("query", function()
    it("returns the text typed after the trigger", function()
      local line = "see @lua/bl"
      assert.equals("lua/bl", files.query(line, #line, "@"))
    end)

    it("uses the last trigger before the cursor", function()
      local line = "@a @b"
      assert.equals("b", files.query(line, #line, "@"))
    end)

    it("honours a custom trigger", function()
      local line = "see #lua/init.lua"
      assert.equals("lua/init.lua", files.query(line, #line, "#"))
      assert.is_nil(files.query(line, #line, "@"))
    end)

    it("stops at whitespace", function()
      local line = "@foo bar"
      assert.is_nil(files.query(line, #line, "@"))
    end)

    it("returns nil without a trigger or a cursor", function()
      assert.is_nil(files.query("plain", 5, "@"))
      assert.is_nil(files.query(nil, 3, "@"))
      assert.is_nil(files.query("@x", nil, "@"))
    end)
  end)

  describe("search_query", function()
    it("normalizes typed backslashes for fff", function()
      assert.equals("lua/bl", files.search_query("lua\\bl"))
      assert.equals("lua/bl", files.search_query("lua/bl"))
    end)
  end)

  describe("relative", function()
    local cwd = vim.fn.getcwd()

    local function in_dir(dir, fn)
      local previous = vim.fn.getcwd()
      vim.fn.chdir(dir)
      local ok, err = pcall(fn)
      vim.fn.chdir(previous)
      if not ok then
        error(err)
      end
    end

    it("resolves the index path against 'getcwd'", function()
      local path = files.relative("README.md", cwd)
      assert.equals("README.md", files.convert(path, "/"))
    end)

    it("is relative to 'getcwd', not the index root", function()
      local path
      in_dir(vim.fs.joinpath(cwd, "lua"), function()
        path = files.relative("lua/blink-fff/init.lua", cwd)
      end)
      assert.equals("blink-fff/init.lua", files.convert(path, "/"))
    end)

    it("walks up to a file above 'getcwd'", function()
      local path
      in_dir(vim.fs.joinpath(cwd, "lua"), function()
        path = files.relative("README.md", cwd)
      end)
      assert.equals("../README.md", files.convert(path, "/"))
    end)

    it("walks up from a nested directory", function()
      local path
      in_dir(vim.fs.joinpath(cwd, "lua", "blink-fff"), function()
        path = files.relative("spec/blink-fff/files_spec.lua", cwd)
      end)
      assert.equals(
        "../../spec/blink-fff/files_spec.lua",
        files.convert(path, "/")
      )
    end)

    it("leaves the path alone without an index root", function()
      assert.equals("lua/x.lua", files.relative("lua/x.lua", nil))
      assert.equals("", files.relative("", cwd))
    end)
  end)

  describe("build", function()
    local function result()
      return {
        items = {
          { relative_path = "lua/blink-fff/init.lua" },
          { relative_path = "lua/blink-fff/init.lua" },
          { relative_path = "README.md" },
          { relative_path = "" },
          {},
        },
      }
    end

    it("uses the query separator for label and insert text", function()
      local built = files.build(result(), "lua\\bl", config.new())

      assert.equals(2, #built)
      assert.equals("lua\\blink-fff\\init.lua", built[1].label)
      assert.equals("lua\\blink-fff\\init.lua", built[1].insertText)
      assert.equals("lua/blink-fff/init.lua", built[1].filterText)
      assert.equals("blink-fff", built[1].source_id)
      assert.equals(17, built[1].kind)
      assert.is_nil(built[1].textEdit)
    end)

    it("uses 'shellslash' when the query has no separator", function()
      local shellslash = vim.o.shellslash
      local has_completeslash = vim.fn.exists("+completeslash") == 1
      local completeslash = has_completeslash and vim.o.completeslash or nil

      vim.o.shellslash = true
      if has_completeslash then
        vim.o.completeslash = ""
      end

      local built = files.build(result(), "read", config.new())
      assert.equals("lua/blink-fff/init.lua", built[1].label)

      if has_completeslash then
        vim.o.completeslash = completeslash
      end
      vim.o.shellslash = shellslash
    end)

    it("inserts paths relative to the working directory", function()
      local cwd = vim.fn.getcwd()
      local previous = vim.fn.getcwd()
      vim.fn.chdir(vim.fs.joinpath(cwd, "lua"))
      local ok, built = pcall(files.build, {
        base_path = cwd,
        items = { { relative_path = "lua/blink-fff/init.lua" } },
      }, "blink-fff/", config.new())
      vim.fn.chdir(previous)
      assert.is_true(ok)

      assert.equals("blink-fff/init.lua", built[1].label)
      assert.equals("blink-fff/init.lua", built[1].insertText)
      assert.equals("blink-fff/init.lua", built[1].filterText)
    end)

    it("adds icon metadata only when requested", function()
      local built = files.build(
        result(),
        "read",
        config.new({ customize_icon_highlight = false })
      )
      assert.is_nil(built[1].kind_icon)
    end)

    it("returns an empty list for a missing or empty result", function()
      assert.same({}, files.build(nil, "read", config.new()))
      assert.same({}, files.build({ items = {} }, "read", config.new()))
    end)
  end)
end)
