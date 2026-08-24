---@diagnostic disable:undefined-field,undefined-doc-name

---@class ExecutionProgressPayload
---@field type "stream" | "display_data" | "execute_result" | "error" | "clear"
---@field name? "stdout" | "stderr"
---@field text? string
---@field data? table<string, string>
---@field metadata? table
---@field execution_count? integer
---@field ename? string
---@field evalue? string
---@field traceback? string[]
---@field wait? boolean

---@class ExecutionProgressDispatcher
---@field on_start? fun()
---@field on_progress? fun(output: ExecutionProgressPayload)
---@field on_done? fun(status: "ok" | "error" | "abort", execution_count: integer?)

---@class ICommandExecuter
---@field execute fun(self: ICommandExecuter, code: string, dispatcher: ExecutionProgressDispatcher): string

---@class PendingExecution
---@field dispatcher ExecutionProgressDispatcher
---@field final_status? "ok" | "error" | "abort"
---@field execution_count? integer
---@field is_idle? boolean

---@class CommandExecuter : ICommandExecuter
---@field session WebSocketSession
---@field session_id string
---@field pending table<string, PendingExecution>
---@field warned table<string, boolean>
local CommandExecuter = {}
CommandExecuter.__index = CommandExecuter

---@param session WebSocketSession
---@return CommandExecuter
function CommandExecuter.new(session)
	local self = setmetatable({}, CommandExecuter)
	self.session = session
	self.session_id = vim.fn.sha256(tostring(vim.uv.hrtime())):sub(1, 16)
	self.pending = {}
	self.warned = {}
	return self
end

---@param code string
---@param dispatcher ExecutionProgressDispatcher
---@return string msg_id
function CommandExecuter:execute(code, dispatcher)
	local msg_id = vim.fn.sha256(tostring(vim.uv.hrtime()) .. tostring(math.random(1, 1000000))):sub(1, 16)

	local pending_exec = {
		dispatcher = dispatcher,
	}
	self.pending[msg_id] = pending_exec

	local req = {
		channel = "shell",
		header = {
			msg_id = msg_id,
			msg_type = "execute_request",
			session = self.session_id,
			username = "nvim",
			date = os.date("!%Y-%m-%dT%H:%M:%SZ"),
			version = "5.3",
		},
		parent_header = vim.empty_dict(),
		metadata = vim.empty_dict(),
		content = {
			code = code,
			silent = false,
			store_history = false,
			user_expressions = vim.empty_dict(),
			allow_stdin = false,
			stop_on_error = true,
		},
	}

	self.session:send(vim.json.encode(req))
	return msg_id
end

---@private Map a message type to the progress payload it carries.
---@type table<string, fun(content: table): ExecutionProgressPayload>
local PROGRESS_BUILDERS = {
	stream = function(content)
		return { type = "stream", name = content.name, text = content.text }
	end,
	display_data = function(content)
		return { type = "display_data", data = content.data, metadata = content.metadata }
	end,
	execute_result = function(content)
		return {
			type = "execute_result",
			data = content.data,
			metadata = content.metadata,
			execution_count = content.execution_count,
		}
	end,
	error = function(content)
		return {
			type = "error",
			ename = content.ename,
			evalue = content.evalue,
			traceback = content.traceback,
		}
	end,
	clear_output = function(content)
		return { type = "clear", wait = content.wait }
	end,
}

---@param raw_json string
function CommandExecuter:handle_message(raw_json)
	local ok, msg = pcall(vim.json.decode, raw_json)
	if not ok then
		self:_warn("Received undecodable kernel message: " .. tostring(msg))
		return
	end
	if type(msg) ~= "table" or not msg.parent_header then
		return
	end

	local parent_id = msg.parent_header.msg_id
	if not parent_id then
		return
	end

	local pending_exec = self.pending[parent_id]
	if not pending_exec then
		return
	end

	local dispatcher = pending_exec.dispatcher
	local header = msg.header or {}
	local msg_type = header.msg_type
	local content = msg.content or {}

	if msg_type == "execute_reply" then
		pending_exec.final_status = content.status
		pending_exec.execution_count = content.execution_count
		if pending_exec.is_idle then
			self:_finish(parent_id, pending_exec, pending_exec.final_status, pending_exec.execution_count)
		end
	elseif msg_type == "status" and content.execution_state == "idle" then
		pending_exec.is_idle = true
		if pending_exec.final_status then
			self:_finish(parent_id, pending_exec, pending_exec.final_status, pending_exec.execution_count)
		end
	elseif msg_type == "execute_input" then
		if dispatcher.on_start then
			dispatcher.on_start()
		end
	elseif dispatcher.on_progress then
		local builder = PROGRESS_BUILDERS[msg_type]
		if builder then
			dispatcher.on_progress(builder(content))
		end
	end
end

---@private Warn once per message so a misbehaving kernel doesn't spam.
---@param msg string
function CommandExecuter:_warn(msg)
	if self.warned[msg] then
		return
	end
	self.warned[msg] = true
	vim.notify("[notebook.nvim] " .. msg, vim.log.levels.WARN)
end

---@private
---@param parent_id string
---@param pending_exec PendingExecution
---@param status "ok" | "error" | "abort"
---@param execution_count integer?
function CommandExecuter:_finish(parent_id, pending_exec, status, execution_count)
	self.pending[parent_id] = nil
	if pending_exec.dispatcher.on_done then
		pending_exec.dispatcher.on_done(status, execution_count)
	end
end

return CommandExecuter
