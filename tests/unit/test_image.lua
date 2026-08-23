-- Tests hand the renderer a minimal view stand-in (just the window/buffer
-- handles), not a fully-constructed NotebookView.
---@diagnostic disable:missing-fields

local image_store = require("notebook.ui.image_store")
local term = require("notebook.ui.term")
local Output = require("notebook.notebook.output")

-- image_data detects image mimes (preferring png).
local with_image = Output.new({
	output_type = "display_data",
	data = { ["text/plain"] = "<Figure>", ["image/png"] = "AAAA" },
})
local image = image_store.image_data(with_image)
check(image ~= nil and image.mime == "image/png", "detects image/png")

local stream = Output.new({ output_type = "stream", name = "stdout", text = "hi" })
check(image_store.image_data(stream) == nil, "stream output is not an image")

-- base64 -> cached file, then read dimensions via identify (1x1 PNG).
local b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
local path = image_store.ensure_file("image/png", b64)
check(path ~= nil and vim.uv.fs_stat(path) ~= nil, "decodes base64 into a file")
check(image_store.ensure_file("image/png", b64) == path, "reuses the same cached path")

local dims = path and image_store.dimensions(path)
check(dims ~= nil and dims.width == 1 and dims.height == 1, "reads dimensions via identify")

-- terminal cell size is sane.
local cs = term.cell_size()
check(cs.width > 0 and cs.height > 0, "cell size is positive")

-- resolve() decodes, reads dimensions and computes a height.
do
	local Cell = require("notebook.notebook.cell")
	local Notebook = require("notebook.notebook.notebook")
	local ImageRenderer = require("notebook.ui.image_renderer")

	local nb = Notebook.new()
	local cell = Cell.code("plt.show()")
	cell.metadata.id = "c1"
	table.insert(
		cell.outputs,
		Output.new({
			output_type = "display_data",
			data = { ["image/png"] = b64 },
		})
	)
	table.insert(nb.cells, cell)

	local renderer = ImageRenderer.new({ results_win = 1, results_buf = 1 })
	renderer.api = {
		available = function()
			return true
		end,
		raw = function()
			return {}
		end,
	}

	local resolved = renderer:resolve(nb, 80)
	local info = resolved["c1:1"]
	check(info ~= nil, "resolve produces an entry for the image output")
	check(info ~= nil and info.path ~= nil, "resolve decodes to a file path")
	check(info ~= nil and info.height_cells >= 1, "resolve computes a positive cell height")
	check(info ~= nil and info.id ~= nil, "resolve assigns a stable id")
end

-- A recreated results window (e.g. focus mode closing and re-opening it) must
-- mint fresh image ids: image.nvim registers images globally by id and will not
-- re-bind an existing id to a new window, so ids are scoped to a window
-- generation and the cache is dropped whenever the window handle changes.
do
	local Cell = require("notebook.notebook.cell")
	local Notebook = require("notebook.notebook.notebook")
	local ImageRenderer = require("notebook.ui.image_renderer")
	local nb = Notebook.new()
	local cell = Cell.code("plt.show()")
	cell.metadata.id = "c1"
	table.insert(
		cell.outputs,
		Output.new({
			output_type = "display_data",
			data = { ["image/png"] = b64 },
		})
	)
	table.insert(nb.cells, cell)

	local renderer = ImageRenderer.new({ results_win = 10, results_buf = 1 })
	renderer.api = {
		available = function()
			return true
		end,
		raw = function()
			return {}
		end,
	}
	local cleared = 0
	renderer.clear_all = function()
		cleared = cleared + 1
	end

	local first = renderer:resolve(nb, 80)
	local key = "c1:1"
	check(cleared == 1, "R1 the first resolve drops the (empty) cache")
	renderer.view.results_win = 20
	local second = renderer:resolve(nb, 80)
	check(
		first[key] ~= nil and second[key] ~= nil and first[key].id ~= second[key].id,
		"R1 a recreated window mints a fresh image id"
	)
	check(cleared == 2, "R1 a recreated window drops the image cache")
	check(renderer:resolve(nb, 80)[key].id == second[key].id, "R1 an unchanged window reuses the image id")
	check(cleared == 2, "R1 an unchanged window keeps the image cache")
end

-- hide_all/show_all hide and restore images; sync() redraws them.
do
	local ImageRenderer = require("notebook.ui.image_renderer")

	local function fake_image(id)
		return {
			id = id,
			is_rendered = true,
			overlap = nil,
			clear = function(self)
				self.is_rendered = false
			end,
			render = function(self)
				self.is_rendered = true
			end,
		}
	end

	local renderer = ImageRenderer.new({})
	renderer.api = {
		available = function()
			return true
		end,
		raw = function()
			return {}
		end,
	}
	local img = fake_image("i1")
	renderer.images["i1"] = img

	renderer:hide_all()
	check(img.is_rendered == false, "I1 hide_all hides the image")

	renderer:show_all()
	check(img.is_rendered == true, "I1 show_all redraws the image")

	renderer:sync({ { id = "i1", path = "x", start_row = 2, overlap = 1 } }, 80)
	check(img.is_rendered == true and img.overlap == 1, "I1 sync() redraws the image")
end

-- sync() skips re-rendering images whose geometry did not change (only when not
-- forced), so no-op renders don't flicker; moved/resized/forced images redraw.
do
	local ImageRenderer = require("notebook.ui.image_renderer")

	local function fake_image(id)
		return {
			id = id,
			geometry = nil,
			overlap = nil,
			render_calls = 0,
			render = function(self, geometry)
				self.render_calls = self.render_calls + 1
				self.geometry = vim.tbl_deep_extend("force", self.geometry or {}, geometry)
			end,
			clear = function() end,
		}
	end

	local renderer = ImageRenderer.new({})
	renderer.api = {
		available = function()
			return true
		end,
		raw = function()
			return {}
		end,
	}
	local img = fake_image("i1")
	renderer.images["i1"] = img

	local block = { id = "i1", path = "x", start_row = 2, overlap = 1 }

	renderer:sync({ block }, 80)
	check(img.render_calls == 1, "I2 a new image renders once")

	renderer:sync({ block }, 80)
	check(img.render_calls == 1, "I2 unchanged geometry is not re-rendered")

	renderer:sync({ { id = "i1", path = "x", start_row = 3, overlap = 1 } }, 80)
	check(img.render_calls == 2, "I2 a moved image re-renders")

	renderer:sync({ { id = "i1", path = "x", start_row = 3, overlap = 1 } }, 60)
	check(img.render_calls == 3, "I2 a resized image re-renders")

	renderer:sync({ block }, 60, true)
	check(img.render_calls == 4, "I2 a forced sync re-renders regardless of geometry")
end
