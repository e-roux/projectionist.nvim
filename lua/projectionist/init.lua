--- @class Projectionist
--- Modern Lua port of vim-projectionist for Neovim
local M = {}

-- Internal state
M._config = {}
M._projections = {}
M._roots = {}

--- Utility functions
local function starts_with(str, prefix)
	return str:sub(1, #prefix) == prefix
end

local function ends_with(str, suffix)
	return str:sub(-#suffix) == suffix
end

local function path_join(...)
	local parts = { ... }
	local result = table.concat(parts, "/")
	return result:gsub("//+", "/")
end

local function is_absolute(path)
	return path:match("^/") or path:match("^%a:")
end

--- Convert vim glob pattern to lua pattern with capture groups
--- @param pattern string: Vim glob pattern
--- @return string: Lua pattern with captures
--- @return number: Number of capture groups
local function glob_to_pattern(pattern)
	local capture_count = 0
	local lua_pattern = pattern
		:gsub("%%", "%%%%")
		:gsub("%.", "%%.")
		:gsub("%+", "%%+")
		:gsub("%-", "%%-")
		:gsub("%^", "%%^")
		:gsub("%$", "%%$")
		:gsub("%(", "%%(")
		:gsub("%)", "%%)")
		:gsub("%[", "%%[")
		:gsub("%]", "%%]")

	-- Handle ** before * to avoid double replacement
	lua_pattern = lua_pattern:gsub("%*%*", function()
		capture_count = capture_count + 1
		return "([^%z]*)" -- Match any path including /
	end)

	lua_pattern = lua_pattern:gsub("%*", function()
		capture_count = capture_count + 1
		return "([^/]*)" -- Match single path segment
	end)

	return "^" .. lua_pattern .. "$", capture_count
end

--- Apply placeholder expansions to template string
--- @param template string: Template with placeholders
--- @param captures table: Captured values from pattern matching
--- @return string: Expanded template
local function expand_placeholders(template, captures)
	if not template or not captures then
		return template or ""
	end

	local result = template
	local capture_idx = 1

	-- Replace {} with sequential captures
	result = result:gsub("{}", function()
		local value = captures[capture_idx] or ""
		capture_idx = capture_idx + 1
		return value
	end)

	-- Get the last capture for basename/dirname operations
	local last_capture = captures[#captures] or ""

	-- Handle special placeholders
	local expansions = {
		["{basename}"] = function()
			return last_capture:match("([^/]*)$") or ""
		end,
		["{dirname}"] = function()
			local dirname = last_capture:match("^(.*)/[^/]*$")
			if dirname then
				return dirname
			else
				-- If no directory separator, dirname is the same as basename for compatibility
				return last_capture:match("([^/]*)$") or ""
			end
		end,
		["{dot}"] = function()
			return last_capture:gsub("/", ".")
		end,
		["{underscore}"] = function()
			return last_capture:gsub("/", "_")
		end,
		["{backslash}"] = function()
			return last_capture:gsub("/", "\\")
		end,
		["{colons}"] = function()
			return last_capture:gsub("/", "::")
		end,
		["{hyphenate}"] = function()
			return last_capture:gsub("_", "-")
		end,
		["{blank}"] = function()
			return last_capture:gsub("[_-]", " ")
		end,
		["{uppercase}"] = function()
			return last_capture:upper()
		end,
		["{camelcase}"] = function()
			local parts = vim.split(last_capture, "[/_-]")
			local result = parts[1] or ""
			for i = 2, #parts do
				result = result .. (parts[i]:sub(1, 1):upper() .. parts[i]:sub(2))
			end
			return result
		end,
		["{snakecase}"] = function()
			return last_capture:gsub("([a-z])([A-Z])", "%1_%2"):lower():gsub("/", "_")
		end,
		["{capitalize}"] = function()
			return last_capture:gsub("(%a)([^/]*)", function(first, rest)
				return first:upper() .. rest
			end)
		end,
		["{singular}"] = function()
			-- Simple singularization - can be enhanced
			return last_capture:gsub("s$", "")
		end,
		["{plural}"] = function()
			-- Simple pluralization - can be enhanced
			return last_capture .. "s"
		end,
		["{open}"] = "{",
		["{close}"] = "}",
		["{nothing}"] = "",
		["{vim}"] = last_capture,
	}

	for placeholder, func in pairs(expansions) do
		if type(func) == "function" then
			result = result:gsub(vim.pesc(placeholder), func)
		else
			result = result:gsub(vim.pesc(placeholder), func)
		end
	end

	return result
end

--- Get project root for a given file
--- @param file string|nil: File path (defaults to current buffer)
--- @return string|nil: Project root directory
M.get_project_root = function(file)
	file = file or vim.api.nvim_buf_get_name(0)
	if file == "" then
		file = vim.fn.getcwd()
	end

	local dir = vim.fs.dirname(file)

	-- Check cache first
	if M._roots[dir] then
		return M._roots[dir]
	end

	-- Walk up directories looking for project markers
	while dir and dir ~= "/" and dir ~= "" do
		-- Check for .projections.json, heuristic.json
		for _, marker in ipairs({ ".projections.json", "heuristic.json" }) do
			local marker_path = path_join(dir, marker)
			if vim.fn.filereadable(marker_path) == 1 then
				M._roots[vim.fs.dirname(file)] = dir
				return dir
			end
		end

		-- Check global heuristics
		local heuristics = M._config.heuristics or M._config.patterns
		if heuristics then
			for pattern, _ in pairs(heuristics) do
				if M.has_requirements(dir, pattern) then
					M._roots[vim.fs.dirname(file)] = dir
					return dir
				end
			end
		end

		-- Check default patterns
		local default_markers = { ".git", "package.json", "Cargo.toml", "go.mod", "pyproject.toml", "Makefile" }
		for _, marker in ipairs(default_markers) do
			local marker_path = path_join(dir, marker)
			if vim.fn.filereadable(marker_path) == 1 or vim.fn.isdirectory(marker_path) == 1 then
				M._roots[vim.fs.dirname(file)] = dir
				return dir
			end
		end

		local parent = vim.fs.dirname(dir)
		if parent == dir then
			break
		end
		dir = parent
	end

	return nil
end

--- Get relative path from project root
--- @param file string|nil: File path (defaults to current buffer)
--- @return string|nil: Relative path from project root
M.get_relative_path = function(file)
	file = file or vim.api.nvim_buf_get_name(0)
	local root = M.get_project_root(file)
	if not root or not starts_with(file, root) then
		return nil
	end

	return file:sub(#root + 2) -- +2 to skip the trailing slash
end

--- Check if directory has required files/patterns
--- @param dir string: Directory to check
--- @param requirements string: Requirements pattern (e.g. "Gemfile&lib/|*.gemspec")
--- @return boolean: True if requirements are met
M.has_requirements = function(dir, requirements)
	if not requirements or requirements == "" then
		return false
	end

	-- Split by | (OR conditions)
	for _, or_group in ipairs(vim.split(requirements, "|")) do
		local all_met = true

		-- Split by & (AND conditions)
		for _, requirement in ipairs(vim.split(or_group, "&")) do
			local negated = starts_with(requirement, "!")
			local test = negated and requirement:sub(2) or requirement
			local path = path_join(dir, test)

			local exists = false
			if test:match("%*") then
				-- Glob pattern
				exists = #vim.fn.glob(path) > 0
			elseif ends_with(test, "/") then
				-- Directory
				exists = vim.fn.isdirectory(path) == 1
			else
				-- File
				exists = vim.fn.filereadable(path) == 1
			end

			if negated then
				exists = not exists
			end

			if not exists then
				all_met = false
				break
			end
		end

		if all_met then
			return true
		end
	end

	return false
end

--- Load projections for a given file
--- @param file string|nil: File path (defaults to current buffer)
--- @return table|nil: Projections configuration
M.get_projections = function(file)
	file = file or vim.api.nvim_buf_get_name(0)
	local root = M.get_project_root(file)
	if not root then
		return nil
	end

	-- Check cache
	if M._projections and M._projections[root] then
		return M._projections[root]
	end

	local projections = {}

	-- 1. Load from .projections.json files (walking up from root)
	local dir = root
	while dir and dir ~= "/" do
		for _, filename in ipairs({ ".projections.json", "heuristic.json" }) do
			local json_file = path_join(dir, filename)
			if vim.fn.filereadable(json_file) == 1 then
				local ok, data = pcall(function()
					local content = table.concat(vim.fn.readfile(json_file), "\n")
					return vim.json.decode(content, { luanil = { object = true, array = true } })
				end)
				if ok and data and type(data) == "table" then
					if filename == "heuristic.json" then
						-- Handle heuristic.json: check requirements and apply matching projections
						for pattern, heuristic in pairs(data) do
							if M.has_requirements(root, pattern) then
								for proj_pattern, attrs in pairs(heuristic) do
									projections[proj_pattern] = attrs
								end
							end
						end
					else
						-- Handle .projections.json: direct mapping
						for pattern, attrs in pairs(data) do
							projections[pattern] = attrs
						end
					end
				end
			end
		end

		-- Also check test/ subdirectory for test heuristics
		if dir == root then
			local test_dir = path_join(dir, "test")
			for _, filename in ipairs({ "heuristic.json" }) do
				local json_file = path_join(test_dir, filename)
				if vim.fn.filereadable(json_file) == 1 then
					local ok, data = pcall(function()
						local content = table.concat(vim.fn.readfile(json_file), "\n")
						return vim.json.decode(content, { luanil = { object = true, array = true } })
					end)
					if ok and data and type(data) == "table" then
						-- Handle heuristic.json: check requirements and apply matching projections
						for pattern, heuristic in pairs(data) do
							if M.has_requirements(root, pattern) then
								for proj_pattern, attrs in pairs(heuristic) do
									projections[proj_pattern] = attrs
								end
							end
						end
					end
				end
			end
		end

		local parent = vim.fs.dirname(dir)
		if parent == dir then
			break
		end
		dir = parent
	end

	-- 2. Apply global heuristics
	local heuristics = M._config.heuristics or M._config.patterns
	if heuristics then
		for pattern, heuristic in pairs(heuristics) do
			if M.has_requirements(root, pattern) then
				for proj_pattern, attrs in pairs(heuristic) do
					projections[proj_pattern] = attrs
				end
			end
		end
	end

	-- Cache result
	M._projections = M._projections or {}
	M._projections[root] = projections

	return projections
end

--- Core query functions matching vim-projectionist API
--- Query raw projection data for a given key and file
--- @param key string: The projection key (e.g. 'type', 'alternate')
--- @param file string|nil: The file path (defaults to current buffer)
--- @return table: List of matching projection values (may be empty)
M.query_raw = function(key, file)
	file = file or vim.api.nvim_buf_get_name(0)
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
		local lua_pattern, capture_count = glob_to_pattern(pattern)
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

	-- Sort by pattern specificity (fewer wildcards = more specific)
	table.sort(results, function(a, b)
		local a_wildcards = select(2, a.pattern:gsub("%*", ""))
		local b_wildcards = select(2, b.pattern:gsub("%*", ""))
		if a_wildcards ~= b_wildcards then
			return a_wildcards < b_wildcards
		end
		return #a.pattern > #b.pattern
	end)

	-- Extract just the values for the final result
	local values = {}
	for _, match in ipairs(results) do
		table.insert(values, match.value)
	end

	return values
end

--- Internal function to get query objects with full details
--- @param key string: The projection key
--- @param file string|nil: The file path
--- @return table: List of match objects with value, captures, pattern, attrs
local function query_objects(key, file)
	file = file or vim.api.nvim_buf_get_name(0)
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
		local lua_pattern, capture_count = glob_to_pattern(pattern)
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

	-- Sort by pattern specificity (fewer wildcards = more specific)
	table.sort(results, function(a, b)
		local a_wildcards = select(2, a.pattern:gsub("%*", ""))
		local b_wildcards = select(2, b.pattern:gsub("%*", ""))
		if a_wildcards ~= b_wildcards then
			return a_wildcards < b_wildcards
		end
		return #a.pattern > #b.pattern
	end)

	return results
end

--- Query with placeholder expansion
--- @param key string: The projection key
--- @param expansions table|nil: Optional expansions override
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
				table.insert(results, expand_placeholders(v, captures))
			end
		else
			table.insert(results, expand_placeholders(value, captures))
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
	file = file or vim.api.nvim_buf_get_name(0)
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
	assert(type(opts) == "table", "projectionist.setup: opts must be a table")

	M._config = opts
	M._projections = {}
	M._roots = {}

	-- Register commands unless explicitly disabled
	if opts.commands ~= false then
		M.setup_commands()
	end

	-- Register autocmds unless explicitly disabled
	if opts.autocmds ~= false then
		M.setup_autocmds()
	end
end

--- Register all projectionist commands
M.setup_commands = function()
	-- Core navigation commands
	vim.api.nvim_create_user_command("A", function(cmd)
		M.cmd_alternate(cmd.args, "edit")
	end, { nargs = "?", complete = M.complete_projections })

	vim.api.nvim_create_user_command("AS", function(cmd)
		M.cmd_alternate(cmd.args, "split")
	end, { nargs = "?", complete = M.complete_projections })

	vim.api.nvim_create_user_command("AV", function(cmd)
		M.cmd_alternate(cmd.args, "vsplit")
	end, { nargs = "?", complete = M.complete_projections })

	vim.api.nvim_create_user_command("AT", function(cmd)
		M.cmd_alternate(cmd.args, "tabedit")
	end, { nargs = "?", complete = M.complete_projections })

	vim.api.nvim_create_user_command("AD", function(cmd)
		M.cmd_alternate(cmd.args, "read")
	end, { nargs = "?", complete = M.complete_projections })

	vim.api.nvim_create_user_command("AO", function(cmd)
		M.cmd_alternate(cmd.args, "drop")
	end, { nargs = "?", complete = M.complete_projections })

	-- Directory commands
	vim.api.nvim_create_user_command("Pcd", function(cmd)
		M.cmd_cd(cmd.args, "cd")
	end, { nargs = "?", complete = "dir" })

	vim.api.nvim_create_user_command("Plcd", function(cmd)
		M.cmd_cd(cmd.args, "lcd")
	end, { nargs = "?", complete = "dir" })

	vim.api.nvim_create_user_command("Ptcd", function(cmd)
		M.cmd_cd(cmd.args, "tcd")
	end, { nargs = "?", complete = "dir" })

	-- Aliases if not already defined
	if vim.fn.exists(":Cd") == 0 then
		vim.api.nvim_create_user_command("Cd", function(cmd)
			M.cmd_cd(cmd.args, "cd")
		end, { nargs = "?", complete = "dir" })
	end

	if vim.fn.exists(":Lcd") == 0 then
		vim.api.nvim_create_user_command("Lcd", function(cmd)
			M.cmd_cd(cmd.args, "lcd")
		end, { nargs = "?", complete = "dir" })
	end

	if vim.fn.exists(":Tcd") == 0 then
		vim.api.nvim_create_user_command("Tcd", function(cmd)
			M.cmd_cd(cmd.args, "tcd")
		end, { nargs = "?", complete = "dir" })
	end

	-- Project commands
	vim.api.nvim_create_user_command("ProjectDo", function(cmd)
		M.cmd_project_do(cmd.args)
	end, { nargs = "+", complete = "shellcmd" })

	vim.api.nvim_create_user_command("Console", function(cmd)
		M.cmd_console(cmd.args)
	end, { nargs = "*" })
end

--- Setup autocmds for automatic project detection
M.setup_autocmds = function()
	local group = vim.api.nvim_create_augroup("Projectionist", { clear = true })

	-- Detect projects on file events
	vim.api.nvim_create_autocmd({ "BufNewFile", "BufReadPost" }, {
		group = group,
		callback = function()
			M.detect()
		end,
	})

	-- Apply templates to new files
	vim.api.nvim_create_autocmd("BufNewFile", {
		group = group,
		callback = function()
			if M.get_projections() then
				M.apply_template()
			end
		end,
	})

	-- Reload on .projections.json changes
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		pattern = ".projections.json",
		callback = function()
			M.invalidate_cache()
			M.detect()
		end,
	})
end

--- Command implementations

--- Execute alternate command
--- @param args string: Command arguments
--- @param cmd string: Edit command (edit, split, vsplit, etc.)
M.cmd_alternate = function(args, cmd)
	if args and args ~= "" then
		-- Navigate to specific file pattern
		local files = M.query_file("*", nil, nil) -- Get all projections
		local matching = {}

		for _, file in ipairs(files) do
			if file:match(args) then
				table.insert(matching, file)
			end
		end

		if #matching > 0 then
			local file = matching[1]
			M.edit_file(file, cmd)
		else
			vim.notify("No matches for: " .. args, vim.log.levels.WARN)
		end
	else
		-- Use alternate file
		local alt = M.get_alternate_file()
		if alt then
			M.edit_file(alt, cmd)
		else
			vim.notify("No alternate file found", vim.log.levels.WARN)
		end
	end
end

--- Change to project directory
--- @param args string: Optional subdirectory
--- @param cmd string: cd command (cd, lcd, tcd)
M.cmd_cd = function(args, cmd)
	local root = M.get_project_root()
	if not root then
		vim.notify("Not in a project", vim.log.levels.WARN)
		return
	end

	local target = root
	if args and args ~= "" then
		target = path_join(root, args)
	end

	vim.cmd(cmd .. " " .. vim.fn.fnameescape(target))
end

--- Execute command in project root
--- @param args string: Command to execute
M.cmd_project_do = function(args)
	local root = M.get_project_root()
	if not root then
		vim.notify("Not in a project", vim.log.levels.WARN)
		return
	end

	local cwd = vim.fn.getcwd()
	vim.cmd("cd " .. vim.fn.fnameescape(root))

	local ok, result = pcall(vim.cmd, args)

	vim.cmd("cd " .. vim.fn.fnameescape(cwd))

	if not ok then
		vim.notify("Command failed: " .. result, vim.log.levels.ERROR)
	end
end

--- Start console/REPL
--- @param args string: Optional arguments
M.cmd_console = function(args)
	local console_cmd = M.query_scalar("console")
	if not console_cmd then
		vim.notify("No console command defined", vim.log.levels.WARN)
		return
	end

	local cmd = console_cmd
	if args and args ~= "" then
		cmd = cmd .. " " .. args
	end

	vim.cmd("terminal " .. cmd)
end

--- Utility functions

--- Edit file with given command
--- @param file string: File path
--- @param cmd string: Edit command
M.edit_file = function(file, cmd)
	if cmd == "read" then
		vim.cmd("read " .. vim.fn.fnameescape(file))
	else
		vim.cmd(cmd .. " " .. vim.fn.fnameescape(file))
	end
end

--- Complete function for projections
--- @param arg_lead string: Current argument
--- @param cmd_line string: Full command line
--- @param cursor_pos number: Cursor position
--- @return table: Completion candidates
M.complete_projections = function(arg_lead, cmd_line, cursor_pos)
	local projections = M.get_projections()
	if not projections then
		return {}
	end

	local candidates = {}
	for pattern, attrs in pairs(projections) do
		if pattern:match(vim.pesc(arg_lead)) then
			table.insert(candidates, pattern)
		end
	end

	return candidates
end

--- Detect and activate projections for current buffer
M.detect = function(file)
	file = file or vim.api.nvim_buf_get_name(0)
	if file == "" then
		return
	end

	local projections = M.get_projections(file)
	if projections then
		M.activate(projections, file)
	end
end

--- Activate projections for buffer
--- @param projections table: Projections configuration
--- @param file string: File path
M.activate = function(projections, file)
	-- Set buffer variables for compatibility
	vim.b.projectionist = projections
	vim.b.projectionist_file = file

	-- Set up buffer-local settings
	M.setup_buffer_settings(file)
end

--- Setup buffer-local settings
--- @param file string: File path
M.setup_buffer_settings = function(file)
	local root = M.get_project_root(file)
	if not root then
		return
	end

	-- Set workspace folder
	vim.b.workspace_folder = root

	-- Set up tags if needed
	local tags_file = path_join(root, "tags")
	if vim.fn.filereadable(tags_file) == 1 then
		vim.bo.tags = tags_file
	end

	-- Set up path
	local path_dirs = M.query("path", nil, file)
	if #path_dirs > 0 then
		local paths = {}
		for _, dir in ipairs(path_dirs) do
			if not is_absolute(dir) then
				dir = path_join(root, dir)
			end
			table.insert(paths, dir)
		end
		vim.bo.path = vim.bo.path .. "," .. table.concat(paths, ",")
	end

	-- Set up make command
	local make_cmd = M.query_scalar("make", nil, file)
	if make_cmd then
		vim.bo.makeprg = make_cmd
	end

	-- Set dispatch commands
	local dispatch_cmd = M.query_scalar("dispatch", nil, file)
	if dispatch_cmd then
		vim.b.dispatch = dispatch_cmd
	end

	local start_cmd = M.query_scalar("start", nil, file)
	if start_cmd then
		vim.b.start = start_cmd
	end
end

--- Cache management

--- Invalidate all caches
M.invalidate_cache = function()
	M._projections = {}
	M._roots = {}
end

--- Compatibility layer

--- Legacy function for compatibility
--- @param key string: Projection key
--- @param file string|nil: File path
--- @return table: Results
M.heuristic = function(key, file)
	return M.query_raw(key, file)
end

--- Get config (for backward compatibility)
--- @return table: Current configuration
M.get_config = function()
	return M._config
end

--- Legacy function for compatibility
--- @param file string|nil: File path
--- @return table|nil: Heuristics
M.get_heuristics = function(file)
	return M.get_projections(file)
end

return M
