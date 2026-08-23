---@class WindowLayout
local M = {}

---Open a vertical split showing `buf`, place it in the given direction, and
---run `configure` on the new window. The new window becomes the current window.
---@param direction "leftabove" | "rightbelow"
---@param buf integer
---@param configure fun(win: integer)
---@return integer win
function M.split(direction, buf, configure)
	vim.cmd(direction .. " vsplit")
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)
	configure(win)
	return win
end

return M
