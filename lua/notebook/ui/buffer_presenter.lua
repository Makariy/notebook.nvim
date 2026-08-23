local cursor_anchor = require("notebook.ui.cursor_anchor")
local codec = require("notebook.ui.codec")
local CodeBufferWriter = require("notebook.ui.code_buffer_writer")
local visual_guard = require("notebook.ui.visual_guard")

local M = {}

---@private 0-based rows of every cell marker in a rendered buffer.
---@param lines string[]
---@return integer[]
local function marker_rows(lines)
	local rows = {}
	for i, line in ipairs(lines) do
		if codec.parse_marker(line) then
			table.insert(rows, i - 1)
		end
	end
	return rows
end

---@param win integer?
---@return boolean
local function safe_to_touch(win)
	if not (win and vim.api.nvim_win_is_valid(win)) then
		return false
	end
	local current = vim.api.nvim_get_current_win()
	return current == win or not visual_guard.active()
end

---@param ports ViewPorts
---@param layout NotebookLayout
---@param win_width integer
---@param res_width integer
---@param image_renderer ImageRenderer
---@param scroll_sync ScrollSync
---@return boolean changed Whether either buffer was rewritten
function M.apply(ports, layout, win_width, res_width, image_renderer, scroll_sync)
	local current_code = vim.api.nvim_buf_get_lines(ports.code_buf, 0, -1, false)
	local old_cell_starts = marker_rows(current_code)

	local can_touch_cursor = safe_to_touch(ports.cursor_win)
	local anchor
	if can_touch_cursor then
		anchor = cursor_anchor.capture(ports.cursor_win, old_cell_starts)
	end

	local changed = false
	if CodeBufferWriter.write(ports.code_buf, current_code, layout.code_lines) then
		changed = true
	end

	local current_res = vim.api.nvim_buf_get_lines(ports.results_buf, 0, -1, false)
	local res_changed = not CodeBufferWriter.same_lines(current_res, layout.res_lines)
	if res_changed then
		image_renderer:clear_extmarks()
		vim.bo[ports.results_buf].modifiable = true
		vim.api.nvim_buf_set_lines(ports.results_buf, 0, -1, false, layout.res_lines)
		vim.bo[ports.results_buf].modifiable = false
		changed = true
	end

	vim.api.nvim_buf_clear_namespace(ports.results_buf, ports.hl_ns, 0, -1)
	for _, hl in ipairs(layout.highlights) do
		pcall(vim.api.nvim_buf_set_extmark, ports.results_buf, ports.hl_ns, hl.row, hl.start_col, {
			end_row = hl.row,
			end_col = hl.end_col,
			hl_group = hl.hl,
		})
	end

	vim.api.nvim_buf_clear_namespace(ports.code_buf, ports.hl_ns, 0, -1)
	for _, hl in ipairs(layout.code_highlights) do
		pcall(vim.api.nvim_buf_set_extmark, ports.code_buf, ports.hl_ns, hl.row, hl.start_col, {
			virt_text = hl.virt_text,
			virt_text_pos = "overlay",
		})
	end

	for _, v in ipairs(layout.code_virts) do
		pcall(vim.api.nvim_buf_set_extmark, ports.code_buf, ports.hl_ns, v.row, 0, {
			virt_lines = v.lines,
			virt_lines_above = true,
		})
	end
	for _, v in ipairs(layout.res_virts) do
		pcall(vim.api.nvim_buf_set_extmark, ports.results_buf, ports.hl_ns, v.row, 0, {
			virt_lines = v.lines,
			virt_lines_above = true,
		})
	end

	if ports.results_win and vim.api.nvim_win_is_valid(ports.results_win) then
		image_renderer:sync(layout.images, res_width, res_changed)
	end

	if anchor then
		cursor_anchor.restore(ports.cursor_win, anchor, layout.cell_starts, layout.cell_ends)
		scroll_sync:sync_from(ports.cursor_win)
	end

	return changed
end

return M
