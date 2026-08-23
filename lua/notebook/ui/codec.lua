local Cell = require("notebook.notebook.cell")

local codec = {}

---@class CellSpec
---@field cell_type string
---@field id string
---@field source string

---@param cell_type string
---@param id string
---@return string
function codec.marker_for(cell_type, id)
	return "# %% [" .. cell_type .. ":" .. id .. "]"
end

---@param line string
---@return string? cell_type, string? id
function codec.parse_marker(line)
	local cell_type, id = line:match("^# %%%%%s*%[([a-z]+):(.-)%]$")
	if cell_type then
		return cell_type, id
	end

	if line:match("^# %%%%%s*$") then
		return "code", nil
	end
	return nil
end

---@param source string
---@return string[]
function codec.split_source(source)
	if source == "" then
		return {}
	end
	return vim.split(source, "\n", { plain = true })
end

---@private Prefix a markdown line with `#` so the file stays valid Python.
---@param line string
---@return string
local function prefix_markdown(line)
	if line == "" then
		return "#"
	end
	return "# " .. line
end

---@private Strip the leading markdown `#` prefix.
---@param line string
---@return string
local function strip_markdown(line)
	if line == "#" then
		return ""
	end
	if line:sub(1, 2) == "# " then
		return line:sub(3)
	end
	return line
end

---@param notebook Notebook
function codec.ensure_ids(notebook)
	for _, cell in ipairs(notebook.cells) do
		if not cell.metadata.id or cell.metadata.id == "" then
			cell.metadata.id = Cell.generate_id()
		end
	end
end

---@param cell Cell
---@return string[]
function codec.render_source_lines(cell)
	local lines = {}
	for _, src_line in ipairs(codec.split_source(cell.source)) do
		if cell.cell_type == "markdown" then
			table.insert(lines, prefix_markdown(src_line))
		else
			table.insert(lines, src_line)
		end
	end
	return lines
end

---@param lines string[]
---@return CellSpec[]
function codec.parse_lines(lines)
	local specs = {}
	local current = nil
	local seen_marker = false

	local function flush()
		if not current then
			return
		end
		local source = {}
		for _, line in ipairs(current.body) do
			if current.cell_type == "markdown" then
				table.insert(source, strip_markdown(line))
			else
				table.insert(source, line)
			end
		end

		local i = #source
		while i > 0 and source[i]:match("^%s*$") do
			table.remove(source, i)
			i = i - 1
		end

		table.insert(specs, { cell_type = current.cell_type, id = current.id, source = table.concat(source, "\n") })
		current = nil
	end

	for _, line in ipairs(lines) do
		local cell_type, id = codec.parse_marker(line)
		if cell_type then
			seen_marker = true
			flush()
			current = { cell_type = cell_type, id = id or Cell.generate_id(), body = {} }
		elseif not current then
			if not line:match("^%s*$") then
				current = { cell_type = "code", id = Cell.generate_id(), body = { line } }
			end
		else
			table.insert(current.body, line)
		end
	end
	flush()

	if not seen_marker and #specs == 1 then
		local is_blank = true
		for _, line in ipairs(lines) do
			if line:match("%S") then
				is_blank = false
				break
			end
		end
		if is_blank then
			return {}
		end
	end

	return specs
end

---@param lines string[]
---@return { marker: string?, type: string?, id: string?, source: string[] }[]
function codec.cell_blocks(lines)
	local blocks = {}
	local current
	for _, line in ipairs(lines) do
		local cell_type, id = codec.parse_marker(line)
		if cell_type then
			if current then
				table.insert(blocks, current)
			end
			current = { marker = line, type = cell_type, id = id, source = {} }
		elseif current then
			table.insert(current.source, line)
		end
	end
	if current then
		table.insert(blocks, current)
	end
	for _, block in ipairs(blocks) do
		while #block.source > 0 and block.source[#block.source]:match("^%s*$") do
			table.remove(block.source)
		end
	end
	return blocks
end

---@param lines string[]
---@return table<string, integer> Mapping of cell id to its physical height (including padding)
function codec.physical_heights(lines)
	local heights = {}
	local current_id = nil
	local count = 0
	for _, line in ipairs(lines) do
		local cell_type, id = codec.parse_marker(line)
		if cell_type then
			if current_id then
				heights[current_id] = count
			end
			current_id = id
			count = 0
		elseif current_id then
			count = count + 1
		end
	end
	if current_id then
		heights[current_id] = count
	end
	return heights
end

return codec
