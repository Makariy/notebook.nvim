---@diagnostic disable:undefined-field,undefined-doc-name

---@class ServerSpawnOptions
---@field host? string
---@field port? integer
---@field cwd? string
---@field token? string
---@field python? string Path to the python executable (defaults to "python" on PATH)
---@field timeout_ms? integer

---@class ServerProcess
---@field handle? uv.uv_process_t
---@field stdout? uv.uv_pipe_t
---@field stderr? uv.uv_pipe_t
---@field port? integer
---@field is_ready boolean
---@field autocmd_id? integer
---@field _output string Captured process output (stdout/stderr)
---@field _python string The interpreter that was spawned
local ServerProcess = {}
ServerProcess.__index = ServerProcess

function ServerProcess.new()
	local self = setmetatable({}, ServerProcess)
	self.is_ready = false
	return self
end

---@private
---@return integer 0 when no free port could be found
local function find_free_port()
	local tcp = vim.uv.new_tcp()
	if not tcp then
		return 0
	end

	local ok = tcp:bind("127.0.0.1", 0)
	if type(ok) == "string" then
		tcp:close()
		return 0
	end

	local info = tcp:getsockname()
	tcp:close()
	return (info and info.port) or 0
end

---@param opts? ServerSpawnOptions
---@param on_ready fun(err: string?, port: integer?)
function ServerProcess:spawn(opts, on_ready)
	self.is_ready = false
	self.port = nil
	self._output = ""
	opts = opts or {}

	local host = opts.host or "127.0.0.1"
	local timeout_ms = opts.timeout_ms or 30000
	local python = opts.python or "python"
	self._python = python

	local stdout = vim.uv.new_pipe(false)
	local stderr = vim.uv.new_pipe(false)
	if not stdout or not stderr then
		error("Could not create stdout/stderr pipes")
	end

	local settled = false
	local function settle(err, port)
		if settled then
			return
		end
		settled = true
		self:_stop_timer()
		vim.schedule(function()
			on_ready(err, port)
		end)
	end

	local target_port = opts.port
	if not target_port or target_port == 0 then
		target_port = find_free_port()
	end
	if not target_port or target_port == 0 then
		stdout:close()
		stderr:close()
		settle("Could not find a free port for the jupyter server", nil)
		return
	end

	self._ready_timer = vim.uv.new_timer()
	self._ready_timer:start(timeout_ms, 0, function()
		settle(string.format("Jupyter server did not become ready within %.0fs", timeout_ms / 1000), nil)
		self:stop()
	end)

	local args = {
		"-m",
		"jupyter",
		"server",
		string.format("--ServerApp.ip=%s", host),
		string.format("--ServerApp.port=%d", target_port),
		"--ServerApp.port_retries=0",
		"--ServerApp.open_browser=False",
		"--IdentityProvider.token=" .. (opts.token or ""),
		"--ServerApp.disable_check_xsrf=True",
	}

	local handle, spawn_err = vim.uv.spawn(python, {
		args = args,
		cwd = opts.cwd or vim.fn.getcwd(),
		stdio = { nil, stdout, stderr },
	}, function()
		if not self.is_ready then
			settle(self:_exit_error(), nil)
		end
		self:stop()
	end)

	if not handle then
		stdout:close()
		stderr:close()
		settle(
			string.format(
				"Could not run python '%s': %s. Activate the environment that provides jupyter server, or set opts.python.",
				python,
				tostring(spawn_err)
			),
			nil
		)
		return
	end

	self.handle = handle
	self.stdout = stdout
	self.stderr = stderr

	local function parse_output(_, data)
		if self.is_ready or not data then
			return
		end
		self._output = self._output .. data

		local port_str = self._output:match("http://[%w%.%-_]+:(%d+)/")
		local port = port_str and tonumber(port_str)
		if port and port > 0 then
			self.is_ready = true
			self.port = port
			settle(nil, self.port)
		end
	end

	stdout:read_start(parse_output)
	stderr:read_start(parse_output)

	self.autocmd_id = vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			self:stop()
		end,
		once = true,
	})
end

---@private
---@return string
function ServerProcess:_exit_error()
	local out = self._output or ""
	if out:find("No module named", 1, true) then
		return string.format(
			"python '%s' could not import the jupyter server module. Install 'jupyter server' in the active environment, or set opts.python.",
			self._python or "python"
		)
	end
	return "Jupyter server exited before becoming ready"
end

function ServerProcess:stop()
	self:_stop_timer()

	if self.stdout and not self.stdout:is_closing() then
		self.stdout:close()
	end
	if self.stderr and not self.stderr:is_closing() then
		self.stderr:close()
	end
	if self.handle and not self.handle:is_closing() then
		self.handle:kill(15)
		self.handle:close()
		self.handle = nil
	end
	if self.autocmd_id then
		local id = self.autocmd_id
		self.autocmd_id = nil
		vim.schedule(function()
			pcall(vim.api.nvim_del_autocmd, id)
		end)
	end
end

---@private
function ServerProcess:_stop_timer()
	if self._ready_timer then
		if not self._ready_timer:is_closing() then
			self._ready_timer:stop()
			self._ready_timer:close()
		end
		self._ready_timer = nil
	end
end

return ServerProcess
