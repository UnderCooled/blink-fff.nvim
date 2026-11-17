local config = require("blink-fff.config")
local items = require("blink-fff.items")

describe("blink-fff.items", function()
  local function result()
    return {
      items = {
        {
          relative_path = "src/a.lua",
          line_number = 7,
          line_content = "local foobar = 1",
          match_ranges = { { 6, 9 } },
        },
        {
          relative_path = "src/b.lua",
          line_number = 2,
          line_content = "foobar()",
          match_ranges = { { 0, 3 } },
        },
      },
      base_path = "C:/project",
    }
  end

  it("maps each unique token to a blink completion item", function()
    local built = items.build(result(), "foo", config.new())

    assert.equals(1, #built)
    local item = built[1]
    assert.equals("foobar", item.label)
    assert.equals("foobar", item.filterText)
    assert.equals("foobar", item.insertText)
    assert.equals("blink-fff", item.source_id)
    assert.equals(1, item.kind)
    assert.is_nil(item.textEdit)
    assert.is_table(item.documentation)
    assert.is_function(item.documentation.draw)
  end)

  it("keeps the first match location for documentation", function()
    local built = items.build(result(), "foo", config.new())
    local item = built[1]

    assert.equals("src/a.lua", item.documentation.location.relative_path)
    assert.equals(7, item.documentation.location.line_number)
    assert.equals("C:/project", item.documentation.location.base_path)
  end)

  it("adds icon metadata only when requested", function()
    local with_icon = items.build(result(), "foo", config.new())
    assert.equals("󰈔", with_icon[1].kind_icon)
    assert.equals("BlinkFffKind", with_icon[1].kind_hl)
    assert.equals("FFF", with_icon[1].kind_name)

    local without_icon = items.build(
      result(),
      "foo",
      config.new({ customize_icon_highlight = false })
    )
    assert.is_nil(without_icon[1].kind_icon)
  end)

  it("returns an empty list for a missing or empty result", function()
    assert.same({}, items.build(nil, "foo", config.new()))
    assert.same({}, items.build({ items = {} }, "foo", config.new()))
  end)
end)
