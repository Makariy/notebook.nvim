.PHONY: test check format format-check

test:
	nvim --headless -u NONE -n -c "luafile tests/run.lua"

check:
	lua-language-server --check . --checklevel=Information --logpath=.cache/lls

format:
	stylua lua/ plugin/ tests/

format-check:
	stylua --check lua/ plugin/ tests/
