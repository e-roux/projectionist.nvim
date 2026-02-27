--- @class Projectionist
--- Modern Lua port of vim-projectionist for Neovim
local M = {}

-- Version information for release-please
M._version = "0.2.0"

-- Import modules
local utils = require("projectionist.utils")
local patterns = require("projectionist.patterns")
local config = require("projectionist.config")

-- Expose internal state and functions from config module for compatibility
M.get_project_root = config.get_project_root
M.get_relative_path = config.get_relative_path
M.has_requirements = config.has_requirements
M.get_projections = config.get_projections

-- Set up config to use main module's get_project_root (for test overrides)
config.set_external_root_resolver(function(file)
	return M.get_project_root(file)
end)

--- Internal function to get query objects with full details
--- @param key string: The projection key
--- @param file string|nil: The file path
--- @return table: List of match objects with value, match, pattern, attrs
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

	-- Sort patterns by length descending
	local patterns_keys = vim.tbl_keys(projections)
	table.sort(patterns_keys, function(a, b)
		return #a > #b
	end)

	for _, pattern in ipairs(patterns_keys) do
		local attrs = projections[pattern]
		local match_val = ""
		local matched = false

		if pattern == "*" then
			matched = true
			match_val = relative_path
		elseif not pattern:find("%*") then
			-- Exact match
			matched = (pattern == relative_path)
			match_val = pattern
		else
			-- Wildcard match using Ported Vim logic
			match_val = patterns.vim_match(relative_path, pattern)
			matched = (match_val ~= "")
		end

		if matched and attrs[key] ~= nil then
			table.insert(results, {
				value = attrs[key],
				match = match_val,
				pattern = pattern,
				attrs = attrs,
			})
		end
	end

	return results
end

--- Core query functions matching vim-projectionist API
--- Query raw projection data for a given key and file
--- @param key string: The projection key (e.g. 'type', 'alternate')
--- @param file string|nil: The file path (defaults to current buffer)
--- @return table: List of matching projection values (may be empty)
M.query_raw = function(key, file)
	local raw_results = query_objects(key, file)
	return utils.extract_values(raw_results)
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
		local match = result.match

		if type(value) == "table" then
			for _, v in ipairs(value) do
				table.insert(results, patterns.expand_placeholders(v, match))
			end
		else
			table.insert(results, patterns.expand_placeholders(value, match))
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
	-- Normalize paths: remove double slashes and /./ segments
	for i, path in ipairs(results) do
		results[i] = path:gsub("//+", "/"):gsub("/%./", "/")
	end
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
	return M.query_scalar("type", file)
end

--- Get alternate file for current or specified file
--- @param file string|nil: File path (defaults to current buffer)
--- @return string|nil: Relative path to alternate file
M.get_alternate_file = function(file)
	local alternates = M.query_file("alternate", file)
	return alternates[1]
end

--- Get related files for current or specified file
--- @param file string|nil: File path (defaults to current buffer)
--- @return table: List of related file paths
M.get_related_files = function(file)
	return M.query_file("related", file)
end

--- Get template for current or specified file
--- @param file string|nil: File path (defaults to current buffer)
--- @return table|string|nil: Template content
M.get_template = function(file)
	return M.query_scalar("template", file)
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
M.setup = function(opts)
	opts = opts or {}

	-- Store configuration with backwards compatibility
	config.set_config(opts)
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

