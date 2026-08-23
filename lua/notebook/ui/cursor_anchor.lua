local cell_navigation = require("notebook.ui.cell_navigation")

local M = {}

---@class CursorAnchorState
---@field cell_index integer
---@field line_in_cell integer 0-based offset of the cursor line from its cell's marker row
---@field topline_offset integer 0-based offset of the window's topline from the cell's marker row
---@field col integer
---@field curswant integer

---Capture the current view relative to the cell the cursor is in.
---@param win integer
---@param cell_starts integer[] 0-based marker rows, from the buffer as it is *before* the render
---@return CursorAnchorState
function M.capture(win, cell_starts)
	local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
	local cell_index = cell_navigation.index_for_row(view.lnum - 1, cell_starts)
	local cell_start = cell_starts[cell_index] or 0

	return {
		cell_index = cell_index,
		line_in_cell = view.lnum - 1 - cell_start,
		topline_offset = view.topline - 1 - cell_start,
		col = view.col,
		curswant = view.curswant,
	}
end

---Restore a captured view, remapped onto the cell's *new* boundaries.
---@param win integer
---@param anchor CursorAnchorState
---@param new_cell_starts integer[] 0-based marker rows from the current render
---@param new_cell_ends integer[] 0-based last line of each cell from the current render
function M.restore(win, anchor, new_cell_starts, new_cell_ends)
	if not vim.api.nvim_win_is_valid(win) then
		return
	end

	local new_start = new_cell_starts[anchor.cell_index]
	if not new_start then
		return
	end

	local buf = vim.api.nvim_win_get_buf(win)
	local total_lines = vim.api.nvim_buf_line_count(buf)
	local max_line = new_cell_ends[anchor.cell_index] or new_start

	local lnum = math.min(new_start + anchor.line_in_cell, max_line) + 1
	lnum = math.max(1, math.min(lnum, total_lines))

	local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""
	local col = math.max(0, math.min(anchor.col, #line))

	local topline = math.max(1, math.min(new_start + anchor.topline_offset + 1, total_lines))

	vim.api.nvim_win_call(win, function()
		vim.fn.winrestview({ lnum = lnum, col = col, curswant = anchor.curswant, topline = topline })
	end)
end

return M
