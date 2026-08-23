local Cell = require("notebook.notebook.cell")
local Notebook = require("notebook.notebook.notebook")
local CellOutput = require("notebook.notebook.output")
local helpers = require("tests.helpers")

---@param id string
---@param source string
---@return Cell
local function code_cell(id, source)
	local c = Cell.code(source)
	c.metadata.id = id
	return c
end

local function make_view()
	local nb = Notebook.new()
	table.insert(nb.cells, code_cell("c1", "x = 1\nprint(x)\nprint(x)\nprint(x)"))
	table.insert(nb.cells, code_cell("c2", "y = 2"))
	table.insert(nb.cells, code_cell("c3", "z = 3"))
	local view = helpers.open_view(nb, "test_cursor_win.ipynb")
	vim.wait(30)
	return view, nb
end

-- Another plugin (e.g. zen-mode) can open a floating window over the code
-- buffer and the user edits there. Cell navigation and cursor preservation must
-- track the window the user is actually looking at, not the stale code window.
do
	local view, nb = make_view()
	view.focus_mode:toggle("code")

	local start2 = view:get_cell_start(2)
	vim.api.nvim_win_set_cursor(view.code_win, { start2 + 1, 0 })
	check(view:get_current_cell_index() == 2, "CW1 code-window cursor resolves its cell")

	local fwin = vim.api.nvim_open_win(view.code_buf, true, {
		relative = "editor",
		width = 80,
		height = 30,
		col = 40,
		row = 1,
		style = "minimal",
		border = "none",
	})
	vim.api.nvim_win_set_cursor(fwin, { view:get_cell_start(3) + 1, 0 })
	check(view:get_current_cell_index() == 3, "CW2 float cursor resolves the cell under it")

	local cursor = view:get_cursor()
	check(cursor[1] == view:get_cell_start(3) + 1, "CW3 get_cursor reads the float window")

	view:goto_cell(1)
	check(vim.api.nvim_win_get_cursor(fwin)[1] == view:get_cell_start(1) + 1, "CW4 goto_cell moves the float cursor")

	-- A layout change while the float is current (an output makes cell 1 taller,
	-- shifting the cells below) must keep the float cursor anchored to its cell.
	local start3_before = view:get_cell_start(3)
	vim.api.nvim_win_set_cursor(fwin, { start3_before + 1, 0 })
	nb.cells[1]:add_output(CellOutput.new({ output_type = "stream", name = "stdout", text = "a\nb\nc\nd\ne\n" }))
	view:render()
	check(view:get_current_cell_index() == 3, "CW5 render keeps the float cursor in its cell")
	check(
		vim.api.nvim_win_get_cursor(fwin)[1] == view:get_cell_start(3) + 1,
		"CW6 render anchors the float cursor to the cell start"
	)

	vim.api.nvim_win_close(fwin, false)
end

-- Without a float, navigation still goes through the code window (split mode).
do
	local view = make_view()
	local start2 = view:get_cell_start(2)
	vim.api.nvim_win_set_cursor(view.code_win, { start2 + 1, 0 })
	check(view:get_current_cell_index() == 2, "CW7 split mode still uses the code window cursor")
end

-- Entering the results window aligns its cursor to the code window's cell
-- (regression: it used to restore a stale cursor and land on a random line).
do
	local view = make_view()
	local start3 = view:get_cell_start(3)
	vim.api.nvim_win_set_cursor(view.code_win, { start3 + 1, 0 })
	vim.api.nvim_win_set_cursor(view.results_win, { 1, 0 })

	vim.api.nvim_set_current_win(view.results_win)
	local rc = vim.api.nvim_win_get_cursor(view.results_win)
	check(rc[1] == start3 + 1, "CW8 entering the results window aligns the cursor to the code cell")

	vim.api.nvim_set_current_win(view.code_win)
end

-- When cells above the cursor reflow (output padding grows the code buffer),
-- the cursor stays in the same cell AND at the same screen row (winline), so
-- the view does not jump to an unexpected position.
do
	local nb = Notebook.new()
	for i = 1, 12 do
		local c = Cell.code(("s%d\nt%d\nu%d\nv%d\nw%d"):format(i, i, i, i, i))
		c.metadata.id = "c" .. i
		table.insert(nb.cells, c)
	end
	local view = helpers.open_view(nb, "test_reflow.ipynb")
	vim.wait(30)

	view:goto_cell(9)
	local before = vim.api.nvim_win_call(view.code_win, function()
		return vim.fn.winline()
	end)

	for i = 5, 8 do
		view.notebook.cells[i]:add_output(
			CellOutput.new({ output_type = "stream", name = "stdout", text = "o1\no2\no3\no4\no5\no6\no7\no8" })
		)
	end
	view:render()

	local after = vim.api.nvim_win_call(view.code_win, function()
		return vim.fn.winline()
	end)
	check(math.abs(after - before) <= 3, "CW9 cursor keeps its screen row when cells above reflow")
	check(view:get_current_cell_index() == 9, "CW9 cursor stays in the same cell")
end
