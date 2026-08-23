---@class Cell
---@field cell_type "code" | "markdown" | "raw"
---@field source string
---@field metadata table
---@field execution_count? integer
---@field outputs CellOutput[]
---@field attachments? table
local Cell = {}
Cell.__index = Cell

---@return string A short, unique cell id
function Cell.generate_id()
	return "c" .. vim.fn.sha256(tostring(vim.uv.hrtime())):sub(1, 6)
end

---@param spec { cell_type: string, source?: string, metadata?: table, execution_count?: integer, outputs?: CellOutput[], attachments?: table }
---@return Cell
function Cell.new(spec)
	local self = setmetatable({}, Cell)
	self.cell_type = spec.cell_type
	self.source = spec.source or ""
	self.metadata = spec.metadata or {}
	self.execution_count = spec.execution_count
	self.outputs = spec.outputs or {}
	self.attachments = spec.attachments
	return self
end

---@param source string
---@return Cell
function Cell.code(source)
	return Cell.new({ cell_type = "code", source = source })
end

---@param source string
---@return Cell
function Cell.markdown(source)
	return Cell.new({ cell_type = "markdown", source = source })
end

---@return boolean
function Cell:is_code()
	return self.cell_type == "code"
end

---@param output CellOutput
function Cell:add_output(output)
	if output.output_type == "stream" and #self.outputs > 0 then
		local last = self.outputs[#self.outputs]
		if last.output_type == "stream" and last.name == output.name then
			last.text = last.text .. output.text
			return
		end
	end
	table.insert(self.outputs, output)
end

function Cell:clear_outputs()
	self.outputs = {}
end

return Cell
