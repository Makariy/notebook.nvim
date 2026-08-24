local Cell = require("notebook.notebook.cell")
local Notebook = require("notebook.notebook.notebook")
local Output = require("notebook.notebook.output")
local IpynbParser = require("notebook.notebook.ipynb_parser")

local helpers = require("tests.helpers")

local codec = require("notebook.ui.codec")

---Force an undo boundary (headless edits coalesce otherwise).
---@param view table
local function undo_break(view)
	local ul = vim.bo[view.code_buf].undolevels
	vim.bo[view.code_buf].undolevels = ul
end

---Move the cursor onto the marker of cell @index so get_current_cell_index picks it.
---@param view table
---@param index integer
local function gotocell(view, index)
	local row = view:get_cell_start(index)
	if row then
		vim.api.nvim_win_set_cursor(view.code_win, { row + 1, 0 })
	end
end

---@param view table
---@return boolean
local function aligned(view)
	return vim.api.nvim_buf_line_count(view.code_buf) == vim.api.nvim_buf_line_count(view.results_buf)
end

---Signature of the model: cell_type:source joined by |, in order.
---@param view table
---@return string
local function cells(view)
	local parts = {}
	for _, c in ipairs(view.notebook.cells) do
		table.insert(parts, c.cell_type .. ":" .. c.source)
	end
	return table.concat(parts, "|")
end

---Non-empty output text lines rendered in the results buffer.
---@param view table
---@return string[]
local function rendered_output(view)
	local out = {}
	for _, l in ipairs(vim.api.nvim_buf_get_lines(view.results_buf, 0, -1, false)) do
		if l ~= "" and l ~= "~" then
			table.insert(out, l)
		end
	end
	return out
end

---Install a mock executer keyed by cell id: executing a cell appends a stream
---output to exactly that cell and completes on a short timer.
---@param view table
local function install_executer(view)
	view.session.command_executer = {
		execute = function(_, _, opts)
			---@diagnostic disable-next-line:undefined-field
			local id = opts and opts.cell_id
			for _, c in ipairs(view.notebook.cells) do
				if c.metadata.id == id then
					c:add_output(Output.new({ output_type = "stream", name = "stdout", text = "out[" .. id .. "]\n" }))
				end
			end
			vim.defer_fn(function()
				if opts and opts.on_done then
					opts.on_done("ok", 1)
				end
			end, 20)
			return "msg"
		end,
	}
	local orig = view.session.execute_cell
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
end

---Build a view with the given cells (ids auto-generated).
---@param sources string[]
---@return table
local function make_view(sources)
	local nb = Notebook.new()
	for _, src in ipairs(sources) do
		table.insert(nb.cells, Cell.code(src))
	end
	codec.ensure_ids(nb)
	local view = helpers.open_view(nb, "test_flows.ipynb")
	vim.wait(30)
	return view
end

