local Cell = require("notebook.notebook.cell")
local codec = require("notebook.ui.codec")
local CellClipboard = require("notebook.ui.cell_clipboard")
local Saver = require("notebook.ui.notebook_saver")
local KernelActions = require("notebook.ui.kernel_actions")

---@class NotebookController
---@field view INotebookView
---@field session NotebookSession
---@field clipboard CellClipboard
---@field kernel KernelActions
local NotebookController = {}
NotebookController.__index = NotebookController

---@param view INotebookView
---@param session NotebookSession
function NotebookController.new(view, session)
	local self = setmetatable({}, NotebookController)
	self.view = view
	self.session = session
	self.clipboard = CellClipboard.new()
	self.kernel = KernelActions.new(session, view.execution_state, function()
		view:render()
	end)
	return self
end

function NotebookController:create_cell()
	self.view:sync()
	local current = self.view:get_current_cell_index()
	self.view.notebook:insert(Cell.code(""), current + 1)
	self.view:render()
end

function NotebookController:delete_cell()
	self.view:sync()
	local current = self.view:get_current_cell_index()
	local cell = self.view.notebook.cells[current]
	if cell then
		self.view:retire_cell(cell)
	end
	self.session:delete_cell(current)
	self.view:render()
end

function NotebookController:copy_cell()
	self.view:sync()
	local cell = self.view.notebook:get(self.view:get_current_cell_index())
	if not cell then
		return
	end

	self.clipboard:copy(cell)
	vim.notify("Cell copied", vim.log.levels.INFO)
end

function NotebookController:toggle_cell_output()
	self.view:sync()
	local cell = self.view.notebook:get(self.view:get_current_cell_index())
	if not cell or not cell:is_code() or not cell.metadata.id then
		return
	end
	self.view:toggle_cell_output(cell.metadata.id)
	self.view:render()
end

function NotebookController:toggle_outputs()
	self.view:sync()
	self.view:toggle_all_outputs()
	self.view:render()
end

function NotebookController:toggle_cell_type()
	self.view:sync()
	local cell = self.view.notebook:get(self.view:get_current_cell_index())
	if not cell then
		return
	end

	if cell.cell_type == "markdown" then
		cell.cell_type = "code"
	else
		cell.cell_type = "markdown"
	end
	self.view:render()
end

function NotebookController:cut_cell()
	self:copy_cell()
	self:delete_cell()
end

function NotebookController:paste_cell()
	if self.clipboard:empty() then
		vim.notify("Notebook clipboard is empty", vim.log.levels.WARN)
		return
	end

	self.view:sync()
	local current = self.view:get_current_cell_index()
	local cell = self.clipboard:paste()
	if not cell then
		return
	end
	self.view.notebook:insert(cell, current + 1)
	self.view:render()
end

function NotebookController:move_cell_above()
	self:move_cell(-1)
end

function NotebookController:move_cell_below()
	self:move_cell(1)
end

---@private
---@param delta -1 | 1
function NotebookController:move_cell(delta)
	local view = self.view
	view:sync()

	local current = view:get_current_cell_index()
	local target = current + delta
	if target < 1 or target > #view.notebook.cells then
		return
	end

	local cursor = view:get_cursor()
	local start_row = view:get_cell_start(current) or 0
	local relative_row = cursor[1] - 1 - start_row

	local cell = view.notebook:remove(current)
	if not cell then
		return
	end
	view.notebook:insert(cell, target)
	view:render()

	local new_start = view:get_cell_start(target)
	if new_start then
		local count = view:line_count()
		view:set_cursor(math.min(new_start + relative_row + 1, count), cursor[2])
	end
end

function NotebookController:execute_current_cell()
	self.view:sync()
	self:execute_cells({ self.view:get_current_cell_index() })
end

