local codec = require("notebook.ui.codec")
local output_renderer = require("notebook.ui.output_renderer")

local SEP_HL = "NotebookSeparator"
local STATE_HL = "NotebookState"
local MUTED_HL = "NotebookMuted"

local HIDDEN_LABEL = "[outputs hidden]"

---@class NotebookImageBlock
---@field id string
---@field path string
---@field start_row integer 0-based row in the results buffer
---@field overlap integer number of physical lines the image covers

---@class NotebookLayout
---@field code_lines string[] Real lines for the code buffer
---@field res_lines string[] Real lines for the results buffer
---@field code_virts table[] Virtual lines ({ row, lines }) for the code buffer
---@field res_virts table[] Virtual lines ({ row, lines }) for the results buffer
---@field highlights table[] Text highlights for the results buffer
---@field code_highlights table[] Padding placeholders ("~") for the code buffer
---@field cell_starts integer[] 0-based row of each cell marker
---@field cell_ends integer[] 0-based last line of each cell's block
---@field images NotebookImageBlock[]

local NotebookRenderer = {}

---@private
---@param entry ExecutionEntry?
---@return string
local function format_label(entry)
	if not entry then
		return "○ Not executed"
	end
	if entry.state == "busy" then
		return "◐ Running..."
	end
	if entry.state == "success" then
		if entry.start_time and entry.end_time then
			local elapsed = (entry.end_time - entry.start_time) / 1e9
			return "✓ Success in " .. string.format("%.1fs", elapsed)
		end
		return "✓ Success"
	end
	if entry.state == "error" then
		return "✗ Error"
	end
	return "○ Not executed"
end

local NO_STATE = {
	get = function()
		return nil
	end,
}

---@private
---@param cell Cell
---@param execution_state ExecutionState
---@param pending_sep table[]? The previous cell's separator, if any
---@return table[] code_header
---@return table[] res_header
local function cell_header(cell, execution_state, pending_sep)
	local code_header = {}
	local res_header = {}
	if pending_sep then
		table.insert(code_header, pending_sep)
		table.insert(res_header, pending_sep)
	end
	if cell.cell_type == "code" then
		table.insert(code_header, { { format_label(execution_state:get(cell.metadata.id)), STATE_HL } })
		table.insert(res_header, { { " ", STATE_HL } })
	end
	return code_header, res_header
end

---@private
---@param cell Cell
---@param marker_row integer 0-based marker row
---@param resolved? table<string, { id: string, path: string, height_cells: integer }>
---@param highlights table[] Text highlights, appended to
---@param hidden_outputs? table<string, boolean> Cell ids whose outputs are hidden
---@return string[] c_display
---@return string[] r_lines
---@return table[] cell_images
local function cell_body(cell, marker_row, resolved, highlights, hidden_outputs)
	local c_display = codec.render_source_lines(cell)
	local r_lines = {}
	local cell_images = {}

	if cell.cell_type == "markdown" then
		for _, line in ipairs(codec.split_source(cell.source)) do
			table.insert(r_lines, line)
		end
	elseif hidden_outputs and hidden_outputs[cell.metadata.id] then
		table.insert(r_lines, HIDDEN_LABEL)
		table.insert(highlights, {
			row = marker_row + #r_lines,
			start_col = 0,
			end_col = #HIDDEN_LABEL,
			hl = MUTED_HL,
		})
	else
		local output_index = 0
		for _, out in ipairs(cell.outputs) do
			output_index = output_index + 1
			local key = cell.metadata.id .. ":" .. output_index
			local info = resolved and resolved[key]

			if info then
				local rows = math.max(1, info.height_cells or 1)
				local r_start = #r_lines + 1
				for _ = 1, rows do
					table.insert(r_lines, "")
				end
				table.insert(cell_images, { id = info.id, path = info.path, r_start = r_start, rows = rows })
			else
				for _, ol in ipairs(output_renderer.output_lines(out)) do
					table.insert(r_lines, ol.text)
					for _, seg in ipairs(ol.segments) do
						table.insert(highlights, {
							row = marker_row + #r_lines,
							start_col = seg.start,
							end_col = seg["end"],
							hl = seg.hl,
						})
					end
				end
			end
		end
	end

	return c_display, r_lines, cell_images
end

---@param notebook Notebook
---@param win_width? integer
---@param resolved? table<string, { id: string, path: string, height_cells: integer }>
---@param execution_state? ExecutionState
---@param hidden_outputs? table<string, boolean> Cell ids whose outputs are hidden
---@param undo_locked_heights? table<string, integer> Optional map of actual physical line counts from a locked code buffer
---@return NotebookLayout
function NotebookRenderer.build(notebook, win_width, resolved, execution_state, hidden_outputs, undo_locked_heights)
	win_width = win_width or 80
	execution_state = execution_state or NO_STATE

	local code_lines = { "" }
	local res_lines = { "" }
	local code_virts = {}
	local res_virts = {}
	local highlights = {}
	local code_highlights = {}
	local cell_starts = {}
	local cell_ends = {}
	local images = {}

	local sep = string.rep("─", win_width)

	local pending_sep

	for _, cell in ipairs(notebook.cells) do
		local marker_row = #code_lines

		local code_header, res_header = cell_header(cell, execution_state, pending_sep)
		pending_sep = nil
		if #code_header > 0 then
			table.insert(code_virts, { row = marker_row, lines = code_header })
			table.insert(res_virts, { row = marker_row, lines = res_header })
		end

		table.insert(code_lines, codec.marker_for(cell.cell_type, cell.metadata.id))
		table.insert(res_lines, "~")
		table.insert(highlights, { row = #res_lines - 1, start_col = 0, end_col = 1, hl = "NonText" })
		table.insert(cell_starts, marker_row)

		local c_display, r_lines, cell_images = cell_body(cell, marker_row, resolved, highlights, hidden_outputs)
		local block_h = math.max(#c_display, #r_lines)
		if undo_locked_heights and cell.metadata.id then
			local locked_h = undo_locked_heights[cell.metadata.id]
			if locked_h then
				block_h = math.max(#c_display, locked_h)
			end
		end
		table.insert(cell_ends, marker_row + block_h)

		for _, line in ipairs(c_display) do
			table.insert(code_lines, line)
		end
		if block_h > #c_display then
			for _ = 1, block_h - #c_display do
				table.insert(code_lines, "")
			end
		end

		for j = 1, block_h do
			local line = r_lines[j]
			if line == "~" or line == nil then
				line = "~"
				table.insert(highlights, { row = #res_lines, start_col = 0, end_col = 1, hl = "NonText" })
			end
			table.insert(res_lines, line)
		end

		for _, img in ipairs(cell_images) do
			table.insert(images, {
				id = img.id,
				path = img.path,
				start_row = marker_row + img.r_start,
				overlap = img.rows,
			})
		end

		pending_sep = { { sep, SEP_HL } }
	end

	table.insert(code_lines, "")
	table.insert(res_lines, "")
	if pending_sep then
		local trailing_row = #code_lines - 1
		table.insert(code_virts, { row = trailing_row, lines = { pending_sep } })
		table.insert(res_virts, { row = trailing_row, lines = { pending_sep } })
	end

	return {
		code_lines = code_lines,
		res_lines = res_lines,
		code_virts = code_virts,
		res_virts = res_virts,
		highlights = highlights,
		code_highlights = code_highlights,
		cell_starts = cell_starts,
		cell_ends = cell_ends,
		images = images,
	}
end

return NotebookRenderer