-- Flow 1: create a cell, execute it (empty), delete it, undo -> restored with output.
do
	local view = make_view({ "print('A')" })
	install_executer(view)
	check(aligned(view), "F1 initial buffers aligned")

	view.controller:create_cell()
	vim.wait(30)
	check(cells(view) == "code:print('A')|code:", "F1 create adds an empty code cell")
	check(aligned(view), "F1 buffers aligned after create")

	gotocell(view, 2)
	undo_break(view)
	view.controller:execute_current_cell()
	vim.wait(80)
	local cell2 = view.notebook.cells[2]
	check(view.execution_state:get(cell2.metadata.id).state == "success", "F1 executed cell reaches success")
	check(#cell2.outputs == 1, "F1 executed cell gained an output")
	check(aligned(view), "F1 buffers aligned after execute")
	check(vim.tbl_count(rendered_output(view)) == 1, "F1 output visible in results buffer")

	undo_break(view)
	view.controller:delete_cell()
	vim.wait(30)
	check(cells(view) == "code:print('A')", "F1 delete removes the executed cell")

	undo_break(view)
	helpers.undo(view.code_buf)
	view:sync()
	vim.wait(30)
	check(cells(view) == "code:print('A')|code:", "F1 undo restores the deleted cell")
	check(#view.notebook.cells[2].outputs == 1, "F1 restored cell keeps its output")
end

-- Flow 2: copy a cell, paste twice, execute the second pasted cell, undo, redo.
do
	local view = make_view({ "print('A')" })
	install_executer(view)

	gotocell(view, 1)
	undo_break(view)
	view.controller:copy_cell()
	undo_break(view)
	view.controller:paste_cell()
	undo_break(view)
	view.controller:paste_cell()
	vim.wait(30)
	check(
		cells(view) == "code:print('A')|code:print('A')|code:print('A')",
		"F2 paste twice yields three identical cells"
	)
	check(aligned(view), "F2 buffers aligned after paste x2")

	-- The two pasted cells get distinct ids.
	local id2, id3 = view.notebook.cells[2].metadata.id, view.notebook.cells[3].metadata.id
	check(id2 ~= id3, "F2 pasted cells have distinct ids")

	-- Execute the second pasted cell (index 3).
	gotocell(view, 3)
	undo_break(view)
	view.controller:execute_current_cell()
	vim.wait(80)
	check(#view.notebook.cells[3].outputs == 1, "F2 executed second pasted cell gained output")
	check(#view.notebook.cells[2].outputs == 0, "F2 first pasted cell untouched")

	undo_break(view)
	helpers.undo(view.code_buf)
	view:sync()
	vim.wait(30)
	check(cells(view) == "code:print('A')|code:print('A')", "F2 undo removes the last pasted cell")

	undo_break(view)
	helpers.redo(view.code_buf)
	view:sync()
	vim.wait(30)
	check(cells(view) == "code:print('A')|code:print('A')|code:print('A')", "F2 redo restores the pasted cell")
	check(#view.notebook.cells[3].outputs == 1, "F2 redone cell keeps its output")
	check(aligned(view), "F2 buffers aligned after redo")
end

-- Flow 3: delete a cell that has output, undo -> output preserved.
do
	local view = make_view({ "print('A')", "print('B')" })
	install_executer(view)
	gotocell(view, 1)
	undo_break(view)
	view.controller:execute_current_cell()
	vim.wait(80)
	check(#view.notebook.cells[1].outputs == 1, "F3 cell executed before delete")

	undo_break(view)
	view.controller:delete_cell()
	vim.wait(30)
	check(cells(view) == "code:print('B')", "F3 delete removes executed cell")

	undo_break(view)
	helpers.undo(view.code_buf)
	view:sync()
	vim.wait(30)
	check(cells(view) == "code:print('A')|code:print('B')", "F3 undo restores deleted cell")
	check(#view.notebook.cells[1].outputs == 1, "F3 restored cell keeps its output")
end

-- Flow 4: cut a cell, paste it, undo, redo.
do
	local view = make_view({ "print('A')", "print('B')" })
	gotocell(view, 2)
	undo_break(view)
	view.controller:cut_cell()
	vim.wait(30)
	check(cells(view) == "code:print('A')", "F4 cut removes the cell")

	undo_break(view)
	view.controller:paste_cell()
	vim.wait(30)
	check(cells(view) == "code:print('A')|code:print('B')", "F4 paste restores a B cell")
	check(view.notebook.cells[2].metadata.id ~= view.notebook.cells[1].metadata.id, "F4 pasted cell is a fresh copy")

	undo_break(view)
	helpers.undo(view.code_buf)
	view:sync()
	vim.wait(30)
	check(cells(view) == "code:print('A')", "F4 undo removes the pasted cell")

	undo_break(view)
	helpers.redo(view.code_buf)
	view:sync()
	vim.wait(30)
	check(cells(view) == "code:print('A')|code:print('B')", "F4 redo restores the pasted cell")
	check(aligned(view), "F4 buffers aligned after redo")
end

-- Flow 5: move a cell, undo restores the original order (and keeps outputs).
do
	local view = make_view({ "print('A')", "print('B')", "print('C')" })
	install_executer(view)
	gotocell(view, 3)
	undo_break(view)
	view.controller:execute_current_cell()
	vim.wait(80)

	gotocell(view, 3)
	undo_break(view)
	view.controller:move_cell_above()
	vim.wait(30)
	check(cells(view) == "code:print('A')|code:print('C')|code:print('B')", "F5 move above reorders cells")

	undo_break(view)
	helpers.undo(view.code_buf)
	view:sync()
	vim.wait(30)
	check(cells(view) == "code:print('A')|code:print('B')|code:print('C')", "F5 undo restores original order")
	check(#view.notebook.cells[3].outputs == 1, "F5 moved cell keeps output after undo")
end

-- Flow 6: undo/redo at boundaries must be no-ops without errors.
do
	local view = make_view({ "print('A')" })
	check(view:line_count() >= 1, "F6 view opened")
	local ok = pcall(helpers.undo, view.code_buf)
	check(ok, "F6 undo at initial state does not error")
	view:sync()
	check(cells(view) == "code:print('A')", "F6 no-op undo keeps cells")
	local ok2 = pcall(helpers.redo, view.code_buf)
	check(ok2, "F6 redo at latest state does not error")
end

-- Flow 7: undo, then a new edit, must discard the redo branch.
do
	local view = make_view({ "print('A')" })
	gotocell(view, 1)
	undo_break(view)
	view.controller:copy_cell()
	undo_break(view)
	view.controller:paste_cell()
	vim.wait(30)
	check(cells(view) == "code:print('A')|code:print('A')", "F7 paste once")

	undo_break(view)
	helpers.undo(view.code_buf)
	view:sync()
	vim.wait(30)
	check(cells(view) == "code:print('A')", "F7 undo removes pasted cell")

	-- New edit: paste again (a different cell).
	undo_break(view)
	view.controller:paste_cell()
	vim.wait(30)
	check(cells(view) == "code:print('A')|code:print('A')", "F7 new paste after undo")

	-- Redo must NOT resurrect the first pasted cell.
	undo_break(view)
	helpers.redo(view.code_buf)
	view:sync()
	vim.wait(30)
	check(cells(view) == "code:print('A')|code:print('A')", "F7 redo branch discarded after new edit")
	check(aligned(view), "F7 buffers aligned")
end

-- Flow 8: delete the last remaining cell, then undo.
do
	local view = make_view({ "print('A')" })
	undo_break(view)
	view.controller:delete_cell()
	vim.wait(30)
	check(#view.notebook.cells == 0, "F8 deleting the only cell leaves an empty notebook")
	check(aligned(view), "F8 buffers aligned after deleting all cells")

	undo_break(view)
	helpers.undo(view.code_buf)
	view:sync()
	vim.wait(30)
	check(cells(view) == "code:print('A')", "F8 undo restores the only cell")
end

-- Flow 9: markdown cell created by editing the marker line, then undo reverts it.
do
	local view = make_view({ "print('A')" })
	local id = view.notebook.cells[1].metadata.id
	-- Rewrite the marker as a markdown cell (like a user would by editing it).
	local lines = vim.api.nvim_buf_get_lines(view.code_buf, 0, -1, false)
	for i, l in ipairs(lines) do
		if l:match("^# %%%% %[code:") then
			lines[i] = "# %% [markdown:" .. id .. "]"
		end
	end
	vim.api.nvim_buf_set_lines(view.code_buf, 0, -1, false, lines)
	undo_break(view)
	view:sync()
	vim.wait(30)
	check(view.notebook.cells[1].cell_type == "markdown", "F9 marker edit produces a markdown cell")
	check(view.notebook.cells[1].source == "print('A')", "F9 markdown cell keeps source text")

	undo_break(view)
	helpers.undo(view.code_buf)
	view:sync()
	vim.wait(30)
	check(view.notebook.cells[1].cell_type == "code", "F9 undo reverts the cell to code")
end

-- Flow 10: save -> parse roundtrip preserves sources and outputs.
do
	local view = make_view({ "print('A')", "print('B')" })
	install_executer(view)
	-- Write into the platform temp dir, never the working tree.
	view.path = vim.fn.tempname() .. ".ipynb"
	gotocell(view, 1)
	undo_break(view)
	view.controller:execute_current_cell()
	vim.wait(80)
	view.controller:save()
	vim.wait(30)

	local ok, raw = pcall(io.open, view.path, "r")
	check(ok, "F10 saved notebook file exists")
	local json
	if ok and raw then
		json = raw:read("a")
		raw:close()
		os.remove(view.path)
	end
	local parsed = json and IpynbParser.parse(json)
	check(parsed ~= nil, "F10 saved file parses as a notebook")
	if parsed then
		check(#parsed.cells == 2, "F10 roundtrip keeps cell count")
		check(
			parsed.cells[1].source == "print('A')" and parsed.cells[2].source == "print('B')",
			"F10 roundtrip keeps sources"
		)
		check(#parsed.cells[1].outputs == 1, "F10 roundtrip keeps outputs")
		check(
			parsed.cells[1].outputs[1].text == "out[" .. view.notebook.cells[1].metadata.id .. "]\n",
			"F10 roundtrip keeps output text"
		)
	end
end

-- Flow 11: the whole long flow — create, execute, delete, undo, paste x2,
-- execute second, undo, redo — all consistent at the end.
do
	local view = make_view({ "print('A')", "print('B')" })
	install_executer(view)
	check(aligned(view), "F11 initial aligned")

	-- create an empty cell
	gotocell(view, 1)
	undo_break(view)
	view.controller:create_cell()
	vim.wait(30)
	check(cells(view) == "code:print('A')|code:|code:print('B')", "F11 created cell")

	-- execute the created (empty) cell
	gotocell(view, 2)
	undo_break(view)
	view.controller:execute_current_cell()
	vim.wait(80)
	check(#view.notebook.cells[2].outputs == 1, "F11 executed created cell")

	-- delete it and undo
	undo_break(view)
	view.controller:delete_cell()
	vim.wait(30)
	check(cells(view) == "code:print('A')|code:print('B')", "F11 deleted created cell")
	undo_break(view)
	helpers.undo(view.code_buf)
	view:sync()
	vim.wait(30)
	check(cells(view) == "code:print('A')|code:|code:print('B')", "F11 undo restores created cell with output")
	check(#view.notebook.cells[2].outputs == 1, "F11 restored cell keeps output")

	-- paste twice, execute the second pasted cell
	gotocell(view, 1)
	undo_break(view)
	view.controller:copy_cell()
	undo_break(view)
	view.controller:paste_cell()
	undo_break(view)
	view.controller:paste_cell()
	vim.wait(30)
	gotocell(view, 3)
	undo_break(view)
	view.controller:execute_current_cell()
	vim.wait(80)
	check(#view.notebook.cells[3].outputs == 1, "F11 executed second pasted cell")

	-- undo removes the last pasted cell; redo brings it back with output
	undo_break(view)
	helpers.undo(view.code_buf)
	view:sync()
	vim.wait(30)
	undo_break(view)
	helpers.redo(view.code_buf)
	view:sync()
	vim.wait(30)
	check(
		cells(view) == "code:print('A')|code:print('A')|code:print('A')|code:|code:print('B')",
		"F11 redo restores last pasted cell"
	)
	check(#view.notebook.cells[3].outputs == 1, "F11 redone cell keeps output")
	check(aligned(view), "F11 final buffers aligned")
end
