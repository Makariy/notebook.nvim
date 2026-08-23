---@class CellOutput
---@field output_type "stream" | "display_data" | "execute_result" | "error"
---@field name? "stdout" | "stderr"
---@field text? string
---@field data? table<string, string>
---@field metadata? table
---@field execution_count? integer
---@field ename? string
---@field evalue? string
---@field traceback? string[]
local CellOutput = {}
CellOutput.__index = CellOutput

---@param spec table
---@return CellOutput
function CellOutput.new(spec)
	local self = setmetatable({}, CellOutput)
	self.output_type = spec.output_type
	self.name = spec.name
	self.text = spec.text
	self.data = spec.data
	self.metadata = spec.metadata
	self.execution_count = spec.execution_count
	self.ename = spec.ename
	self.evalue = spec.evalue
	self.traceback = spec.traceback
	return self
end

return CellOutput
