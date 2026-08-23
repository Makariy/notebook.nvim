local ServerProcess = require("notebook.kernel.server_process")
local KernelProvisioner = require("notebook.kernel.provisioner")
local TCPTransport = require("notebook.connection.websocket.transport")
local WSSession = require("notebook.connection.websocket.session")

---@class KernelOptions
---@field spawn boolean Spawn a kernel or connect to an existing one
---@field host? string Default "127.0.0.1"
---@field port? integer If nil, a free port is chosen
---@field token? string
---@field kernel_name? string Default "python3"
---@field cwd? string
---@field python? string Path to the python executable (defaults to "python" on PATH; the user is expected to have their environment active)
---@field on_disconnect? fun() Called when the kernel websocket closes unexpectedly

---@class IKernelManager
---@field start fun(self: IKernelManager, on_ready: fun(err: string?, session: WebSocketSession?))
---@field interrupt fun(self: IKernelManager, on_done?: fun(err: string?))
---@field restart fun(self: IKernelManager, on_done?: fun(err: string?))
---@field shutdown fun(self: IKernelManager, on_done?: fun())

---@class KernelManager : IKernelManager
---@field options KernelOptions
---@field server? ServerProcess
---@field provisioner? KernelProvisioner
---@field session? WebSocketSession
---@field closed boolean
local KernelManager = {}
KernelManager.__index = KernelManager

---@param options? KernelOptions
---@return KernelManager
function KernelManager.new(options)
	local self = setmetatable({}, KernelManager)
	self.options = vim.tbl_deep_extend("force", {
		host = "127.0.0.1",
		kernel_name = "python3",
		spawn = true,
	}, options or {})
	self.closed = false

	if self.options.spawn then
		self.server = ServerProcess.new()
	end

	return self
end

---@param on_ready fun(err: string?, session: WebSocketSession?)
function KernelManager:start(on_ready)
	if self.options.spawn then
		self.server:spawn({
			host = self.options.host,
			port = self.options.port,
			cwd = self.options.cwd,
			token = self.options.token,
			python = self.options.python,
		}, function(spawn_err, bound_port)
			if spawn_err or not bound_port then
				return on_ready(spawn_err or "Server failed to start", nil)
			end

			self:_provision_and_connect(bound_port, on_ready)
		end)
	else
		if not self.options.host or not self.options.port then
			return on_ready("host and port are required to connect to an existing kernel", nil)
		end

		self:_provision_and_connect(self.options.port, on_ready)
	end
end

---@private
---@param port integer
---@param on_ready fun(err: string?, session: WebSocketSession?)
function KernelManager:_provision_and_connect(port, on_ready)
	self.provisioner = KernelProvisioner.new(self.options.host, port, self.options.token, self.options.kernel_name)

	self.provisioner:provision(function(err, kernel_id)
		if err then
			return on_ready(err, nil)
		end

		local transport = TCPTransport.new()
		self.session = WSSession.new(transport)

		local ws_path = self.provisioner:with_query(string.format("/api/kernels/%s/channels", kernel_id))

		self.session:connect(
			self.options.host,
			port,
			ws_path,
			function()
				on_ready(nil, self.session)
			end,
			nil,
			function()
				if not self.closed and self.options.on_disconnect then
					self.options.on_disconnect()
				end
			end,
			function(err_msg)
				on_ready(err_msg, nil)
			end
		)
	end)
end

---@param on_done? fun(err: string?)
function KernelManager:interrupt(on_done)
	if not self.provisioner then
		if on_done then
			on_done("Kernel not started")
		end
		return
	end
	self.provisioner:interrupt(on_done)
end

---@param on_done? fun(err: string?)
function KernelManager:restart(on_done)
	if not self.provisioner then
		if on_done then
			on_done("Kernel not started")
		end
		return
	end
	self.provisioner:restart(on_done)
end

---@param on_done? fun()
function KernelManager:shutdown(on_done)
	self.closed = true

	if self.session then
		self.session:close()
	end

	local function cleanup()
		if self.server then
			self.server:stop()
		end
		if on_done then
			on_done()
		end
	end

	if self.provisioner and self.provisioner.kernel_id then
		self.provisioner:shutdown(function()
			cleanup()
		end)
	else
		cleanup()
	end
end

return KernelManager
