local Cell = require("notebook.notebook.cell")
local Notebook = require("notebook.notebook.notebook")
local NotebookRenderer = require("notebook.ui.notebook_renderer")
local codec = require("notebook.ui.codec")
local helpers = require("tests.helpers")

-- Markdown cells: the code window shows the source commented with `# ` (so the
-- file stays valid Python) while the results window shows the real markdown text
-- with that leading comment prefix stripped.

local function make_view(sources)
	local nb = Notebook.new()
	for i, src in ipairs(sources) do
		local cell = Cell.code(src)
		cell.metadata.id = "c" .. i
		table.insert(nb.cells, cell)
	end
	codec.ensure_ids(nb)
	return helpers.open_view(nb, "test_markdown.ipynb")
end

local function undo_break(view)
	local ul = vim.bo[view.code_buf].undolevels
	vim.bo[view.code_buf].undolevels = ul
end

-- Codec: the `# ` prefix (plugin-added comment) is stripped; a bare `#text` is
-- left untouched (the leading "T" must not be truncated).
do
	local specs = codec.parse_lines({
		"# %% [markdown:m1]",
		"# # This is markdown header",
		"# This is markdown text",
		"# #This stays",
		"#",
	})
	check(specs[1].cell_type == "markdown", "M1 marker parsed as markdown")
	check(
		specs[1].source == "# This is markdown header\nThis is markdown text\n#This stays",
		"M1 comment prefix stripped, no-space #T kept"
	)
end

