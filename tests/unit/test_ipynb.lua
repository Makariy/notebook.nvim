local IpynbParser = require("notebook.notebook.ipynb_parser")
local IpynbRenderer = require("notebook.notebook.ipynb_renderer")
local Notebook = require("notebook.notebook.notebook")
local Cell = require("notebook.notebook.cell")
local Output = require("notebook.notebook.output")

-- render -> parse -> render is a lossless round trip for cells, sources,
-- metadata, execution counts and every output shape.
do
	local nb = Notebook.new()
	local cell = Cell.code("x = 1\nprint(x)")
	cell.metadata = { id = "c1" }
	cell.execution_count = 2
	table.insert(cell.outputs, Output.new({ output_type = "stream", name = "stdout", text = "1\n" }))
	table.insert(
		cell.outputs,
		Output.new({
			output_type = "error",
			ename = "ZeroDivisionError",
			evalue = "div by zero",
			traceback = { "Traceback", "  line 1" },
		})
	)
	table.insert(nb.cells, cell)

	local md = Cell.markdown("# Title")
	md.metadata = { id = "c2" }
	table.insert(nb.cells, md)

	local json = IpynbRenderer.render(nb)
	local parsed = IpynbParser.parse(json)
	check(parsed ~= nil, "I1 renders and parses back")
	if not parsed then
		return
	end
	check(#parsed.cells == 2, "I1 cell count preserved")
	check(parsed.cells[1].source == "x = 1\nprint(x)", "I1 source preserved")
	check(parsed.cells[1].cell_type == "code" and parsed.cells[1].execution_count == 2, "I1 execution count preserved")
	check(parsed.cells[1].metadata.id == "c1", "I1 metadata preserved")
	check(#parsed.cells[1].outputs == 2, "I1 outputs preserved")
	check(
		parsed.cells[1].outputs[1].text == "1\n" and parsed.cells[1].outputs[1].name == "stdout",
		"I1 stream output preserved"
	)
	check(parsed.cells[1].outputs[2].evalue == "div by zero", "I1 error output preserved")
	check(parsed.cells[2].cell_type == "markdown" and parsed.cells[2].source == "# Title", "I1 markdown preserved")
	check(IpynbRenderer.render(parsed) == json, "I1 re-render is byte-identical")
end

-- Malformed input reports a descriptive error.
do
	local _, err = IpynbParser.parse("not json")
	check(err ~= nil and err:find("Invalid notebook JSON") ~= nil, "I2 malformed json is reported")
	local _, err2 = IpynbParser.parse(vim.json.encode({ nbformat = 4 }))
	check(err2 ~= nil and err2:find("cells") ~= nil, "I2 a missing cells array is reported")
	local _, err3 = IpynbParser.parse("null")
	check(err3 ~= nil and err3:find("top%-level object") ~= nil, "I2 a non-object root is reported")
end
