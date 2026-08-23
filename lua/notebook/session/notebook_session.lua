local KernelManager = require("notebook.kernel.kernel_manager")
local CommandExecuter = require("notebook.execution.executer")
local Cell = require("notebook.notebook.cell")
local Listeners = require("notebook.session.listeners")
local InFlight = require("notebook.session.in_flight")
local OutputFactory = require("notebook.session.output_factory")

---@class SessionListener
---@field on_progress? fun(cell_id: string, output: CellOutput)
---@field on_done? fun(cell_id: string, status: "ok" | "error" | "abort", execution_count: integer?)
---@field on_changed? fun()

---@class INotebookSession
---@field start fun(self: INotebookSession, on_ready: fun(err: string?))
---@field execute_cell fun(self: INotebookSession, index: integer)
---@field delete_cell fun(self: INotebookSession, index: integer): Cell?
---@field interrupt fun(self: INotebookSession, on_done?: fun(err: string?))
---@field restart fun(self: INotebookSession, on_done?: fun(err: string?))
---@field shutdown fun(self: INotebookSession, on_done?: fun())
---@field subscribe fun(self: INotebookSession, listener: SessionListener)

---@class NotebookSession : INotebookSession
---@field notebook Notebook
---@field kernel_manager KernelManager
---@field command_executer? ICommandExecuter
---@field listeners Listeners
---@field in_flight InFlight
local NotebookSession = {}
NotebookSession.__index = NotebookSession

---@param notebook Notebook
---@param kernel_options? KernelOptions
---@return NotebookSession
function NotebookSession.new(notebook, kernel_options)
	local self = setmetatable({}, NotebookSession)
	self.notebook = notebook
	self.kernel_manager = KernelManager.new(kernel_options)
	self.listeners = Listeners.new()
	self.in_flight = InFlight.new()
	return self
end

---@param on_ready fun(err: string?)
function NotebookSession:start(on_ready)
	self.kernel_manager:start(function(err, ws_session)
		if err then
			return on_ready(err)
		end

		local executer = CommandExecuter.new(ws_session)
		self.command_executer = executer
		ws_session.on_message = function(msg)
			executer:handle_message(msg)
		end

		on_ready(nil)
	end)
end

---@param listener SessionListener
function NotebookSession:subscribe(listener)
	self.listeners:add(listener)
end

---@param index integer
function NotebookSession:execute_cell(index)
	if not self.command_executer then
		vim.notify("NotebookSession is not started", vim.log.levels.ERROR)
		return
	end

	local cell = self.notebook:get(index)
	if not cell or not cell:is_code() then
		return
	end

	if not cell.metadata.id then
		cell.metadata.id = Cell.generate_id()
	end
	local cell_id = cell.metadata.id

	cell:clear_outputs()

	-- Re-executing a cell supersedes any in-flight execution of the same cell:
	-- stale progress/done callbacks are ignored so outputs are not duplicated.
	local msg_id
	msg_id = self.command_executer:execute(cell.source, {
		on_progress = function(payload)
			if not self.in_flight:is_current(cell_id, msg_id) then
				return
			end
			self:_handle_progress(cell_id, cell, payload)
		end,
		on_done = function(status, count)
			if not self.in_flight:is_current(cell_id, msg_id) then
				return
			end
			self.in_flight:finish(cell_id)
			cell.execution_count = count
			self:_notify_done(cell_id, status, count)
		end,
	})
	self.in_flight:begin(cell_id, msg_id)
end

---@param index integer
---@return Cell?
function NotebookSession:delete_cell(index)
	local removed = self.notebook:remove(index)
	if removed then
		self.listeners:emit("on_changed")
	end
	return removed
end

---@param on_done? fun(err: string?)
function NotebookSession:interrupt(on_done)
	self.kernel_manager:interrupt(on_done)
end

---@param on_done? fun(err: string?)
function NotebookSession:restart(on_done)
	self.kernel_manager:restart(on_done)
end

---@param on_done? fun()
function NotebookSession:shutdown(on_done)
	self.command_executer = nil
	self.kernel_manager:shutdown(on_done)
end

---@private
---@param cell_id string
---@param cell Cell
---@param payload ExecutionProgressPayload
function NotebookSession:_handle_progress(cell_id, cell, payload)
	if payload.type == "clear" then
		cell:clear_outputs()
		self.in_flight:set_waiting(cell_id, payload.wait == true)
		self.listeners:emit("on_changed")
		return
	end

	local output = OutputFactory.from_progress(payload)
	if output then
		cell:add_output(output)
		if not self.in_flight:is_waiting(cell_id) then
			self.listeners:emit("on_progress", cell_id, output)
		end
	end
end

---@param cell_id string
---@param status "ok" | "error" | "abort"
---@param execution_count integer?
function NotebookSession:_notify_done(cell_id, status, execution_count)
	self.listeners:emit("on_done", cell_id, status, execution_count)
end

return NotebookSession
