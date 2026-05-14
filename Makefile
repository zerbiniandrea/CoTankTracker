.PHONY: all lint format check typecheck deps

OUF_REPO := https://github.com/oUF-wow/oUF.git

all: deps typecheck lint format

deps:
	@if [ ! -e libs/oUF/.git ]; then \
		echo "Cloning oUF..."; \
		git clone $(OUF_REPO) libs/oUF; \
	else \
		echo "Fetching oUF..."; \
		if [ "$$(git -C libs/oUF rev-parse --is-shallow-repository)" = "true" ]; then \
			git -C libs/oUF fetch --unshallow --tags; \
		else \
			git -C libs/oUF fetch --tags --prune; \
		fi; \
	fi
	@latest=$$(git -C libs/oUF tag --list --sort=-v:refname | head -n1); \
	if [ -z "$$latest" ]; then echo "No tags found in libs/oUF"; exit 1; fi; \
	echo "Checking out oUF $$latest"; \
	git -C libs/oUF -c advice.detachedHead=false checkout $$latest

lint:
	luacheck .

format:
	stylua .

typecheck:
	lua-language-server --check . --checklevel=Warning

check: deps typecheck lint
	stylua --check .
