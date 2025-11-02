--- @class ProjectionistConfig
--- Configuration loading and project detection for projectionist.nvim
local utils = require("projectionist.utils")
local M = {}

--- Internal state
M._roots = {}
M._projections = {}
M._config = {}
M._external_root_resolver = nil

--- Get project root for a given file
--- @param file string|nil: File path (defaults to current buffer)
--- @return string|nil: Project root directory
M.get_project_root = function(file)
	file = utils.get_current_file(file)
	local dir = vim.fs.dirname(file)

	-- Check cache first
	if M._roots[dir] then
		return M._roots[dir]
	end

	-- Walk up directories looking for project markers
	while dir and dir ~= "/" and dir ~= "" do
		-- Check for .projections.json, heuristic.json
		for _, marker in ipairs({ ".projections.json", "heuristic.json" }) do
			local marker_path = utils.path_join(dir, marker)
			if utils.path_exists(marker_path, false) then
				M._roots[vim.fs.dirname(file)] = dir
				return dir
			end
		end

		-- Check global heuristics
		local heuristics = M._config and (M._config.heuristics or M._config.patterns)
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
			local marker_path = utils.path_join(dir, marker)
			if utils.path_exists(marker_path) then
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
	file = utils.get_current_file(file)
	-- Use external root resolver if available, otherwise use internal one
	local root = M._external_root_resolver and M._external_root_resolver(file) or M.get_project_root(file)
	if not root or not utils.starts_with(file, root) then
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
			local req_path = utils.path_join(dir, requirement)
			local exists = false

			if requirement:find("%*") then
				-- Glob pattern
				exists = utils.glob_match(requirement, req_path)
			else
				-- Exact file/directory
				exists = utils.path_exists(req_path)
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
	file = utils.get_current_file(file)
	-- Use external root resolver if available, otherwise use internal one
	local root = M._external_root_resolver and M._external_root_resolver(file) or M.get_project_root(file)
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
			local json_file = utils.path_join(dir, filename)
			local data = utils.read_json(json_file)
			if data then
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

		-- Also check test/ subdirectory for test heuristics
		if dir == root then
			local test_dir = utils.path_join(dir, "test")
			for _, filename in ipairs({ "heuristic.json" }) do
				local json_file = utils.path_join(test_dir, filename)
				local data = utils.read_json(json_file)
				if data then
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

		local parent = vim.fs.dirname(dir)
		if parent == dir then
			break
		end
		dir = parent
	end

	-- 2. Apply global heuristics
	local heuristics = M._config and (M._config.heuristics or M._config.patterns)
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

--- Set global configuration
--- @param config table: Configuration object
M.set_config = function(config)
	M._config = config
end

--- Set external root resolver (for testing)
--- @param resolver function|nil: External root resolver function
M.set_external_root_resolver = function(resolver)
	M._external_root_resolver = resolver
end

--- Clear all caches
M.clear_cache = function()
	M._roots = {}
	M._projections = {}
end

return M
