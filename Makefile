test:
	nvim --headless -u tests/minimal_init.lua -c "luafile tests/run.lua"

.PHONY: test
