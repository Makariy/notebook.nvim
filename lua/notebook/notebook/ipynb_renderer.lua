---@class IpynbRenderer
local IpynbRenderer = {}

---@private Ensure an empty table encodes as a JSON object `{}`, not an array `[]`.
---@param t table?
---@return table
local function as_object(t)
	if t == nil then
		return vim.empty_dict()
	end
	if next(t) == nil then
		return vim.empty_dict()
	end
	return t
end

---@private Split a string into a list of lines, preserving trailing newlines.
---@param source string
---@return string[]
local function split_keepends(source)
	local lines = {}
	for line, newline in source:gmatch("([^\n]*)(\n?)") do
		if line ~= "" or newline ~= "" then
			table.insert(lines, line .. newline)
		end
	end
	return lines
end

---@private
---@param output CellOutput
---@return table
local function render_output(output)
	local t = { output_type = output.output_type }

	if output.output_type == "stream" then
		t.name = output.name
		t.text = output.text
	elseif output.output_type == "display_data" or output.output_type == "execute_result" then
		t.data = as_object(output.data)
		t.metadata = as_object(output.metadata)
		if output.output_type == "execute_result" then
			t.execution_count = output.execution_count or vim.NIL
		end
	elseif output.output_type == "error" then
		t.ename = output.ename
		t.evalue = output.evalue
		t.traceback = output.traceback or {}
	end

	return t
end

---@private
---@param cell Cell
---@return table
local function render_cell(cell)
	local t = { cell_type = cell.cell_type }

	if cell.cell_type == "code" then
		t.execution_count = cell.execution_count or vim.NIL
	end

	t.metadata = as_object(cell.metadata)

	if cell.cell_type == "code" then
		t.outputs = {}
		for _, output in ipairs(cell.outputs) do
			table.insert(t.outputs, render_output(output))
		end
	end

	t.source = split_keepends(cell.source)

	if cell.attachments ~= nil then
		t.attachments = as_object(cell.attachments)
	end

	return t
end

---@param notebook Notebook
---@return string
function IpynbRenderer.render(notebook)
	local cells = {}
	for _, cell in ipairs(notebook.cells) do
		table.insert(cells, render_cell(cell))
	end

	return vim.json.encode({
		cells = cells,
		metadata = as_object(notebook.metadata),
		nbformat = notebook.nbformat or 4,
		nbformat_minor = notebook.nbformat_minor or 0,
	})
end

return IpynbRenderer
