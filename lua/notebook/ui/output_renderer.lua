---@class AnsiSegment
---@field start integer byte offset (0-based)
---@field ["end"] integer byte offset (0-based, exclusive)
---@field hl string highlight group name

---@class OutputLine
---@field text string
---@field segments AnsiSegment[]

local ansi = require("notebook.ui.ansi")
local HighlightRegistry = require("notebook.ui.ansi_highlights")

local M = {}

local registry = HighlightRegistry.new()

---@private
---@param text string?
---@return string[]
local function split_lines(text)
	text = text or ""
	if text:sub(-1) == "\n" then
		text = text:sub(1, -2)
	end
	return vim.split(text, "\n", { plain = true, trimempty = false })
end

---@private
---@param raw string[]
---@param registry HighlightRegistry
---@return OutputLine[]
local function to_output_lines(raw, registry)
	local result = {}
	for _, line in ipairs(raw) do
		local stripped, spans = ansi.segments(line)
		local segments = {}
		for _, span in ipairs(spans) do
			local s = span.style
			table.insert(segments, {
				start = span.start,
				["end"] = span["end"],
				hl = registry:group(s.fg, s.bg, s.bold, s.italic, s.underline),
			})
		end
		table.insert(result, { text = stripped, segments = segments })
	end
	return result
end

---@private
---@param output CellOutput
---@return string[]
local function stream_lines(output)
	return split_lines(output.text)
end

---@private
---@param output CellOutput
---@return string[]
local function data_lines(output)
	local data = output.data or {}
	local text = data["text/plain"] or data["text/markdown"]
	if text then
		return split_lines(text)
	end
	local mime = next(data)
	if mime then
		return { "[" .. mime .. "]" }
	end
	return {}
end

---@private
---@param output CellOutput
---@return string[]
local function error_lines(output)
	local lines = { (output.ename or "Error") .. ": " .. (output.evalue or "") }
	for _, trace in ipairs(output.traceback or {}) do
		for _, line in ipairs(split_lines(trace)) do
			table.insert(lines, line)
		end
	end
	return lines
end

---@private
---@type table<string, fun(output: CellOutput): string[]>
local OUTPUT_LINE_BUILDERS = {
	stream = stream_lines,
	execute_result = data_lines,
	display_data = data_lines,
	error = error_lines,
}

---@param output CellOutput
---@return OutputLine[]
function M.output_lines(output)
	local builder = OUTPUT_LINE_BUILDERS[output.output_type]
	if not builder then
		return {}
	end
	return to_output_lines(builder(output), registry)
end

return M
