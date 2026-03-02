.PHONY: test lint format check

test:
	nvim --headless -u tests/minimal_init.lua -l tests/run_tests.lua

lint:
	luacheck lua/ --no-unused-args --no-max-line-length --globals vim

format:
	stylua lua/ tests/

check: lint test