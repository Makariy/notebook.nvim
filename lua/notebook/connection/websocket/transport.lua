---@diagnostic disable:undefined-field,undefined-doc-name

---@class ITransport
---@field connect fun(self: ITransport, host: string, port: integer, on_ready: fun(err: string?))
---@field write fun(self: ITransport, data: string, on_flushed: fun(err: string?)?)
---@field read_start fun(self: ITransport, on_data: fun(err: string?, chunk: string?))
---@field close fun(self: ITransport)

---@class TCPTransport : ITransport
---@field tcp uv.uv_tcp_t
local TCPTransport = {}
TCPTransport.__index = TCPTransport

function TCPTransport.new()
	return setmetatable({ tcp = vim.uv.new_tcp() }, TCPTransport)
end

function TCPTransport:connect(host, port, on_ready)
	self.tcp:connect(host, port, function(err)
		if err then
			vim.schedule(function()
				on_ready(err)
			end)
		else
			vim.schedule(function()
				on_ready(nil)
			end)
		end
	end)
end

function TCPTransport:write(data, on_flushed)
	if not self.tcp:is_closing() then
		self.tcp:write(data, function(err)
			if on_flushed then
				vim.schedule(function()
					on_flushed(err)
				end)
			end
		end)
	end
end

function TCPTransport:read_start(on_data)
	self.tcp:read_start(function(err, chunk)
		vim.schedule(function()
			on_data(err, chunk)
		end)
	end)
end

function TCPTransport:close()
	if not self.tcp:is_closing() then
		self.tcp:close()
	end
end

return TCPTransport
