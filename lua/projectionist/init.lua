--- @class Projectionist
--- Modern Lua port of vim-projectionist for Neovim
local M = {}

-- Import modules
local utils = require("projectionist.utils")
local patterns = require("projectionist.patterns")
local config = require("projectionist.config")

-- Expose internal state and functions from config module for compatibility
M._config = config._config
M._projections = config._projections
M._roots = config._roots
M.get_project_root = config.get_project_root
M.get_relative_path = config.get_relative_path
M.has_requirements = config.has_requirements
M.get_projections = config.get_projections

-- Set up config to use main module's get_project_root (for test overrides)
config.set_external_root_resolver(function(file)
	return M.get_project_root(file)
end)

--- Core query functions matching vim-projectionist API
--- Query raw projection data for a given key and file
--- @param key string: The projection key (e.g. 'type', 'alternate')
--- @param file string|nil: The file path (defaults to current buffer)
--- @return table: List of matching projection values (may be empty)
M.query_raw = function(key, file)
	file = utils.get_current_file(file)
	local projections = M.get_projections(file)
	if not projections then
		return {}
	end

	local relative_path = M.get_relative_path(file)
	if not relative_path then
		return {}
	end

	local results = {}

	-- Find matching patterns and collect results
	for pattern, attrs in pairs(projections) do
		local lua_pattern, capture_count = patterns.glob_to_pattern(pattern)
		local captures = { relative_path:match(lua_pattern) }

		-- Check if pattern matched: either captures > 0 or (no wildcards and exact match)
		local matched = false
		if capture_count > 0 then
			matched = #captures == capture_count
		else
			matched = relative_path:match(lua_pattern) ~= nil
		end

		if matched and attrs[key] ~= nil then
			-- Store raw result with captures for later expansion
			table.insert(results, {
				value = attrs[key],
				captures = captures,
				pattern = pattern,
				attrs = attrs,
			})
		end
	end

	-- Sort by pattern specificity and extract values
	results = utils.sort_by_specificity(results)
	return utils.extract_values(results)
end

--- Internal function to get query objects with full details
--- @param key string: The projection key
--- @param file string|nil: The file path
--- @return table: List of match objects with value, captures, pattern, attrs
local function query_objects(key, file)
	file = utils.get_current_file(file)
	local projections = M.get_projections(file)
	if not projections then
		return {}
	end

	local relative_path = M.get_relative_path(file)
	if not relative_path then
		return {}
	end

	local results = {}

	-- Find matching patterns and collect results
	for pattern, attrs in pairs(projections) do
		local lua_pattern, capture_count = patterns.glob_to_pattern(pattern)
		local captures = { relative_path:match(lua_pattern) }

		if #captures == capture_count and attrs[key] ~= nil then
			-- Store raw result with captures for later expansion
			table.insert(results, {
				value = attrs[key],
				captures = captures,
				pattern = pattern,
				attrs = attrs,
			})
		end
	end

	-- Sort by pattern specificity 
	return utils.sort_by_specificity(results)
end

--- Query with placeholder expansion
--- @param key string: The projection key
--- @param expansions table|nil: Optional expansions override (unused but kept for compatibility)
--- @param file string|nil: The file path
--- @return table: List of expanded values
M.query = function(key, expansions, file)
	local raw_results = query_objects(key, file)
	local results = {}

	for _, result in ipairs(raw_results) do
		local value = result.value
		local captures = result.captures

		if type(value) == "table" then
			for _, v in ipairs(value) do
				table.insert(results, patterns.expand_placeholders(v, captures))
			end
		else
			table.insert(results, patterns.expand_placeholders(value, captures))
		end
	end

	return results
end

--- Query returning file paths
--- @param key string: The projection key
--- @param file string|nil: The file path
--- @return table: List of file paths
M.query_file = function(key, file)
	local results = M.query(key, nil, file)
	-- Return relative paths from project root as vim-projectionist does
	return results
end

--- Query returning executable commands
--- @param key string: The projection key
--- @param expansions table|nil: Optional expansions override
--- @param file string|nil: The file path
--- @return table: List of executable commands
M.query_exec = function(key, expansions, file)
	return M.query(key, expansions, file)
end

--- Query returning scalar value (first match)
--- @param key string: The projection key
--- @param expansions table|nil: Optional expansions override
--- @param file string|nil: The file path
--- @return string|nil: First matching value
M.query_scalar = function(key, expansions, file)
	local results = M.query(key, expansions, file)
	return results[1]
end

--- Convenience accessors for common queries

--- Get file type for current or specified file
--- @param file string|nil: File path (defaults to current buffer)
--- @return string|nil: File type
M.get_file_type = function(file)
	return M.query_scalar("type", nil, file)
end

--- Get alternate file for current or specified file
--- @param file string|nil: File path (defaults to current buffer)
--- @return string|nil: Relative path to alternate file
M.get_alternate_file = function(file)
	local alternates = M.query("alternate", nil, file)
	return alternates[1]
end

--- Get related files for current or specified file
--- @param file string|nil: File path (defaults to current buffer)
--- @return table: List of related file paths
M.get_related_files = function(file)
	return M.query_file("related", nil, file)
