local HTTPClient = require("notebook.connection.http.client")

---@class KernelProvisioner
---@field host string
---@field port integer
---@field token? string
---@field kernel_name? string
---@field http_client HttpClient
---@field kernel_id? string
---@field retry_timeout_ms integer
---@field retry_base_ms integer
---@field retry_max_ms integer
local KernelProvisioner = {}
KernelProvisioner.__index = KernelProvisioner

---@param host string
---@param port integer
---@param token? string
---@param kernel_name? string
---@param opts? { timeout_ms?: integer, base_ms?: integer, max_ms?: integer }
---@return KernelProvisioner
function KernelProvisioner.new(host, port, token, kernel_name, opts)
	opts = opts or {}
	local self = setmetatable({}, KernelProvisioner)
	self.host = host
	self.port = port
	self.token = token
	self.kernel_name = kernel_name
	self.http_client = HTTPClient.new(host, port)
	self.retry_timeout_ms = opts.timeout_ms or 10000
	self.retry_base_ms = opts.base_ms or 50
	self.retry_max_ms = opts.max_ms or 1000
	return self
end

---@private Always send the token query, even for an empty token (because of old jupyter server versions)
---@return string
function KernelProvisioner:query()
	return "?token=" .. (self.token or "")
end

---@param path string
---@return string
function KernelProvisioner:with_query(path)
	return path .. self:query()
end

---@param on_done fun(err: string?, kernel_id: string?)
function KernelProvisioner:provision(on_done)
	local body = vim.json.encode({ name = self.kernel_name })
	local path = self:with_query("/api/kernels")

	self:_request_with_retry("POST", path, body, function(err, res)
		if err or not res or res.status ~= 201 then
			local detail = res and res.body or err
			return on_done("Failed to provision kernel: " .. tostring(detail))
		end

		local ok, kernel_info = pcall(vim.json.decode, res.body)
		if not ok or not kernel_info.id then
			return on_done("Invalid JSON response from kernel provision API")
		end

		self.kernel_id = kernel_info.id
		on_done(nil, self.kernel_id)
	end)
end

---@param on_done? fun(err: string?)
function KernelProvisioner:interrupt(on_done)
	self:_kernel_action("interrupt", on_done)
end

---@param on_done? fun(err: string?)
function KernelProvisioner:restart(on_done)
	self:_kernel_action("restart", on_done)
end

---@param on_done? fun()
function KernelProvisioner:shutdown(on_done)
	local kernel_id = self.kernel_id
	if not kernel_id then
		if on_done then
			on_done()
		end
		return
	end

	local path = self:with_query(string.format("/api/kernels/%s", kernel_id))
	self.http_client:request("DELETE", path, nil, function()
		if on_done then
			on_done()
		end
	end)
end

---@private
---@param action string
---@param on_done? fun(err: string?)
function KernelProvisioner:_kernel_action(action, on_done)
	local kernel_id = self.kernel_id
	if not kernel_id then
		if on_done then
			on_done("No kernel provisioned")
		end
		return
	end

	local path = self:with_query(string.format("/api/kernels/%s/%s", kernel_id, action))
	self.http_client:request("POST", path, nil, function(err)
		if on_done then
			on_done(err)
		end
	end)
end

---@private
---@param method "GET" | "POST" | "DELETE"
---@param path string
---@param body? string
---@param on_done fun(err: string?, res: HttpResponse?)
function KernelProvisioner:_request_with_retry(method, path, body, on_done)
	local start = vim.uv.hrtime()
	local attempt = 0

	local function try_once()
		attempt = attempt + 1
		self.http_client:request(method, path, body, function(err, res, err_code)
			local elapsed = vim.uv.hrtime() - start
			local transient = err_code == "ECONNREFUSED" or (res and res.status >= 500)
			if transient and elapsed < self.retry_timeout_ms * 1e6 then
				local delay = math.min(self.retry_base_ms * 2 ^ (attempt - 1), self.retry_max_ms)
				vim.defer_fn(try_once, delay)
			else
				on_done(err, res)
			end
		end)
	end

	try_once()
end

return KernelProvisioner
