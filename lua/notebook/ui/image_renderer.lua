local ImageApi = require("notebook.ui.image_api")
local ImageResolver = require("notebook.ui.image_resolver")

---@class ImageRenderer
---@field view NotebookView
---@field api ImageApi
---@field resolver ImageResolver
---@field images table<string, table> Active image.nvim Image objects
---@field _editing boolean
---@field _window integer? Results window the active images are bound to
---@field _generation integer Bumped when the results window is recreated
---@field warned table<string, boolean>
local ImageRenderer = {}
ImageRenderer.__index = ImageRenderer

---@param view NotebookView
---@return ImageRenderer
function ImageRenderer.new(view)
	local self = setmetatable({}, ImageRenderer)
	self.view = view
	self.api = ImageApi.new()
	self.resolver = ImageResolver.new()
	self.images = {}
	self._editing = false
	self.warned = {}
	self._window = nil
	self._generation = 0
	return self
end

---@return boolean
function ImageRenderer:available()
	return self.api:available()
end

---@param notebook Notebook
---@param win_width integer
---@return table<string, { id: string, path: string, height_cells: integer }>
function ImageRenderer:resolve(notebook, win_width)
	local win = self.view.results_win
	if win ~= self._window then
		self:clear_all()
		self._window = win
		self._generation = self._generation + 1
	end
	return self.resolver:resolve(notebook, win_width, self._generation)
end

function ImageRenderer:begin_edit()
	if not self:available() then
		return
	end
	if not next(self.images) then
		return
	end
	self._editing = true
	self.api:disable()
end

function ImageRenderer:end_edit()
	if not self:available() then
		return
	end
	if not self._editing then
		return
	end
	self._editing = false
	self.api:enable()
end

---@param blocks { id: string, path: string, start_row: integer, overlap: integer }[]
---@param win_width integer
---@param force? boolean Re-render every image. True after the results buffer was
---rewritten (inline extmarks were dropped); when false only images whose
---geometry changed are re-rendered, so no-op renders don't flicker.
function ImageRenderer:sync(blocks, win_width, force)
	if not self:available() then
		return
	end

	local active = {}
	for _, block in ipairs(blocks) do
		if block.path then
			active[block.id] = true

			local image = self.images[block.id]
			local created = false
			if not image then
				local api = self.api:raw()
				local ok, created_img = pcall(api.from_file, block.path, {
					id = block.id,
					window = self.view.results_win,
					buffer = self.view.results_buf,
					with_virtual_padding = false,
					inline = true,
					overlap = block.overlap,
					width = win_width,
					height = block.overlap,
					max_width_window_percentage = 100,
					max_height_window_percentage = math.huge,
				})
				if ok and created_img then
					image = created_img
					created = true
					self.images[block.id] = image
				elseif not ok then
					self:_warn("image.nvim from_file failed: " .. tostring(created_img))
				end
			end

			if image then
				image.overlap = block.overlap
				local geom = image.geometry
				local needs = created
					or force
					or not geom
					or geom.y ~= block.start_row
					or geom.width ~= win_width
					or geom.height ~= block.overlap
				if needs then
					local ok, err =
						pcall(image.render, image, { x = 0, y = block.start_row, width = win_width, height = block.overlap })
					if not ok then
						self:_warn("image.nvim render failed: " .. tostring(err))
					end
				end
			end
		end
	end

	for id, image in pairs(self.images) do
		if not active[id] then
			pcall(image.clear, image)
			self.images[id] = nil
		end
	end
end

function ImageRenderer:hide_all()
	for _, image in pairs(self.images) do
		if image.is_rendered then
			pcall(image.clear, image, true)
		end
	end
end

function ImageRenderer:show_all()
	for _, image in pairs(self.images) do
		if not image.is_rendered then
			pcall(image.render, image)
		end
	end
end

function ImageRenderer:clear_extmarks()
	for _, image in pairs(self.images) do
		pcall(image.clear, image, true)
	end
end

function ImageRenderer:clear_all()
	for _, image in pairs(self.images) do
		pcall(image.clear, image)
	end
	self.images = {}
end

---@private Warn once per message so repeated render cycles don't spam.
---@param msg string
function ImageRenderer:_warn(msg)
	if self.warned[msg] then
		return
	end
	self.warned[msg] = true
	vim.notify("[notebook.nvim] " .. msg, vim.log.levels.WARN)
end

return ImageRenderer
