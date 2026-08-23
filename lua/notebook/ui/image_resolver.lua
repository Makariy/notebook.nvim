local image_store = require("notebook.ui.image_store")
local term = require("notebook.ui.term")

local DEFAULT_HEIGHT_ROWS = 10

---@class ImageResolver
---@field _id_cache table<string, { base64: string, id: string }>
local ImageResolver = {}
ImageResolver.__index = ImageResolver

---@return ImageResolver
function ImageResolver.new()
	return setmetatable({ _id_cache = {} }, ImageResolver)
end

---@param notebook Notebook
---@param win_width integer
---@param generation? integer Window-generation the ids are scoped to
---@return table<string, { id: string, path: string, height_cells: integer }>
function ImageResolver:resolve(notebook, win_width, generation)
	local resolved = {}
	local cell_size = term.cell_size()
	local gen = generation and (tostring(generation) .. "-") or ""

	for _, cell in ipairs(notebook.cells) do
		if cell.metadata.id then
			for index, output in ipairs(cell.outputs) do
				local image = image_store.image_data(output)
				if image then
					local path = image_store.ensure_file(image.mime, image.base64)
					if path then
						local key = (generation or 0) .. ":" .. cell.metadata.id .. ":" .. index
						local cached = self._id_cache[key]
						local id
						if cached and cached.base64 == image.base64 then
							id = cached.id
						else
							id = "nbimg-"
								.. gen
								.. cell.metadata.id
								.. ":"
								.. index
								.. ":"
								.. vim.fn.sha256(image_store.clean_base64(image.base64)):sub(1, 12)
							self._id_cache[key] = { base64 = image.base64, id = id }
						end
						resolved[cell.metadata.id .. ":" .. index] = {
							id = id,
							path = path,
							height_cells = self:_height_cells(path, win_width, cell_size),
						}
					end
				end
			end
		end
	end

	return resolved
end

---@private
---@param path string
---@param win_width integer
---@param cell_size { width: number, height: number }
---@return integer
function ImageResolver:_height_cells(path, win_width, cell_size)
	local dims = image_store.dimensions(path)
	if not dims or dims.width <= 0 or dims.height <= 0 then
		return DEFAULT_HEIGHT_ROWS
	end
	return math.max(1, math.ceil(win_width * cell_size.width * dims.height / (dims.width * cell_size.height)))
end

return ImageResolver