--- Inspect which patterns match a given file
--- Returns structured data about matching patterns, captures, and query results
--- @param file string|nil: File path (defaults to current buffer)
--- @return table: Information with file, root, relative_path, matches, and queries
M.inspect = function(file)
	file = utils.get_current_file(file)
	local root = M.get_project_root(file)
	local relative_path = M.get_relative_path(file)
	local projections = M.get_projections(file)

	-- Collect all global heuristics (setup + vim.g)
	local heuristics = {}
	if config._config then
		for k, v in pairs(config._config.heuristics or config._config.patterns or {}) do
			heuristics[k] = v
		end
	end
	local vim_heuristics = vim.g.projectionist_heuristics or vim.g.projectionist_patterns
	if vim_heuristics then
		for k, v in pairs(vim_heuristics) do
			if heuristics[k] == nil then
				heuristics[k] = v
			end
		end
	end

	local result = {
		file = file,
		root = root,
		relative_path = relative_path,
		matches = {},
		queries = {},
		projections = projections,
		heuristics = heuristics,
	}

	-- Add __tostring metamethod for pretty printing
	setmetatable(result, {
		__tostring = function(self)
			local lines = {}
			table.insert(lines, "=================================================")
			table.insert(lines, "Projectionist File Inspection")
			table.insert(lines, "=================================================")
			table.insert(lines, string.format("File: %s", self.file or "unknown"))
			table.insert(lines, string.format("Root: %s", self.root or "not found"))
			table.insert(lines, string.format("Relative: %s", self.relative_path or "n/a"))

			table.insert(lines, "\n--- Matching Patterns ---")
			if #self.matches == 0 then
				table.insert(lines, "No patterns match this file")
			else
				for i, match in ipairs(self.matches) do
					table.insert(lines, string.format("\n%d. Pattern: %s", i, match.pattern))
					if match.captures and #match.captures > 0 then
						-- The first capture is used for {} expansion
						table.insert(lines, string.format("   Match Segment: %s", vim.inspect(match.captures[1])))
					end
					table.insert(lines, "   Attributes:")
					local attr_keys = vim.tbl_keys(match.attributes)
					table.sort(attr_keys)
					for _, key in ipairs(attr_keys) do
						table.insert(lines, string.format("     %s: %s", key, vim.inspect(match.attributes[key])))
					end
				end
			end

			table.insert(lines, "\n--- Query Results ---")
			local query_keys = { "type", "alternate", "related", "template", "console", "dispatch", "start", "makeprg" }
			for _, key in ipairs(query_keys) do
				local value = self.queries[key]
				if value and (#value > 0 or type(value) ~= "table") then
					table.insert(lines, string.format("%s: %s", key, vim.inspect(value)))
				end
			end

			table.insert(lines, "\n--- Active Projections for Root ---")
			if not self.projections or next(self.projections) == nil then
				table.insert(lines, "No projections found for this root")
			else
				local patterns_list = vim.tbl_keys(self.projections)
				table.sort(patterns_list)
				for _, pattern in ipairs(patterns_list) do
					table.insert(lines, string.format("Pattern: %s", pattern))
				end
			end

			table.insert(lines, "\n--- Global Heuristics ---")
			if not self.heuristics or next(self.heuristics) == nil then
				table.insert(lines, "No global heuristics configured")
			else
				local h_keys = vim.tbl_keys(self.heuristics)
				table.sort(h_keys)

				local known_attrs = {
					type = true,
					alternate = true,
					console = true,
					dispatch = true,
					template = true,
					start = true,
					makeprg = true,
					make = true,
				}

				for _, req in ipairs(h_keys) do
					local value = self.heuristics[req]
					local is_direct = false
					if type(value) == "table" then
						for k, _ in pairs(value) do
							if type(k) == "string" and known_attrs[k] then
								is_direct = true
								break
							end
						end
					end

					if is_direct then
						table.insert(lines, string.format("Direct Projection: %s", req))
					else
						table.insert(lines, string.format("Requirement: %s", req))
						if type(value) == "table" then
							local sub_patterns = vim.tbl_keys(value)
							table.sort(sub_patterns)
							for _, p in ipairs(sub_patterns) do
								if type(p) == "string" and (p:find("%*") or p:find("/")) then
									table.insert(lines, string.format("  Pattern: %s", p))
								end
							end
						end
					end
				end
			end

			return table.concat(lines, "\n")
		end,
	})

	if not projections or not relative_path then
		return result
	end

	-- Find all matching patterns
	local patterns_keys = vim.tbl_keys(projections)
	table.sort(patterns_keys, function(a, b)
		return #a > #b
	end)

	for _, pattern in ipairs(patterns_keys) do
		local attrs = projections[pattern]
		local match_val = ""
		local matched = false

		if pattern == "*" then
			matched = true
			match_val = relative_path
		elseif not pattern:find("%*") then
			matched = (pattern == relative_path)
			match_val = pattern
		else
			match_val = patterns.vim_match(relative_path, pattern)
			matched = (match_val ~= "")
		end

		if matched then
			table.insert(result.matches, {
				pattern = pattern,
				captures = { match_val },
				attributes = attrs,
			})
		end
	end

	-- Matches are already sorted by pattern length decrementing from the loop
	-- Add query results
	result.queries = {
		type = M.query("type", nil, file),
		alternate = M.query("alternate", nil, file),
		related = M.query("related", nil, file),
		template = M.query("template", nil, file),
		console = M.query("console", nil, file),
		dispatch = M.query("dispatch", nil, file),
		start = M.query("start", nil, file),
		makeprg = M.query("makeprg", nil, file),
	}

	return result
end

return M
