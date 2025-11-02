# .luacheckrc for projectionist.nvim

# Standard lua globals
std = "luajit"

# Global variables specific to Neovim
globals = {
  "vim",
}

# Only check our source code, not dependencies
include_files = {
  "lua/projectionist/**/*.lua",
  "test/**/*.lua",
}

# Exclude dependencies from linting
exclude_files = {
  "lua/plenary/**",
  "lua_modules/**",
}

# Allow unused function arguments (common in callbacks)
unused_args = false

# Line length limit
max_line_length = 120

# Allow shadowing upvalues (common in nested functions)
allow_defined_top = true