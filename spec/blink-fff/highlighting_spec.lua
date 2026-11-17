local highlighting = require("blink-fff.highlighting")

describe("blink-fff.highlighting", function()
  it("finds every plain occurrence on a line", function()
    assert.same({ { 1, 3 }, { 5, 7 } }, highlighting.find_all("foo foo", "foo"))
    assert.same({}, highlighting.find_all("foo", ""))
    assert.same({}, highlighting.find_all("foo", "bar"))
  end)

  it("marks each occurrence in the documentation buffer", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "foo bar",
      "foo foo",
    })

    local ns = vim.api.nvim_create_namespace("blink-fff-spec")
    highlighting.highlight(buf, ns, "foo", { "foo bar", "foo foo" }, 0)

    local marks =
      vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    assert.equals(3, #marks)
    assert.equals(0, marks[1][2])
    assert.equals(0, marks[1][3])
    assert.equals(3, marks[1][4].end_col)
  end)

  it("clears previous marks on the same namespace", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "foo", "bar" })
    local ns = vim.api.nvim_create_namespace("blink-fff-spec-clear")

    highlighting.highlight(buf, ns, "foo", { "foo", "bar" }, 0)
    highlighting.highlight(buf, ns, "bar", { "foo", "bar" }, 0)

    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
    assert.equals(1, #marks)
    assert.equals(1, marks[1][2])
  end)
end)
