---@diagnostic disable:undefined-field

local M = {}

local ok, ffi = pcall(require, "ffi")
if ok then
	pcall(
		ffi.cdef,
		[[
		typedef struct {
			unsigned short row;
			unsigned short col;
			unsigned short xpixel;
			unsigned short ypixel;
		} nb_term_winsize;
	]]
	)
	pcall(ffi.cdef, "int ioctl(int, int, ...);")
end

---@return { width: number, height: number } cell size in pixels
function M.cell_size()
	if not ffi or not ffi.C or ffi.C.ioctl == nil then
		return { width = 8, height = 16 }
	end

	local TIOCGWINSZ
	if vim.fn.has("linux") == 1 then
		TIOCGWINSZ = 0x5413
	elseif vim.fn.has("mac") == 1 or vim.fn.has("bsd") == 1 then
		TIOCGWINSZ = 0x40087468
	end
	if not TIOCGWINSZ then
		return { width = 8, height = 16 }
	end

	local sz = ffi.new("nb_term_winsize")
	if ffi.C.ioctl(1, TIOCGWINSZ, sz) ~= 0 then
		return { width = 8, height = 16 }
	end

	local xpixel, ypixel = sz.xpixel, sz.ypixel
	if xpixel == 0 or ypixel == 0 then
		xpixel = sz.col * 8
		ypixel = sz.row * 16
	end

	local width = sz.col > 0 and math.floor(xpixel / sz.col) or 0
	local height = sz.row > 0 and math.floor(ypixel / sz.row) or 0
	if width <= 0 then
		width = 8
	end
	if height <= 0 then
		height = 16
	end

	return { width = width, height = height }
end

return M
