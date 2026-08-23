local codec = require("notebook.ui.codec")
local reconcile = require("notebook.notebook.reconcile")
local Cell = require("notebook.notebook.cell")
local Notebook = require("notebook.notebook.notebook")

-- cell_blocks splits rendered lines into per-cell blocks and strips padding.
do
	local blocks = codec.cell_blocks({
		"",
		"# %% [code:abc]",
		"print(1)",
		"",
		"",
		"# %% [code:def]",
		"print(2)",
		"",
	})
	check(#blocks == 2, "cell_blocks returns two cells")
	check(blocks[1].type == "code" and blocks[1].id == "abc", "cell_blocks parses the marker")
	check(#blocks[1].source == 1 and blocks[1].source[1] == "print(1)", "cell_blocks strips trailing padding")
	check(blocks[2].id == "def" and blocks[2].source[1] == "print(2)", "cell_blocks splits the second cell")
end

do
	local blocks = codec.cell_blocks({ "", "# %%", "x = 1", "" })
	check(
		#blocks == 1 and blocks[1].id == nil and blocks[1].source[1] == "x = 1",
		"cell_blocks keeps bare markers id-less"
	)
end

-- render_source_lines prefixes markdown, leaves code untouched.
local md = Cell.markdown("hello\nworld")
local md_lines = codec.render_source_lines(md)
check(md_lines[1] == "# hello" and md_lines[2] == "# world", "markdown source prefixed")

local code = Cell.code("a = 1\nb = 2")
check(#codec.render_source_lines(code) == 2, "code source unprefixed")

-- parse_lines splits code and markdown cells and strips markdown prefix.
local specs = codec.parse_lines({
	"# %% [code:x1]",
	"a = 1",
	"",
	"# %% [markdown:y2]",
	"# hello",
})
check(#specs == 2, "parse_lines returns two cells")
check(specs[1].id == "x1" and specs[1].source == "a = 1", "code cell parsed")
check(specs[2].cell_type == "markdown" and specs[2].source == "hello", "markdown cell un-prefixed")

-- reconcile moves deleted cells to the graveyard and restores them by id.
local nb = Notebook.new()
local cellA = Cell.code("print('A')")
cellA.metadata.id = "a"
table.insert(nb.cells, cellA)

local graveyard = {}
reconcile.reconcile(nb, codec.parse_lines({ "# %% [code:b]", "print('B')" }), graveyard)
check(#nb.cells == 1 and nb.cells[1].metadata.id == "b", "reconcile removes deleted cell")
check(graveyard["a"] ~= nil, "deleted cell moved to graveyard")

reconcile.reconcile(
	nb,
	codec.parse_lines({
		"# %% [code:a]",
		"print('A')",
		"# %% [code:b]",
		"print('B')",
	}),
	graveyard
)
check(#nb.cells == 2, "reconcile restores cell from graveyard")
