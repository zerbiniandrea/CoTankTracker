.PHONY: all lint format check typecheck deps

all: deps typecheck lint format

deps:
	@if [ ! -d libs/oUF ]; then \
		echo "Fetching oUF..."; \
		git clone --depth 1 https://github.com/oUF-wow/oUF.git libs/oUF; \
	fi

lint:
	luacheck .

format:
	stylua .

typecheck:
	lua-language-server --check . --checklevel=Warning

check: deps typecheck lint
	stylua --check .
