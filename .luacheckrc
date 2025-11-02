-- .luacheckrc for projectionist.nvim

-- Standard lua globals
std = "luajit"

-- Global variables specific to Neovim
globals = {
  "vim",
  "describe",
  "it",
  "before_each",
  "after_each",
  "setup",
  "teardown",
}

-- Only check our source code, not dependencies
include_files = {
  "lua/projectionist/**/*.lua",
  "test/**/*.lua",
}

-- Exclude dependencies from linting
exclude_files = {
  "lua/plenary/**",
  "lua_modules/**",
  "test/lua_modules/**",
}

-- Allow unused function arguments (common in callbacks)
unused_args = false

-- Line length limit
max_line_length = 120

-- Allow shadowing upvalues (common in nested functions)
allow_defined_top = true

-- Ignore warnings about unused variables in test files
files["test/**/*.lua"] = {
  ignore = {"212", "213", "431", "432"},  -- unused argument, unused variable, shadowing upvalue, shadowing definition
}

-- Ignore specific false positives in source files  
files["lua/projectionist/config.lua"] = {
  ignore = {"311"},  -- value assigned to variable is unused (false positive)
}

files["lua/projectionist/init.lua"] = {
  ignore = {"311"},  -- value assigned to variable is unused (false positive)
}