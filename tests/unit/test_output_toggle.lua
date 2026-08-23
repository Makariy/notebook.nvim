local Cell = require("notebook.notebook.cell")
local Notebook = require("notebook.notebook.notebook")
local Output = require("notebook.notebook.output")
local helpers = require("tests.helpers")

---Build a view whose first cell has a source of one line and three output lines,
---so hiding the output must also remove the two padding lines from the code
---buffer (block height collapses from 3 to 1).
local function make_view()
	local nb = Notebook.new()
	local c = Cell.code("print('A')")
	c.metadata.id = "c1"
	c:add_output(Output.new({ output_type = "stream", name = "stdout", text = "0\n1\n2\n" }))
	table.insert(nb.cells, c)
	return helpers.open_view(nb, "test_output_toggle.ipynb")
end

local function results_text(view)
	return table.concat(vim.api.nvim_buf_get_lines(view.results_buf, 0, -1, false), "|")
end

local function code_text(view)
	return table.concat(vim.api.nvim_buf_get_lines(view.code_buf, 0, -1, false), "|")
end

local function aligned(view)
	return vim.api.nvim_buf_line_count(view.code_buf) == vim.api.nvim_buf_line_count(view.results_buf)
end

-- Toggle the current cell: output lines and padding disappear, buffers align,
-- and a second toggle restores everything.
do
	local view = make_view()
	vim.wait(30)
	vim.api.nvim_win_set_cursor(view.code_win, { view:get_cell_start(1) + 1, 0 })

	check(results_text(view):find("0|1|2", 1, true) ~= nil, "OT1 output visible initially")
	local visible_count = vim.api.nvim_buf_line_count(view.code_buf)

	view.controller:toggle_cell_output()
	vim.wait(30)
	check(results_text(view):find("0|1|2", 1, true) == nil, "OT2 cell output hidden")
	check(results_text(view):find("%[outputs hidden%]") ~= nil, "OT2 muted placeholder shown")
	check(aligned(view), "OT2 buffers aligned")
	local hidden_count = vim.api.nvim_buf_line_count(view.code_buf)
	check(hidden_count < visible_count, "OT2 padding removed with the output")
	check(code_text(view):find("print%('A'%)", 1, false) ~= nil, "OT2 source still shown")

	view.controller:toggle_cell_output()
	vim.wait(30)
	check(results_text(view):find("0|1|2", 1, true) ~= nil, "OT3 output restored on second toggle")
	check(vim.api.nvim_buf_line_count(view.code_buf) == visible_count, "OT3 padding restored")
	check(aligned(view), "OT3 buffers aligned")
end

-- Toggle all: hides every code cell's output, and toggling again reveals all.
do
	local nb = Notebook.new()
	local c1 = Cell.code("print('A')")
	c1.metadata.id = "a"
	c1:add_output(Output.new({ output_type = "stream", name = "stdout", text = "A\n" }))
	local c2 = Cell.code("print('B')")
	c2.metadata.id = "b"
	c2:add_output(Output.new({ output_type = "stream", name = "stdout", text = "B\n" }))
	table.insert(nb.cells, c1)
	table.insert(nb.cells, c2)
	local view = helpers.open_view(nb, "test_output_toggle.ipynb")
	vim.wait(30)

	view.controller:toggle_outputs()
	vim.wait(30)
	check(results_text(view):find("A", 1, true) == nil, "OT4 all outputs hidden")
	check(results_text(view):find("B", 1, true) == nil, "OT4 second cell output hidden too")
	check(vim.fn.count(results_text(view), "[outputs hidden]") == 2, "OT4 placeholder per hidden cell")
	check(aligned(view), "OT4 buffers aligned")

	view.controller:toggle_outputs()
	vim.wait(30)
	check(results_text(view):find("A", 1, true) ~= nil, "OT5 outputs revealed again")
	check(results_text(view):find("B", 1, true) ~= nil, "OT5 second cell revealed too")
	check(aligned(view), "OT5 buffers aligned")
end

-- A markdown cell is unaffected by the current-cell toggle.
do
	local nb = Notebook.new()
	local md = Cell.markdown("some text")
	md.metadata.id = "m1"
	local code = Cell.code("print('A')")
	code.metadata.id = "c1"
	code:add_output(Output.new({ output_type = "stream", name = "stdout", text = "out\n" }))
	table.insert(nb.cells, md)
	table.insert(nb.cells, code)
	local view = helpers.open_view(nb, "test_output_toggle.ipynb")
	vim.wait(30)

	vim.api.nvim_win_set_cursor(view.code_win, { view:get_cell_start(1) + 1, 0 })
	view.controller:toggle_cell_output()
	vim.wait(30)
	check(results_text(view):find("some text", 1, true) ~= nil, "OT6 markdown cell text unaffected")
	check(aligned(view), "OT6 buffers aligned")
end

-- Both commands are registered by setup().
do
	require("notebook").setup()
	local commands = vim.api.nvim_get_commands({})
	check(commands["NotebookCellToggleOutput"] ~= nil, "OT7 NotebookCellToggleOutput registered")
	check(commands["NotebookToggleOutputs"] ~= nil, "OT7 NotebookToggleOutputs registered")
end