-- Renderer: code lines are prefixed, results lines are the stripped text.
do
	local nb = Notebook.new()
	local md = Cell.markdown("# This is markdown header\nThis is markdown text")
	md.metadata.id = "m1"
	table.insert(nb.cells, md)

	local layout = NotebookRenderer.build(nb, 80)
	check(#layout.code_lines == #layout.res_lines, "M2 code and results stay line-aligned")
	local code_has = table.concat(layout.code_lines, "\n")
	local res_has = table.concat(layout.res_lines, "\n")
	check(code_has:find("# # This is markdown header", 1, true) ~= nil, "M2 code window prefixes markdown with `# `")
	check(code_has:find("# This is markdown text", 1, true) ~= nil, "M2 code window prefixes the second line too")
	check(res_has:find("# This is markdown header", 1, true) ~= nil, "M2 results window shows the real markdown header")
	check(res_has:find("This is markdown text", 1, true) ~= nil, "M2 results window strips the comment prefix")
end

-- View: markdown text rendered in the results buffer.
do
	local nb = Notebook.new()
	local md = Cell.markdown("# This is markdown header\nThis is markdown text")
	md.metadata.id = "m1"
	table.insert(nb.cells, md)
	local view = helpers.open_view(nb, "test_markdown.ipynb")
	vim.wait(30)

	local res = table.concat(vim.api.nvim_buf_get_lines(view.results_buf, 0, -1, false), "|")
	check(res:find("# This is markdown header", 1, true) ~= nil, "M3 results buffer contains stripped markdown header")
	check(res:find("This is markdown text", 1, true) ~= nil, "M3 results buffer contains stripped markdown text")
	check(
		vim.api.nvim_buf_line_count(view.code_buf) == vim.api.nvim_buf_line_count(view.results_buf),
		"M3 buffers aligned for markdown cell"
	)
	helpers.check_virt_anchors(view, "M3 markdown cell virtual lines anchored")
end

-- Toggle: code <-> markdown preserves the source and round-trips.
do
	local view = make_view({ "x = 1\n#This stays" })
	check(view.notebook.cells[1].cell_type == "code", "M4 starts as a code cell")

	vim.api.nvim_win_set_cursor(view.code_win, { view:get_cell_start(1) + 1, 0 })
	view.controller:toggle_cell_type()
	vim.wait(30)
	check(view.notebook.cells[1].cell_type == "markdown", "M4 toggle converts the cell to markdown")

	local res = table.concat(vim.api.nvim_buf_get_lines(view.results_buf, 0, -1, false), "|")
	check(res:find("x = 1", 1, true) ~= nil, "M4 markdown text rendered in results")
	check(res:find("#This stays", 1, true) ~= nil, "M4 no-space #T not truncated in results")

	view.controller:toggle_cell_type()
	vim.wait(30)
	check(view.notebook.cells[1].cell_type == "code", "M4 toggling back restores a code cell")
	check(view.notebook.cells[1].source == "x = 1\n#This stays", "M4 source survives the round trip")
	check(
		vim.api.nvim_buf_line_count(view.code_buf) == vim.api.nvim_buf_line_count(view.results_buf),
		"M4 buffers aligned after toggling back"
	)
end

-- Toggle is undoable.
do
	local view = make_view({ "print('A')" })
	vim.api.nvim_win_set_cursor(view.code_win, { view:get_cell_start(1) + 1, 0 })
	undo_break(view)
	view.controller:toggle_cell_type()
	vim.wait(30)
	check(view.notebook.cells[1].cell_type == "markdown", "M5 toggle to markdown")

	undo_break(view)
	helpers.undo(view.code_buf)
	view:sync()
	vim.wait(30)
	check(view.notebook.cells[1].cell_type == "code", "M5 undo reverts the cell type to code")
	check(view.notebook.cells[1].source == "print('A')", "M5 undo keeps the source intact")
end

-- The command is registered by setup().
do
	require("notebook").setup()
	local commands = vim.api.nvim_get_commands({})
	check(commands["NotebookCellSwitchType"] ~= nil, "M6 :NotebookCellSwitchType is registered")
end

-- Markdown cells carry no execution state line (only code cells do).
do
	local nb = Notebook.new()
	local code = Cell.code("print('A')")
	code.metadata.id = "m7code"
	local md = Cell.markdown("text")
	md.metadata.id = "m7md"
	table.insert(nb.cells, code)
	table.insert(nb.cells, md)

	local layout = NotebookRenderer.build(nb, 80)
	-- Cell 1 (code): header = [state]. Cell 2 (markdown): header = [separator].
	check(layout.code_virts[1].lines[1][1][1] == "○ Not executed", "M7 code cell keeps its state line")
	check(layout.code_virts[2].lines[1][1][1] == string.rep("─", 80), "M7 markdown header starts with the separator")
	check(#layout.code_virts[2].lines == 1, "M7 markdown cell has no state line")
	check(#layout.code_virts == 3, "M7 still one header per cell + trailing separator")
end

-- A leading markdown cell has no header at all (nothing above its marker).
do
	local nb = Notebook.new()
	local md = Cell.markdown("text")
	md.metadata.id = "m8md"
	local code = Cell.code("print('A')")
	code.metadata.id = "m8code"
	table.insert(nb.cells, md)
	table.insert(nb.cells, code)

	local layout = NotebookRenderer.build(nb, 80)
	check(
		layout.code_virts[1].row == layout.cell_starts[2],
		"M8 leading markdown cell has no header; first header is at the code cell"
	)
	check(layout.code_virts[1].lines[1][1][1] == string.rep("─", 80), "M8 code cell header carries the separator")
	check(layout.code_virts[1].lines[2][1][1] == "○ Not executed", "M8 code cell header carries its state")
	check(#layout.code_virts == 2, "M8 leading markdown cell contributes no header extmark")
end

-- The view renders no status line above a markdown cell and stays anchored.
do
	local nb = Notebook.new()
	local code = Cell.code("print('A')")
	code.metadata.id = "m9code"
	local md = Cell.markdown("text")
	md.metadata.id = "m9md"
	table.insert(nb.cells, code)
	table.insert(nb.cells, md)
	local view = helpers.open_view(nb, "test_markdown.ipynb")
	vim.wait(30)

	local rows = {}
	for _, m in ipairs(vim.api.nvim_buf_get_extmarks(view.code_buf, view.hl_ns, 0, -1, { details = true })) do
		if m[4] and m[4].virt_lines then
			rows[#rows + 1] = m[2]
		end
	end
	table.sort(rows)
	check(vim.deep_equal(rows, helpers.expected_virt_rows(view)), "M9 markdown cell header is a separator-only anchor")
	helpers.check_virt_anchors(view, "M9 markdown cell without state line")
end