function NotebookController:execute_all()
	self.view:sync()
	self:execute_cells(self:_range(1, #self.view.notebook.cells))
end

function NotebookController:execute_above()
	self.view:sync()
	local current = self.view:get_current_cell_index()
	self:execute_cells(self:_range(1, current))
end

function NotebookController:execute_below()
	self.view:sync()
	local current = self.view:get_current_cell_index()
	self:execute_cells(self:_range(current, #self.view.notebook.cells))
end

---@private
---@param from integer
---@param to integer
---@return integer[]
function NotebookController:_range(from, to)
	local indices = {}
	for i = from, to do
		table.insert(indices, i)
	end
	return indices
end

---@param indices integer[]
function NotebookController:execute_cells(indices)
	local view = self.view
	codec.ensure_ids(view.notebook)

	for _, i in ipairs(indices) do
		local cell = view.notebook.cells[i]
		if cell and cell.cell_type == "code" then
			view.execution_state:set_busy(cell.metadata.id)
			cell:clear_outputs()
		end
	end
	view:render()

	self.kernel:ensure_running(function(err)
		if err then
			return
		end
		for _, i in ipairs(indices) do
			self.session:execute_cell(i)
		end
	end)
end

function NotebookController:save()
	self.view:sync()

	if Saver.save(self.view.path, self.view.notebook) then
		self.view:mark_saved()
	end
end

---@param pane string?
function NotebookController:focus(pane)
	if pane == nil or pane == "" then
		pane = self.view:current_pane()
	end
	self.view.focus_mode:toggle(pane)
end

function NotebookController:start_kernel()
	self.kernel:start()
end

function NotebookController:kernel_restart()
	self.kernel:restart()
end

function NotebookController:kernel_interrupt()
	self.kernel:interrupt()
end

function NotebookController:kernel_shutdown()
	self.kernel:shutdown()
end

function NotebookController:split_cell()
	local view = self.view
	view:sync()
	local current = view:get_current_cell_index()
	local cell = view.notebook:get(current)
	if not cell then
		return
	end

	local cursor = view:get_cursor()
	local row = cursor[1] - 1 -- 0-based
	local cell_start = view:get_cell_start(current) or 0

	if row <= cell_start then
		vim.notify("Cannot split at the cell marker", vim.log.levels.WARN)
		return
	end

	local source_lines = codec.split_source(cell.source)
	local relative_row = row - cell_start

	if relative_row > #source_lines then
		relative_row = #source_lines + 1
	end

	local first_source = {}
	local second_source = {}

	for i, line in ipairs(source_lines) do
		if i < relative_row then
			table.insert(first_source, line)
		else
			table.insert(second_source, line)
		end
	end

	cell.source = table.concat(first_source, "\n")
	local new_cell = Cell.new({
		cell_type = cell.cell_type,
		source = table.concat(second_source, "\n"),
		metadata = { id = Cell.generate_id() },
	})

	view.notebook:insert(new_cell, current + 1)
	view:render()

	local new_start = view:get_cell_start(current + 1)
	if new_start then
		view:set_cursor(new_start + 1, 0)
	end
end

function NotebookController:goto_error()
	local view = self.view
	view:sync()
	for i, cell in ipairs(view.notebook.cells) do
		if cell.metadata.id then
			local entry = view.execution_state:get(cell.metadata.id)
			if entry and entry.state == "error" then
				local cell_start = view:get_cell_start(i)
				if cell_start then
					view:set_cursor(cell_start + 1, 0)
					return
				end
			end
		end
	end
	vim.notify("No errored cell found", vim.log.levels.INFO)
end

function NotebookController:goto_running()
	local view = self.view
	view:sync()
	for i, cell in ipairs(view.notebook.cells) do
		if cell.metadata.id then
			local entry = view.execution_state:get(cell.metadata.id)
			if entry and entry.state == "busy" then
				local cell_start = view:get_cell_start(i)
				if cell_start then
					view:set_cursor(cell_start + 1, 0)
					return
				end
			end
		end
	end
	vim.notify("No running cell found", vim.log.levels.INFO)
end

function NotebookController:join_cell()
	local view = self.view
	view:sync()
	local current = view:get_current_cell_index()
	local cell = view.notebook:get(current)
	local next_cell = view.notebook:get(current + 1)

	if not cell or not next_cell then
		vim.notify("No cell below to join with", vim.log.levels.WARN)
		return
	end

	if cell.cell_type ~= next_cell.cell_type then
		vim.notify("Cannot join cells of different types", vim.log.levels.WARN)
		return
	end

	local s1 = cell.source or ""
	local s2 = next_cell.source or ""
	if s1 ~= "" and s2 ~= "" then
		cell.source = s1 .. "\n" .. s2
	else
		cell.source = s1 .. s2
	end

	view.notebook:remove(current + 1)
	view:render()
end
return NotebookController
