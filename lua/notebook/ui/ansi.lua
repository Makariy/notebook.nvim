local M = {}

---@class AnsiStyle
---@field fg integer?
---@field bg integer?
---@field bold boolean
---@field italic boolean
---@field underline boolean

---@class AnsiSpan
---@field start integer 0-based byte offset into the stripped text
---@field ["end"] integer 0-based byte offset, exclusive
---@field style AnsiStyle

---@private Apply a sequence of SGR parameters to a style.
---@param state AnsiStyle
---@param params integer[]
---@return AnsiStyle
local function apply_sgr(state, params)
	local s = {
		fg = state.fg,
		bg = state.bg,
		bold = state.bold,
		italic = state.italic,
		underline = state.underline,
	}
	for _, p in ipairs(params) do
		if p == 0 then
			s.fg, s.bg, s.bold, s.italic, s.underline = nil, nil, false, false, false
		elseif p == 1 then
			s.bold = true
		elseif p == 3 then
			s.italic = true
		elseif p == 4 then
			s.underline = true
		elseif p == 22 then
			s.bold = false
		elseif p == 23 then
			s.italic = false
		elseif p == 24 then
			s.underline = false
		elseif p >= 30 and p <= 37 then
			s.fg = p - 30
		elseif p >= 90 and p <= 97 then
			s.fg = p - 90 + 8
		elseif p >= 40 and p <= 47 then
			s.bg = p - 40
		elseif p >= 100 and p <= 107 then
			s.bg = p - 100 + 8
		elseif p == 39 then
			s.fg = nil
		elseif p == 49 then
			s.bg = nil
		end
	end
	return s
end

---@param text string
---@return string stripped, AnsiSpan[] spans (only spans with a visible style)
function M.segments(text)
	if not text:find("\x1b", 1, true) then
		return text, {}
	end

	local runs = {}
	local state = { fg = nil, bg = nil, bold = false, italic = false, underline = false }
	local buf = {}

	local function flush(style)
		local chunk = table.concat(buf)
		buf = {}
		if chunk ~= "" then
			table.insert(runs, { text = chunk, style = style })
		end
	end

	local i = 1
	local n = #text
	while i <= n do
		local c = text:sub(i, i)
		if c == "\x1b" and text:sub(i + 1, i + 1) == "[" then
			local j = i + 2
			while j <= n and not text:sub(j, j):match("[a-zA-Z]") do
				j = j + 1
			end
			if text:sub(j, j) == "m" then
				flush(state)
				local params = {}
				for num in text:sub(i + 2, j - 1):gmatch("%d+") do
					table.insert(params, tonumber(num))
				end
				state = apply_sgr(state, params)
			end
			i = j + 1
		else
			buf[#buf + 1] = c
			i = i + 1
		end
	end
	flush(state)

	local parts = {}
	local spans = {}
	local pos = 0
	for _, run in ipairs(runs) do
		local start = pos
		pos = pos + #run.text
		table.insert(parts, run.text)
		local s = run.style
		if s.fg or s.bg or s.bold or s.italic or s.underline then
			table.insert(spans, { start = start, ["end"] = pos, style = s })
		end
	end

	return table.concat(parts), spans
end

return M
