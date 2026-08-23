---@param notebook Notebook
---@param path string
---@return NotebookView
local function open_view(notebook, path)
	vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
	local view = require("notebook.ui.notebook_view").new(notebook, path)
	view:open()
	return view
end

---@param buf integer
---@param ns integer
---@return integer[]
local function virt_rows(buf, ns)
	local rows = {}
	for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
		if m[4] and m[4].virt_lines then
			rows[#rows + 1] = m[2]
		end
	end
	table.sort(rows)
	return rows
end

---@param view NotebookView
---@return integer[]
local function expected_virt_rows(view)
	local expected = {}
	for i, start in ipairs(view._cell_starts) do
		local cell = view.notebook.cells[i]
		local leading_non_code = i == 1 and cell and cell.cell_type ~= "code"
		if not leading_non_code then
			expected[#expected + 1] = start
		end
	end
	expected[#expected + 1] = vim.api.nvim_buf_line_count(view.code_buf) - 1
	table.sort(expected)
	return expected
end

---@param view NotebookView
---@param label string
local function check_virt_anchors(view, label)
	local rows = virt_rows(view.code_buf, view.hl_ns)
	local expected = expected_virt_rows(view)
	check(vim.deep_equal(rows, expected), label .. ": state/separator virtual lines anchored at markers (not bottom)")
	check(#rows == #expected, label .. ": one header per cell plus a trailing separator")
	local line_count = vim.api.nvim_buf_line_count(view.code_buf)
	local all_valid = true
	local distinct = {}
	for _, r in ipairs(rows) do
		if r < 0 or r >= line_count then
			all_valid = false
		end
		distinct[r] = true
	end
	check(all_valid, label .. ": every virtual line anchored to a valid row (none past the end)")
	check(
		next(distinct) ~= nil and #vim.tbl_keys(distinct) == #rows,
		label .. ": virtual lines at distinct rows (not collapsed)"
	)
	check(
		vim.deep_equal(virt_rows(view.results_buf, view.hl_ns), rows),
		label .. ": results buffer virtual lines mirror code anchors"
	)
end

---@param buf integer
local function undo(buf)
	vim.api.nvim_buf_call(buf, function()
		vim.cmd("undo")
	end)
end

---@param buf integer
local function redo(buf)
	vim.api.nvim_buf_call(buf, function()
		vim.cmd("redo")
	end)
end

return {
	open_view = open_view,
	virt_rows = virt_rows,
	expected_virt_rows = expected_virt_rows,
	check_virt_anchors = check_virt_anchors,
	undo = undo,
	redo = redo,
}
