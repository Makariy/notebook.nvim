---@class ImageApi
---@field api table?
---@field warned table<string, boolean>
local ImageApi = {}
ImageApi.__index = ImageApi

---@return ImageApi
function ImageApi.new()
	return setmetatable({ api = nil, warned = {} }, ImageApi)
end

---@return boolean
function ImageApi:available()
	if self.api then
		return true
	end

	local ok, api = pcall(require, "image")
	if not ok then
		self:_warn("image.nvim is not installed or not on the runtimepath")
		return false
	end

	self.api = api
	return true
end

---@return table
function ImageApi:raw()
	return self.api
end

function ImageApi:disable()
	if not self:available() then
		return
	end
	pcall(self.api.disable)
end

function ImageApi:enable()
	if not self:available() then
		return
	end
	pcall(self.api.enable)
end

---@private Warn once per message so repeated probes don't spam.
---@param msg string
function ImageApi:_warn(msg)
	if self.warned[msg] then
		return
	end
	self.warned[msg] = true
	vim.notify("[notebook.nvim] " .. msg, vim.log.levels.WARN)
end

return ImageApi
