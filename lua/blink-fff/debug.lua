local M = {}

--- Write one diagnostic line when options.debug is enabled.
---@param options blink-fff.Options|nil
---@param message string
function M.log(options, message)
  if not (options and options.debug) then
    return
  end
  vim.notify("blink-fff: " .. message, vim.log.levels.INFO)
end

--- @param options blink-fff.Options|nil
--- @param fmt string
function M.logf(options, fmt, ...)
  M.log(options, string.format(fmt, ...))
end

return M
