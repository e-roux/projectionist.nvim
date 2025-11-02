# projectionist.nvim Makefile

# Variables
LUA_FILES := $(shell find lua/ -name "*.lua" 2>/dev/null || true)
TEST_FILES := $(shell find test/ -name "*.lua" 2>/dev/null || true)
ALL_LUA_FILES := $(LUA_FILES) $(TEST_FILES)

# Dependency files
PLENARY_DIR := lua_modules/plenary
PLENARY_MARKER := $(PLENARY_DIR)/.git/HEAD

# Tool detection
STYLUA := $(shell command -v stylua 2>/dev/null)
LUACHECK := $(shell command -v luacheck 2>/dev/null)

# Phony targets
.PHONY: test test-full test-shell clean deps lint format check help all
.DEFAULT_GOAL := help

## help: Show this help message
help:
	@echo "Available targets:"
	@sed -n 's/^##//p' $(MAKEFILE_LIST) | column -t -s ':' | sed -e 's/^/ /'

## all: Run all checks (deps, lint, format-check, test)
all: deps lint format-check test

## deps: Install test dependencies
deps: $(PLENARY_MARKER)

$(PLENARY_MARKER):
	@echo "Installing plenary.nvim..."
	@mkdir -p lua_modules
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $(PLENARY_DIR)
	@touch $@

## test: Run tests (requires dependencies)
test: $(PLENARY_MARKER) $(LUA_FILES) $(TEST_FILES)
	nvim --headless -u test/minimal_init.vim \
		-c 'lua require("plenary.test_harness").test_directory("test/", {minimal_init = "test/minimal_init.vim"})' \
		-c 'qa!'

## test-shell: Run tests using shell script
test-shell: $(PLENARY_MARKER)
	./test.sh

## test-full: Run both nvim and shell tests
test-full: test test-shell

## lint: Run luacheck linting (if available)
lint:
ifdef LUACHECK
	luacheck $(ALL_LUA_FILES) --globals vim --std luajit
else
	@echo "luacheck not found - skipping lint check"
	@echo "Install with: luarocks install luacheck"
endif

## format: Format code with stylua (if available)
format:
ifdef STYLUA
	stylua $(ALL_LUA_FILES)
else
	@echo "stylua not found - skipping format"
	@echo "Install from: https://github.com/JohnnyMorganz/StyLua"
endif

## format-check: Check code formatting with stylua (if available)
format-check:
ifdef STYLUA
	stylua --check $(ALL_LUA_FILES)
else
	@echo "stylua not found - skipping format check"
	@echo "Install from: https://github.com/JohnnyMorganz/StyLua"
endif

## check: Run all checks without installing dependencies
check:
	@echo "Running all available checks..."
	@$(MAKE) lint
	@$(MAKE) format-check
	@if [ -f $(PLENARY_MARKER) ]; then \
		$(MAKE) test; \
	else \
		echo "Dependencies not installed - run 'make deps' first"; \
	fi

## clean: Remove all generated files and dependencies
clean:
	rm -rf lua_modules/
	rm -f doc/tags

## install-tools: Install development tools
install-tools:
	@echo "Installing development tools..."
	@echo "Note: This requires system package managers"
	@echo "For stylua: Download from https://github.com/JohnnyMorganz/StyLua/releases"
	@echo "For luacheck: luarocks install luacheck"

# Debug target to show variables
debug:
	@echo "LUA_FILES: $(LUA_FILES)"
	@echo "TEST_FILES: $(TEST_FILES)"
	@echo "PLENARY_MARKER: $(PLENARY_MARKER)"
	@echo "STYLUA: $(STYLUA)"
	@echo "LUACHECK: $(LUACHECK)"