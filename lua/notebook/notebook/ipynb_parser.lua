local Cell = require("notebook.notebook.cell")
local CellOutput = require("notebook.notebook.output")
local Notebook = require("notebook.notebook.notebook")

local IpynbParser = {}

---@private
---@param value string | string[] | nil
---@return string?
local function to_string(value)
	if type(value) == "string" then
		return value
	end
	if type(value) == "table" then
		return table.concat(value)
	end
	return nil
end

---@private
---@param raw table
---@return CellOutput?
local function parse_output(raw)
	local output_type = raw.output_type
	if output_type == "stream" then
		return CellOutput.new({
			output_type = "stream",
			name = raw.name,
			text = to_string(raw.text),
		})
	elseif output_type == "display_data" or output_type == "execute_result" then
		local data = {}
		if type(raw.data) == "table" then
			for mime, value in pairs(raw.data) do
				data[mime] = to_string(value)
			end
		end
		return CellOutput.new({
			output_type = output_type,
			data = data,
			metadata = raw.metadata or {},
			execution_count = raw.execution_count,
		})
	elseif output_type == "error" then
		return CellOutput.new({
			output_type = "error",
			ename = raw.ename,
			evalue = raw.evalue,
			traceback = raw.traceback,
		})
	end
	return nil
end

---@private
---@param raw table
---@return Cell?
local function parse_cell(raw)
	local cell_type = raw.cell_type
	if not cell_type then
		return nil
	end

	local outputs = {}
	if type(raw.outputs) == "table" then
		for _, out in ipairs(raw.outputs) do
			local parsed = parse_output(out)
			if parsed then
				if parsed.output_type == "stream" and #outputs > 0 then
					local last = outputs[#outputs]
					if last.output_type == "stream" and last.name == parsed.name then
						last.text = last.text .. parsed.text
						parsed = nil
					end
				end
				if parsed then
					table.insert(outputs, parsed)
				end
			end
		end
	end

	return Cell.new({
		cell_type = cell_type,
		source = to_string(raw.source) or "",
		metadata = raw.metadata or {},
		execution_count = raw.execution_count,
		outputs = outputs,
		attachments = raw.attachments,
	})
end

---@param data string
---@return Notebook?, string?
function IpynbParser.parse(data)
	local ok, decoded = pcall(vim.json.decode, data, { luanil = { object = true, array = true } })
	if not ok then
		return nil, "Invalid notebook JSON: " .. tostring(decoded)
	end
	if type(decoded) ~= "table" then
		return nil, "Invalid notebook JSON: expected a top-level object"
	end
	if type(decoded.cells) ~= "table" then
		return nil, "Invalid notebook JSON: missing or non-array 'cells'"
	end

	local cells = {}
	for _, raw in ipairs(decoded.cells) do
		local cell = parse_cell(raw)
		if cell then
			table.insert(cells, cell)
		end
	end

	return Notebook.new(cells, {
		metadata = decoded.metadata or {},
		nbformat = decoded.nbformat,
		nbformat_minor = decoded.nbformat_minor,
	})
end

return IpynbParser
