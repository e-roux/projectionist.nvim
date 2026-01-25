-- Minimal init for running tests
-- Respects LUA_MODULES_DIR and CI environment variables for CI/local compatibility

local modules_dir
if vim.env.LUA_MODULES_DIR then
	modules_dir = vim.env.LUA_MODULES_DIR
elseif vim.env.CI then
	modules_dir = "lua_modules"
else
	modules_dir = vim.env.HOME .. "/.cache/projectionist-nvim/deps"
end

local plenary_dir = modules_dir .. "/plenary"

-- Add plenary to runtime path
vim.opt.runtimepath:prepend(plenary_dir)

-- Add current directory to runtime path
vim.opt.runtimepath:prepend(vim.fn.getcwd())

-- Enable filetype detection
vim.cmd("filetype plugin indent on")
vim.cmd("syntax enable")
