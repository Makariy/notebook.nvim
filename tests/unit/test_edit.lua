local Cell = require("notebook.notebook.cell")
local Notebook = require("notebook.notebook.notebook")
local Output = require("notebook.notebook.output")
local helpers = require("tests.helpers")

-- Regression: editing the code buffer must never shift or delete output lines in
-- the results buffer (they used to be mirrored at the edit position, corrupting
-- the display). Instead the layout is rebuilt by a debounced re-render, so the
-- model and both buffers end up consistent.
local function make_view()
	local nb = Notebook.new()
	local cell = Cell.code("import time\nfor i in range(10):\n    print(i)\n    time.sleep(0.2)")
	cell.metadata.id = "ce1f384"
	cell:add_output(Output.new({ output_type = "stream", name = "stdout", text = "0\n1\n2\n3\n4\n5\n6\n7\n8\n9\n" }))
	table.insert(nb.cells, cell)

	local view = helpers.open_view(nb, "test_edit.ipynb")
	view.execution_state:set_done("ce1f384", true)
	vim.wait(30)
	return view
end

local function results_lines(view)
	return vim.api.nvim_buf_get_lines(view.results_buf, 0, -1, false)
end

do
	local view = make_view()

	-- Deleting a source line must not delete an output line.
	vim.api.nvim_buf_set_lines(view.code_buf, 5, 6, false, {})

	local res = results_lines(view)
	local out = {}
	for _, l in ipairs(res) do
		if l ~= "" and l ~= "~" then
			table.insert(out, l)
		end
	end
	check(#out == 10, "deleting a code line keeps all 10 output lines")
	check(out[4] == "3", "output line 3 still present (was not shifted)")

	-- Once the debounced render settles, the model reflects the edit and the
	-- buffers are realigned.
	vim.wait(100)
	check(
		view.notebook.cells[1].source == "import time\nfor i in range(10):\n    print(i)",
		"model source reflects the deletion"
	)
	check(
		vim.api.nvim_buf_line_count(view.code_buf) == vim.api.nvim_buf_line_count(view.results_buf),
		"buffers realign after edit"
	)
end

do
	local view = make_view()

	-- Inserting a source line must not insert a gap inside the output.
	vim.api.nvim_buf_set_lines(view.code_buf, 3, 3, false, { "    # added" })

	local res = results_lines(view)
	local out = {}
	for _, l in ipairs(res) do
		if l ~= "" and l ~= "~" then
			table.insert(out, l)
		end
	end
	check(#out == 10, "inserting a code line keeps all 10 output lines")
	check(out[1] == "0" and out[10] == "9", "output contiguous, no gap inserted")

	vim.wait(100)
	check(
		view.notebook.cells[1].source
			== "import time\n    # added\nfor i in range(10):\n    print(i)\n    time.sleep(0.2)",
		"model source reflects the insertion"
	)
	check(
		vim.api.nvim_buf_line_count(view.code_buf) == vim.api.nvim_buf_line_count(view.results_buf),
		"buffers realign after insertion"
	)
end

do
	local view = make_view()

	-- Re-rendering must not run away (a render may rewrite padding in the code
	-- buffer; that write must not schedule another render).
	local renders = 0
	local orig = view.sync
	view.sync = function(...)
		renders = renders + 1
		return orig(...)
	end

	vim.api.nvim_buf_set_lines(view.code_buf, 5, 6, false, {})
	vim.wait(300)
	view.sync = orig
	check(renders == 1, "a single edit schedules exactly one re-render")
end

-- Regression: typing a trailing blank at the end of a cell must not strand the
-- cursor in the next cell. The parse strips the trailing blank (a decoration
-- write), so cursor_guard must classify the cursor against the buffer's actual
-- markers and clamp it back inside the cell.
do
	local nb = Notebook.new()
	local c1 = Cell.code("print('A')\nprint('B')")
	c1.metadata.id = "c1"
	table.insert(nb.cells, c1)
	local c2 = Cell.code("print('C')")
	c2.metadata.id = "c2"
	table.insert(nb.cells, c2)
	local view = helpers.open_view(nb, "test_edit.ipynb")
	vim.wait(30)

	-- Append a newline at the very end of cell 1's source.
	vim.api.nvim_win_set_cursor(view.code_win, { view._cell_starts[1] + 1 + 2, 999 })
	vim.fn.feedkeys("A\n\x1b", "xt")
	vim.wait(200)

	local row, cell = vim.api.nvim_win_get_cursor(view.code_win)[1], view:get_current_cell_index()
	check(cell == 1, "cursor stays in the edited cell after a trailing blank is stripped")
	check(row <= view._cell_starts[2], "cursor line stays within the edited cell's block (row " .. row .. ")")
end

-- Regression: hiding a cell's output shrinks its block; the cursor must stay in
-- the cell rather than drift into the next one.
do
	local nb = Notebook.new()
	local c1 = Cell.code("x = 1")
	c1.metadata.id = "c1"
	c1:add_output(Output.new({ output_type = "stream", name = "stdout", text = "o1\no2\no3\no4\no5" }))
	table.insert(nb.cells, c1)
	local c2 = Cell.code("y = 2")
	c2.metadata.id = "c2"
	table.insert(nb.cells, c2)
	local view = helpers.open_view(nb, "test_edit.ipynb")
	vim.wait(30)

	-- Park the cursor on the cell's padding (below its code), then hide output.
	view:set_cursor(view._cell_starts[2], 0)
	vim.wait(30)
	view.controller:toggle_cell_output()
	vim.wait(30)

	check(view:get_current_cell_index() == 1, "cursor stays in the cell after its output is hidden")
end
