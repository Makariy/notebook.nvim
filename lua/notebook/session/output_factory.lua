local CellOutput = require("notebook.notebook.output")

local M = {}

---@param payload ExecutionProgressPayload
---@return CellOutput?
function M.from_progress(payload)
	if payload.type == "stream" then
		return CellOutput.new({
			output_type = "stream",
			name = payload.name,
			text = payload.text,
		})
	elseif payload.type == "display_data" then
		return CellOutput.new({
			output_type = "display_data",
			data = payload.data,
			metadata = payload.metadata,
		})
	elseif payload.type == "execute_result" then
		return CellOutput.new({
			output_type = "execute_result",
			data = payload.data,
			metadata = payload.metadata,
			execution_count = payload.execution_count,
		})
	elseif payload.type == "error" then
		return CellOutput.new({
			output_type = "error",
			ename = payload.ename,
			evalue = payload.evalue,
			traceback = payload.traceback,
		})
	end
	return nil
end

return M
