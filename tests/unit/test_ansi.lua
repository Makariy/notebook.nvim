local ansi = require("notebook.ui.ansi")

-- Plain text passes through untouched with no spans.
do
	local stripped, spans = ansi.segments("hello world")
	check(stripped == "hello world", "A1 plain text passes through")
	check(#spans == 0, "A1 plain text has no spans")
end

-- A colored run is stripped of escape codes and reported as a span.
do
	local stripped, spans = ansi.segments("\x1b[31mred\x1b[0mnormal")
	check(stripped == "rednormal", "A2 escape codes are stripped")
	check(#spans == 1, "A2 one styled span")
	check(spans[1].start == 0 and spans[1]["end"] == 3, "A2 span covers the red text")
	check(spans[1].style.fg == 1, "A2 span carries the fg color")
	check(spans[1].style.bold == false, "A2 span is not bold")
end

-- Bold + color combine, and the style resets with SGR 0.
do
	local stripped, spans = ansi.segments("\x1b[1;32mbold green\x1b[0m plain")
	check(stripped == "bold green plain", "A3 stripped text")
	check(#spans == 1, "A3 one styled span")
	check(spans[1].style.bold == true, "A3 span is bold")
	check(spans[1].style.fg == 2, "A3 span is green")
end

-- Bright colors map into the 8-15 range.
do
	local _, spans = ansi.segments("\x1b[91mhi")
	check(spans[1].style.fg == 9, "A4 bright fg maps to 9")
end

-- Background colors and underline.
do
	local _, spans = ansi.segments("\x1b[44;4mtext")
	check(spans[1].style.bg == 4, "A5 bg color captured")
	check(spans[1].style.underline == true, "A5 underline captured")
end

-- A span with no visible style is omitted.
do
	local _, spans = ansi.segments("\x1b[0mplain\x1b[0m")
	check(#spans == 0, "A6 reset-only sequences produce no spans")
end
