MAKEFLAGS += --silent
SHELL := /bin/sh
.DEFAULT_GOAL := help

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------

NVIM ?= nvim
GIT ?= git
STYLUA := $(shell command -v stylua 2>/dev/null)
LUACHECK := $(shell command -v luacheck 2>/dev/null)

# Directories
# Use XDG cache for local dev (persistent), allow CI to override to lua_modules (cached)
XDG_CACHE_HOME ?= $(HOME)/.cache
ifdef CI
LUA_MODULES_DIR ?= lua_modules
else
LUA_MODULES_DIR ?= $(XDG_CACHE_HOME)/projectionist-nvim/deps
endif
PLENARY_DIR ?= $(LUA_MODULES_DIR)/plenary
TEST_DIR ?= test
MINIMAL_INIT ?= $(TEST_DIR)/minimal_init.lua

# Timestamp markers
PLENARY_MARKER := $(PLENARY_DIR)/.git/HEAD

# Source files
LUA_SRC := lua/projectionist
TEST_SRC := $(TEST_DIR)
DOC_SRC := doc
 
#------------------------------------------------------------------------------
# Phony Targets Declaration
#------------------------------------------------------------------------------

.PHONY: all test lint fmt check qa clean help
.PHONY: plenary.run plenary.clean
.PHONY: stylua.run
.PHONY: luacheck.run

#------------------------------------------------------------------------------
# High-Level Targets
#------------------------------------------------------------------------------

all: check test
test: plenary.run
lint: luacheck.run
fmt: stylua.run
check: fmt lint
qa: check test

#------------------------------------------------------------------------------
# Testing
#------------------------------------------------------------------------------

# Timestamp file tracks when plenary.nvim was cloned
$(PLENARY_MARKER):
	printf "🔄 Cloning plenary.nvim...\n"
	mkdir -p "$(LUA_MODULES_DIR)"
	$(GIT) clone --depth 1 --quiet \
		https://github.com/nvim-lua/plenary.nvim "$(PLENARY_DIR)"
	printf "✅ Cloned plenary.nvim\n"

plenary.run: $(PLENARY_MARKER)
	printf "🔄 Running tests...\n"
	$(NVIM) --headless -u $(MINIMAL_INIT) \
		-c 'lua require("plenary.test_harness").test_directory("$(TEST_DIR)/", {minimal_init = "$(MINIMAL_INIT)"})' \
		-c 'qa!'
	printf "✅ Tests complete\n"

plenary.clean:
	if [ -d "$(LUA_MODULES_DIR)" ]; then \
		printf "🧹 Removing test dependencies...\n"; \
		rm -rf "$(LUA_MODULES_DIR)"; \
		printf "✅ Removed test dependencies\n"; \
	fi

#------------------------------------------------------------------------------
# Formatting
#------------------------------------------------------------------------------

stylua.run:
ifdef STYLUA
	printf "🔄 Formatting code...\n"
	$(STYLUA) .
	printf "✅ Code formatted\n"
else
	printf "❌ stylua not found\n"
	printf "Install from: https://github.com/JohnnyMorganz/StyLua\n"
	exit 1
endif


#------------------------------------------------------------------------------
# Linting
#------------------------------------------------------------------------------

luacheck.run:
ifdef LUACHECK
	printf "🔄 Linting code...\n"
	$(LUACHECK) .
	printf "✅ Lint complete\n"
else
	printf "❌ luacheck not found\n"
	printf "Install with: luarocks install luacheck\n"
	exit 1
endif

#------------------------------------------------------------------------------
# Documentation
#------------------------------------------------------------------------------

$(DOC_SRC)/tags:
	printf "📄 Generating help tags...\n"
	$(NVIM) --headless -c "helptags doc/" -c "qa!"
	test -f $@

doc: $(DOC_SRC)/tags

doc.clean:
	printf "🧹 Removing documentation tags...\n"
	rm -f $(DOC_SRC)/tags

#------------------------------------------------------------------------------
# Cleanup
#------------------------------------------------------------------------------

clean: plenary.clean doc.clean

#------------------------------------------------------------------------------
# Help
#------------------------------------------------------------------------------

# Colors
CYAN := \033[0;36m
PURPLE := \033[0;35m
RESET := \033[0m

help:
	printf "$(CYAN)"
	printf "╔════════════════════════════════════════════════════════════════╗\n"
	printf "║                   _           _   _             _     _        ║\n"
	printf "║   _ __  _ __ ___ (_) ___  ___| |_(_) ___  _ __ (_)___| |_      ║\n"
	printf "║  | '_ \| '__/ _ \| |/ _ \/ __| __| |/ _ \| '_ \| / __| __|     ║\n"
	printf "║  | |_) | | | (_) | |  __/ (__| |_| | (_) | | | | \__ \ |_      ║\n"
	printf "║  | .__/|_|  \___// |\___|\___|\__|_|\___/|_| |_|_|___/\__|     ║\n"
	printf "║  |_|           |__/                                            ║\n"
	printf "╚════════════════════════════════════════════════════════════════╝\n"
	printf "$(RESET)\n"
	printf "Usage: make [target] [VAR=val]\n\n"
	printf "$(PURPLE)Development targets:$(RESET)\n"
	printf "  fmt            - Check and format code with stylua\n"
	printf "  lint           - Lint code with luacheck\n"
	printf "  check          - Run all checks (fmt + lint)\n"
	printf "  test           - Run tests with plenary.nvim\n"
	printf "  qa             - Quality assurance (check + test)\n"
	printf "\n"
	printf "$(PURPLE)General targets:$(RESET)\n"
	printf "  clean          - Remove generated files and dependencies\n"
	printf "  doc            - Generate documentation\n"
	printf "  help           - Show this help message\n"
	printf "\n"
	printf "$(PURPLE)Variables:$(RESET)\n"
	printf "  NVIM              - Neovim binary (default: nvim)\n"
	printf "  GIT               - Git binary (default: git)\n"
	printf "  LUA_MODULES_DIR   - Dependencies directory\n"
