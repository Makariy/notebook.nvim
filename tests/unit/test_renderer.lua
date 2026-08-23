local NotebookRenderer = require("notebook.ui.notebook_renderer")
local Cell = require("notebook.notebook.cell")
local Notebook = require("notebook.notebook.notebook")
local Output = require("notebook.notebook.output")

local nb = Notebook.new()
local c1 = Cell.code("print(1)")
c1.metadata.id = "c1"
table.insert(nb.cells, c1)

local c2 = Cell.code("print(2)")
c2.metadata.id = "c2"
table.insert(c2.outputs, Output.new({ output_type = "stream", name = "stdout", text = "a\nb\nc" }))
table.insert(nb.cells, c2)

local layout = NotebookRenderer.build(nb, 80)

check(#layout.code_lines == #layout.res_lines, "code and results buffers have equal line count")
check(#layout.cell_starts == 2, "one start row per cell")
check(layout.cell_starts[1] == 1, "first cell marker after leading anchor line")
check(layout.cell_starts[2] == 3, "second cell starts after first block")

-- Decorations live in virtual lines: state above each marker, separator above
-- the next marker (so it follows edits).
check(#layout.code_virts == 3, "one header per cell + trailing separator")
check(layout.code_virts[1].row == 1, "first state above first marker")
check(layout.code_virts[1].lines[1][1][1] == "○ Not executed", "default state rendered")
check(layout.code_virts[2].row == 3, "second header at second marker")
check(layout.code_virts[2].lines[1][1][1] == string.rep("─", 80), "separator above second marker")
check(layout.code_virts[2].lines[2][1][1] == "○ Not executed", "second state rendered")
check(layout.code_virts[3].row == 7, "trailing separator after last cell")
check(layout.code_virts[3].lines[1][1][1] == string.rep("─", 80), "last separator rendered")

-- Real lines contain markers + source, plus the anchor/padding lines.
check(layout.code_lines[2] == "# %% [code:c1]", "marker follows the leading anchor line")
check(layout.code_lines[1] == "", "leading anchor line is blank")

-- Hidden outputs: the cell renders a single muted placeholder line, no output
-- lines, no image blocks, and the block collapses to the source height (the
-- code buffer gains no padding).
do
	local nb = Notebook.new()
	local c = Cell.code("print('A')")
	c.metadata.id = "c1"
	c:add_output(Output.new({ output_type = "stream", name = "stdout", text = "0\n1\n2\n" }))
	table.insert(nb.cells, c)

	local visible = NotebookRenderer.build(nb, 80)
	local hidden = NotebookRenderer.build(nb, 80, nil, nil, { c1 = true })

	check(#hidden.code_lines < #visible.code_lines, "RH1 hidden cell removes padding")

	local res = table.concat(hidden.res_lines, "\n")
	check(res:find("%[outputs hidden%]") ~= nil, "RH2 placeholder present in results")
	check(res:find("0\n1\n2", 1, true) == nil, "RH3 output text hidden")

	local muted = false
	for _, h in ipairs(hidden.highlights) do
		if h.hl == "NotebookMuted" then
			muted = true
		end
	end
	check(muted, "RH4 placeholder carries the muted highlight")
	check(#hidden.images == 0, "RH5 no image blocks for a hidden cell")
	check(#hidden.code_lines == #hidden.res_lines, "RH6 buffers stay aligned")
end

-- Image outputs reserve physical rows and emit renderable image blocks.
do
	local nb = Notebook.new()
	local c = Cell.code("plt.show()")
	c.metadata.id = "imgcell"
	table.insert(
		c.outputs,
		Output.new({
			output_type = "display_data",
			data = { ["image/png"] = "base64stuff" },
		})
	)
	table.insert(nb.cells, c)

	local resolved = {
		["imgcell:1"] = { id = "img1", path = "placeholder.png", height_cells = 5 },
	}
	local with_image = NotebookRenderer.build(nb, 80, resolved)

	check(#with_image.images == 1, "image output emits one image block")
	check(with_image.images[1].id == "img1", "image block carries id")
	check(with_image.images[1].start_row == 2, "image block anchored at reserved row")
	check(with_image.images[1].overlap == 5, "image block carries overlap (reserved rows)")
	check(#with_image.code_lines == #with_image.res_lines, "image cell keeps buffers aligned")

	-- Without resolved images, fall back to the text placeholder.
	local without_image = NotebookRenderer.build(nb, 80, nil)
	local placeholder = false
	for _, line in ipairs(without_image.res_lines) do
		if line:find("image/png", 1, true) then
			placeholder = true
		end
	end
	check(placeholder, "falls back to [image/png] placeholder without resolved images")
	check(#without_image.images == 0, "no image blocks without resolved images")
end
