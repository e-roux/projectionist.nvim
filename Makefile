# projectionist.nvim Makefile

.PHONY: test deps clean

# Run tests
test:
	nvim --headless -u test/minimal_init.vim -c 'lua require("plenary.test_harness").test_directory("test/", {minimal_init = "test/minimal_init.vim"})' -c 'qa!'

# Install test dependencies
deps:
	@if [ ! -d "lua_modules/plenary" ]; then \
		echo "Installing plenary.nvim..."; \
		git clone https://github.com/nvim-lua/plenary.nvim lua_modules/plenary; \
	else \
		echo "plenary.nvim already installed"; \
	fi

# Clean test dependencies
clean:
	rm -rf lua_modules/

# Run tests with dependencies
test-full: deps test