end

--- Get template for current or specified file
--- @param file string|nil: File path (defaults to current buffer)
--- @return table|string|nil: Template content
M.get_template = function(file)
	return M.query_scalar("template", nil, file)
end

--- Template system

--- Apply template to current buffer
--- @param file string|nil: File path (defaults to current buffer)
--- @return boolean: True if template was applied
M.apply_template = function(file)
	file = utils.get_current_file(file)
	local template = M.get_template(file)

	if not template then
		return false
	end

	-- Get template lines
	local lines = {}
	if type(template) == "table" then
		lines = template
	elseif type(template) == "string" then
		lines = vim.split(template, "\n")
	end

	if #lines == 0 then
		return false
	end

	-- Apply template to buffer
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

	-- Trigger BufReadPost for proper initialization
	vim.cmd("doautocmd BufReadPost " .. vim.fn.fnameescape(file))

	return true
end

--- Configuration and setup

--- Setup projectionist with configuration
--- @param opts table: Configuration options
---   - heuristics: Global heuristics (patterns -> projections)
---   - commands: Whether to register commands (default: true)
---   - autocmds: Whether to register autocmds (default: true)
M.setup = function(opts)
	opts = opts or {}

	-- Store configuration with backwards compatibility
	config.set_config(opts)

	-- Register commands and autocmds
	if opts.commands ~= false then
		M.setup_commands()
	end

	if opts.autocmds ~= false then
		M.setup_autocmds()
	end
end

--- Setup vim commands
M.setup_commands = function()
	vim.api.nvim_create_user_command("A", function(args)
		M.cmd_alternate(args, "edit")
	end, {
		nargs = "*",
		complete = M.complete_projections,
		desc = "Edit alternate file",
	})

	vim.api.nvim_create_user_command("AS", function(args)
		M.cmd_alternate(args, "split")
	end, {
		nargs = "*",
		complete = M.complete_projections,
		desc = "Split alternate file",
	})

	vim.api.nvim_create_user_command("AV", function(args)
		M.cmd_alternate(args, "vsplit")
	end, {
		nargs = "*",
		complete = M.complete_projections,
		desc = "Vertical split alternate file",
	})

	vim.api.nvim_create_user_command("AT", function(args)
		M.cmd_alternate(args, "tabedit")
	end, {
		nargs = "*",
		complete = M.complete_projections,
		desc = "Tab alternate file",
	})

	vim.api.nvim_create_user_command("Cd", function(args)
		M.cmd_cd(args, "cd")
	end, {
		nargs = 0,
		desc = "Change to project root",
	})

	vim.api.nvim_create_user_command("Lcd", function(args)
		M.cmd_cd(args, "lcd")
	end, {
		nargs = 0,
		desc = "Change to project root (local)",
	})

	vim.api.nvim_create_user_command("ProjectDo", function(args)
		M.cmd_project_do(args)
	end, {
		nargs = "+",
		desc = "Execute command in project root",
	})

	vim.api.nvim_create_user_command("Console", function(args)
		M.cmd_console(args)
	end, {
		nargs = 0,
		desc = "Open project console",
	})
end

--- Setup autocmds for file detection and template application
M.setup_autocmds = function()
	local group = vim.api.nvim_create_augroup("projectionist", { clear = true })

	-- Detect projectionist files
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
		group = group,
		callback = function(ev)
			M.detect(ev.file)
		end,
		desc = "Detect projectionist files",
	})

	-- Apply templates to new files
	vim.api.nvim_create_autocmd("BufNewFile", {
		group = group,
		callback = function(ev)
			if utils.path_exists(ev.file) then
				return
			end
			-- Small delay to ensure buffer is properly initialized
			vim.defer_fn(function()
				M.apply_template(ev.file)
			end, 1)
		end,
		desc = "Apply projectionist templates",
	})

	-- Clear cache when projection files change
	vim.api.nvim_create_autocmd({ "BufWritePost" }, {
		group = group,
		pattern = { ".projections.json", "heuristic.json" },
		callback = function()
			M.invalidate_cache()
		end,
		desc = "Invalidate projectionist cache",
	})
end

--- Command implementations

--- Alternate file command handler
--- @param args table: Command arguments
--- @param cmd string: Edit command (edit, split, vsplit, etc.)
M.cmd_alternate = function(args, cmd)
	local arg = args.args and args.args ~= "" and args.args or nil
	local file = utils.get_current_file()

	if arg then
		-- Use provided argument as alternate
		local root = M.get_project_root(file)
		if root then
			local full_path = utils.path_join(root, arg)
			M.edit_file(full_path, cmd)
		end
	else
		-- Find alternate
		local alternate = M.get_alternate_file(file)
		if alternate then
			local root = M.get_project_root(file)
			if root then
				local full_path = utils.path_join(root, alternate)
				M.edit_file(full_path, cmd)
			end
		else
			vim.notify("No alternate file found", vim.log.levels.WARN)
		end
	end
end

