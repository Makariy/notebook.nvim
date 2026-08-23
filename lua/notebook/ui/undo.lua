local M = {}

---@param buf integer
function M.clear(buf)
	vim.api.nvim_buf_call(buf, function()
		local old = vim.bo[buf].undolevels
		vim.bo[buf].undolevels = -1
		local n = vim.api.nvim_buf_line_count(buf)
		vim.api.nvim_buf_set_lines(buf, n, n, false, { "" })
		vim.api.nvim_buf_set_lines(buf, n, n + 1, false, {})
		vim.bo[buf].undolevels = old
		vim.bo[buf].modified = false
	end)
end

return M
