#!/bin/bash
# Test runner script for projectionist.nvim

set -e

echo "Running projectionist.nvim tests..."

# Check if plenary is installed
if [ ! -d "lua_modules/plenary" ]; then
    echo "Installing plenary.nvim..."
    git clone https://github.com/nvim-lua/plenary.nvim lua_modules/plenary
fi

# Run tests
nvim --headless -u test/minimal_init.vim \
     -c 'lua require("plenary.test_harness").test_directory("test/", {minimal_init = "test/minimal_init.vim"})' \
     -c 'qa!'

echo "Tests completed!"