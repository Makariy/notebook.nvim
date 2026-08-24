local Cell = require("notebook.notebook.cell")
local Notebook = require("notebook.notebook.notebook")
local Output = require("notebook.notebook.output")
local helpers = require("tests.helpers")

-- Regression: the state/separator virtual lines must be anchored at the cell
-- markers in the LIVE buffer. A full-buffer rewrite that happens after the
-- initial render (e.g. an undo-history clear) used to move every virt extmark
-- onto the last line, so all statuses/delimiters piled up at the bottom of the
-- window. These checks inspect the actual extmarks, not just the layout data.

local function make_view(sources, outputs)
	local nb = Notebook.new()
	for i, src in ipairs(sources) do
		local cell = Cell.code(src)
		cell.metadata.id = "c" .. i
		if outputs and outputs[i] then
			cell:add_output(Output.new({ output_type = "stream", name = "stdout", text = outputs[i] }))
		end
		table.insert(nb.cells, cell)
	end
	local view = helpers.open_view(nb, "test_virtual_lines.ipynb")
	if outputs then
		for i = 1, #outputs do
			view.execution_state:set_done("c" .. i, true)
		end
	end
	vim.wait(30)
	return view
end

local function undo_break(view)
	local ul = vim.bo[view.code_buf].undolevels
	vim.bo[view.code_buf].undolevels = ul
end

-- Single code cell: header above its marker, trailing separator at the end.
do
	local view = make_view({ "print('A')" })
	check(#view._cell_starts == 1, "V1 one cell marker")
	check(view._cell_starts[1] == 1, "V1 marker after the leading anchor line")
	helpers.check_virt_anchors(view, "V1 after open")
end

-- Two cells, the first with output (so padding shifts the second marker down).
do
	local view = make_view({ "for i in range(3):\n    print(i)", "print('B')" }, {
		"0\n1\n2\n",
	})
	check(#view._cell_starts == 2, "V2 two cell markers")
	helpers.check_virt_anchors(view, "V2 after open (with output padding)")
end

-- After editing the code, the re-render must re-anchor the virtual lines.
do
	local view = make_view({ "print('A')\nx = 1", "print('B')" })
	vim.api.nvim_buf_set_lines(view.code_buf, 4, 5, false, {})
	vim.wait(80)
	helpers.check_virt_anchors(view, "V3 after editing code")
end

-- After executing a cell (output added -> padding changes), anchors hold.
do
	local view = make_view({ "print('A')", "print('B')" })
	view.session.command_executer = {
		execute = function(_, _, opts)
			for _, c in ipairs(view.notebook.cells) do
				if c.metadata.id == (opts and opts.cell_id) then
					c:add_output(Output.new({ output_type = "stream", name = "stdout", text = "out\n" }))
				end
			end
			vim.defer_fn(function()
				if opts and opts.on_done then
					opts.on_done("ok", 1)
				end
			end, 20)
			return "m"
		end,
	}
	function view.session:execute_cell(index)
		local cell = self.notebook:get(index)
		if not cell or not cell:is_code() then
			return
		end
		local id = cell.metadata.id
		self.command_executer:execute(cell.source, {
			cell_id = id,
			on_done = function(status, count)
				cell.execution_count = count
				self:_notify_done(id, status, count)
			end,
		})
	end
	vim.api.nvim_win_set_cursor(view.code_win, { view:get_cell_start(2) + 1, 0 })
	view.controller:execute_current_cell()
	vim.wait(80)
	helpers.check_virt_anchors(view, "V4 after executing a cell")
end

-- After delete + undo, the restored layout re-anchors correctly.
do
	local view = make_view({ "print('A')", "print('B')" })
	vim.api.nvim_win_set_cursor(view.code_win, { view:get_cell_start(2) + 1, 0 })
	undo_break(view)
	view.controller:delete_cell()
	vim.wait(30)
	helpers.check_virt_anchors(view, "V5 after deleting a cell")
end
