local M = {}

---@param row integer 0-based row
---@param starts integer[] 0-based marker rows
---@return integer
function M.index_for_row(row, starts)
	local current = 1
	for i, start_row in ipairs(starts) do
		if row >= start_row then
			current = i
		else
			break
		end
	end
	return current
end

---@param code_win integer
---@param cell_starts integer[]?
---@return integer
function M.current_index(code_win, cell_starts)
	if not cell_starts then
		return 1
	end
	local cursor_row = vim.api.nvim_win_get_cursor(code_win)[1] - 1
	return M.index_for_row(cursor_row, cell_starts)
end

---@param cell_starts integer[]?
---@param index integer
---@return integer?
function M.cell_start(cell_starts, index)
	if not cell_starts then
		return nil
	end
	return cell_starts[index]
end

---@param code_win integer
---@param cell_starts integer[]?
---@param index integer
function M.goto_cell(code_win, cell_starts, index)
	if not cell_starts then
		return
	end
	local start = cell_starts[index]
	if not start then
		return
	end
	vim.api.nvim_win_set_cursor(code_win, { start + 1, 0 })
end

return M
