local M = {}

local IMAGE_EXT = {
	["image/png"] = "png",
	["image/jpeg"] = "jpg",
	["image/gif"] = "gif",
	["image/webp"] = "webp",
	["image/svg+xml"] = "svg",
}

local IMAGE_MIMES = { "image/png", "image/jpeg", "image/gif", "image/webp", "image/svg+xml" }

---@class NotebookImageData
---@field mime string
---@field base64 string

---@type table<string, { width: number, height: number }>
local dims_cache = {}

---@type table<string, boolean>
local warned = {}

---@private Warn once per message so repeated failures don't spam.
---@param msg string
local function warn(msg)
	if warned[msg] then
		return
	end
	warned[msg] = true
	vim.notify("[notebook.nvim] " .. msg, vim.log.levels.WARN)
end

---@param output CellOutput
---@return NotebookImageData?
function M.image_data(output)
	local data = output.data
	if type(data) ~= "table" then
		return nil
	end

	for _, mime in ipairs(IMAGE_MIMES) do
		local value = data[mime]
		if type(value) == "string" and value ~= "" then
			return { mime = mime, base64 = value }
		end
	end
	return nil
end

---@private
---@param mime string
---@param base64 string
---@return string path
local function path_for(mime, base64)
	local ext = IMAGE_EXT[mime] or "png"
	local hash = vim.fn.sha256(M.clean_base64(base64))
	return vim.fn.stdpath("cache") .. "/notebook.nvim/images/" .. hash .. "." .. ext
end

---@param base64 string
---@return string
function M.clean_base64(base64)
	return (base64:gsub("%s", ""))
end

---@param mime string
---@param base64 string
---@return string?
function M.ensure_file(mime, base64)
	local path = path_for(mime, base64)
	if vim.uv.fs_stat(path) then
		return path
	end

	local decoded = vim.base64.decode(M.clean_base64(base64))
	if not decoded or decoded == "" then
		warn("Failed to decode base64 image output (skipped)")
		return nil
	end

	local dir = vim.fn.fnamemodify(path, ":h")
	vim.fn.mkdir(dir, "p")

	local f, err = io.open(path, "wb")
	if not f then
		warn("Failed to write cached image to " .. path .. ": " .. tostring(err))
		return nil
	end
	f:write(decoded)
	f:close()

	return path
end

---@param path string
---@return { width: number, height: number }?
function M.dimensions(path)
	local cached = dims_cache[path]
	if cached then
		return cached
	end

	local out = vim.fn.system({ "identify", "-format", "%w %h", path })
	local w, h = out:match("^(%d+) (%d+)$")
	if not w then
		warn("ImageMagick `identify` failed for " .. path .. " (using a default image height)")
		return nil
	end

	local result = { width = tonumber(w), height = tonumber(h) }
	dims_cache[path] = result
	return result
end

return M
