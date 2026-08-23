local M = {}

---@return boolean Whether the current window is in Visual or Select mode.
function M.active()
	local m = vim.fn.mode()
	return m == "v" or m == "V" or m == "\22" or m == "s" or m == "S" or m == "\19"
end

return M