--- Change directory command handler
--- @param args table: Command arguments
--- @param cmd string: cd or lcd
M.cmd_cd = function(args, cmd)
	local root = M.get_project_root()
	if root then
		vim.cmd(cmd .. " " .. vim.fn.fnameescape(root))
		vim.notify("Changed to " .. root)
	else
		vim.notify("No project root found", vim.log.levels.WARN)
	end
end

--- Project do command handler
--- @param args table: Command arguments with command to execute
M.cmd_project_do = function(args)
	local root = M.get_project_root()
	if not root then
		vim.notify("No project root found", vim.log.levels.WARN)
		return
	end

	local cmd = args.args
	if not cmd or cmd == "" then
		vim.notify("No command provided", vim.log.levels.WARN)
		return
	end

	-- Save current directory and change to project root
	local cwd = vim.fn.getcwd()
	vim.cmd("lcd " .. vim.fn.fnameescape(root))

	-- Execute command
	vim.cmd(cmd)

	-- Restore directory
	vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
end

--- Console command handler
--- @param args table: Command arguments
M.cmd_console = function(args)
	local console = M.query_scalar("console")
	if console then
		-- Execute the console command
		vim.cmd(console)
	else
		-- Fall back to shell in project root
		local root = M.get_project_root()
		if root then
			vim.cmd("lcd " .. vim.fn.fnameescape(root))
			vim.cmd("terminal")
		else
			vim.notify("No project root found", vim.log.levels.WARN)
		end
	end
end

--- Edit file with specified command
--- @param file string: File path
--- @param cmd string: Edit command
M.edit_file = function(file, cmd)
	cmd = cmd or "edit"
	
	-- Create directory if it doesn't exist
	local dir = vim.fs.dirname(file)
	if not utils.path_exists(dir, true) then
		vim.fn.mkdir(dir, "p")
	end

	vim.cmd(cmd .. " " .. vim.fn.fnameescape(file))
end

--- Complete projections for commands
--- @param arg_lead string: Current argument (unused but kept for compatibility)
--- @param cmd_line string: Full command line (unused but kept for compatibility)
--- @param cursor_pos number: Cursor position (unused but kept for compatibility)
--- @return table: Completion candidates
M.complete_projections = function(arg_lead, cmd_line, cursor_pos)
	local projections = M.get_projections()
	if not projections then
		return {}
	end

	local candidates = {}
	for pattern, _ in pairs(projections) do
		-- Convert glob pattern to example paths
		local example = pattern:gsub("%*%*", "path"):gsub("%*", "file")
		if utils.starts_with(example, arg_lead) then
			table.insert(candidates, example)
		end
	end

	return candidates
end

--- File detection and activation

--- Detect and activate projectionist for file
--- @param file string|nil: File path
M.detect = function(file)
	file = utils.get_current_file(file)
	local projections = M.get_projections(file)
	if projections then
		M.activate(projections, file)
	end
end

--- Activate projectionist features for current file
--- @param projections table: Projections configuration
--- @param file string: File path
M.activate = function(projections, file)
	file = utils.get_current_file(file)
	M.setup_buffer_settings(file)
end

--- Setup buffer-specific settings based on projections
--- @param file string: File path
M.setup_buffer_settings = function(file)
	file = utils.get_current_file(file)
	
	-- Set buffer variables for type and alternate
	local file_type = M.get_file_type(file)
	if file_type then
		vim.b.projectionist_type = file_type
	end

	local alternate = M.get_alternate_file(file)
	if alternate then
		vim.b.projectionist_alternate = alternate
	end

	-- Set up any projection-specific settings
	local raw_results = query_objects("*", file)
	for _, result in ipairs(raw_results) do
		local attrs = result.attrs
		local captures = result.captures

		-- Apply buffer settings
		if attrs.makeprg then
			local makeprg = patterns.expand_placeholders(attrs.makeprg, captures)
			vim.bo.makeprg = makeprg
		end

		if attrs.compiler then
			vim.cmd("compiler " .. attrs.compiler)
		end

		if attrs.path then
			local path = patterns.expand_placeholders(attrs.path, captures)
			vim.opt_local.path:append(path)
		end
		
		if attrs.suffixesadd then
			local suffixes = attrs.suffixesadd
			if type(suffixes) == "table" then
				for _, suffix in ipairs(suffixes) do
					vim.opt_local.suffixesadd:append(suffix)
				end
			else
				vim.opt_local.suffixesadd:append(suffixes)
			end
		end
	end
end

--- Cache management

--- Invalidate projectionist cache
M.invalidate_cache = function()
	config.clear_cache()
end

--- Compatibility functions for vim-projectionist

--- Get heuristic value (compatibility)
--- @param key string: Heuristic key
--- @param file string|nil: File path
--- @return any: Heuristic value
M.heuristic = function(key, file)
	return M.query_raw(key, file)
end

--- Get configuration (compatibility)
--- @return table: Current configuration
M.get_config = function()
	return M._config
end

--- Get heuristics for file (compatibility)
--- @param file string|nil: File path
--- @return table: Active heuristics
M.get_heuristics = function(file)
	return M.get_projections(file)
end

return M