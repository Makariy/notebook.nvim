---@class KernelActions
---@field session NotebookSession
---@field execution_state ExecutionState
---@field on_state_changed fun()
local KernelActions = {}
KernelActions.__index = KernelActions

---@param session NotebookSession
---@param execution_state ExecutionState
---@param on_state_changed fun()
function KernelActions.new(session, execution_state, on_state_changed)
	return setmetatable({
		session = session,
		execution_state = execution_state,
		on_state_changed = on_state_changed,
	}, KernelActions)
end

---@param on_ready fun(err: string?)
function KernelActions:ensure_running(on_ready)
	if self.session.command_executer then
		return on_ready(nil)
	end

	vim.notify("Starting Kernel...", vim.log.levels.INFO)
	self.session:start(function(err)
		if err then
			vim.notify("Kernel error: " .. err, vim.log.levels.ERROR)
			return
		end
		vim.notify("Kernel started", vim.log.levels.INFO)
		on_ready(nil)
	end)
end

function KernelActions:start()
	if self.session.command_executer then
		vim.notify("Kernel is already running", vim.log.levels.INFO)
		return
	end
	self:ensure_running(function() end)
end

function KernelActions:restart()
	vim.notify("Restarting Kernel...", vim.log.levels.INFO)
	self.session:restart(function(err)
		if err then
			vim.notify("Kernel restart error: " .. err, vim.log.levels.ERROR)
		else
			vim.notify("Kernel restarted", vim.log.levels.INFO)
			self:_clear_busy()
		end
	end)
end

function KernelActions:interrupt()
	vim.notify("Interrupting Kernel...", vim.log.levels.INFO)
	self.session:interrupt(function(err)
		if err then
			vim.notify("Kernel interrupt error: " .. err, vim.log.levels.ERROR)
		else
			vim.notify("Kernel interrupted", vim.log.levels.INFO)
			self:_clear_busy()
		end
	end)
end

function KernelActions:shutdown()
	vim.notify("Shutting down Kernel...", vim.log.levels.INFO)
	self.session:shutdown(function()
		vim.notify("Kernel shut down", vim.log.levels.INFO)
		self:_clear_busy()
	end)
end

---@private
function KernelActions:_clear_busy()
	if self.execution_state:set_error_busy() then
		self.on_state_changed()
	end
end

return KernelActions
