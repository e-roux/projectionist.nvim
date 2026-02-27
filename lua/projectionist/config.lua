--- @class ProjectionistConfig
--- Configuration loading and project detection for projectionist.nvim
local utils = require("projectionist.utils")
-- local patterns = require("projectionist.patterns")
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
		-- 1. Check for projection files
		for _, marker in ipairs({ ".projections.json", "projections.json", "heuristic.json" }) do
			local marker_path = utils.path_join(dir, marker)
			if utils.path_exists(marker_path, false) then
				M._roots[vim.fs.dirname(file)] = dir
				return dir
			end
		end

		-- 2. Check default markers
		local default_markers = { ".git", "package.json", "Cargo.toml", "go.mod", "pyproject.toml" }
		for _, marker in ipairs(default_markers) do
			local marker_path = utils.path_join(dir, marker)
			if utils.path_exists(marker_path) then
				M._roots[vim.fs.dirname(file)] = dir
				return dir
			end
		end

		-- 3. Check global heuristics (all sources)
		local heuristics = M.get_all_heuristics()
		for requirement, _ in pairs(heuristics) do
			-- Heuristics can be Direct Projection (Format B) or Requirement-keyed (Format A)
			-- Only Requirement-keyed ones can define a root
			if not M.is_direct_projection(heuristics[requirement]) then
				if M.has_requirements(dir, requirement) then
					M._roots[vim.fs.dirname(file)] = dir
					return dir
				end
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

	-- Compute start index after root, handling optional trailing slash
	local start_idx = #root + 1
	if file:sub(start_idx, start_idx) == "/" then
		start_idx = start_idx + 1
	end
	return file:sub(start_idx)
end

--- Check if directory has required files/patterns
--- @param dir string: Directory to check
--- @param requirements string: Requirements pattern (e.g. "Gemfile&lib/|*.gemspec")
--- @return boolean: True if requirements are met
M.has_requirements = function(dir, requirements)
	if not requirements or requirements == "" then
		return false
	end

	-- Split by | (OR conditions) - any group passing means success
	for _, or_group in ipairs(vim.split(requirements, "|")) do
		local all_met = true

		-- Split by & (AND conditions) - all must pass
		for _, test in ipairs(vim.split(or_group, "&")) do
			-- Check for negation prefix
			local negated = test:match("^!") ~= nil

			-- Extract the actual path (strip leading ! and /)
			-- Tim Pope's: matchstr(test, '[^!/].*') gets everything after leading ! or /
			local relative = test:match("^!?(.*)") or test

			-- Build full path: root + "/" + relative
			local full_path = utils.path_join(dir, relative)

			local found = false
			if relative:find("%*") then
				-- Glob pattern: check if any files match
				local matches = utils.glob_list(full_path)
				found = #matches > 0
			elseif relative:match("/$") then
				-- Directory check (path ends with /)
				-- Tim Pope uses: isdirectory(root . relative)
				found = utils.path_exists(full_path, true)
			else
				-- File check
				-- Tim Pope uses: filereadable(root . relative)
				found = utils.path_exists(full_path, false)
			end
			-- ...

			-- Apply negation: if negated and found, or not negated and not found, fail
			-- Tim Pope's: if test =~# '^!' ? found : !found then return 0
			if negated then
				if found then
					all_met = false
					break
				end
			else
				if not found then
					all_met = false
					break
				end
			end
		end

		if all_met then
			return true
		end
	end

	return false
end

--- Helper to merge projection attributes
local function merge_projections(target, source)
	if not source or type(source) ~= "table" then
		return
	end
	for pattern, attrs in pairs(source) do
		if type(attrs) == "table" then
			target[pattern] = target[pattern] or {}
			for k, v in pairs(attrs) do
				target[pattern][k] = v
			end
		end
	end
end

--- Get all configured heuristics from all sources
M.get_all_heuristics = function()
	local heuristics = {}
	-- 1. From setup()
	if M._config then
		for k, v in pairs(M._config.heuristics or M._config.patterns or {}) do
			heuristics[k] = v
		end
	end
	-- 2. From global Vim variables
	local vim_heuristics = vim.g.projectionist_heuristics or vim.g.projectionist_patterns
	if vim_heuristics then
		for k, v in pairs(vim_heuristics) do
			if heuristics[k] == nil then
				heuristics[k] = v
			end
		end
	end
	return heuristics
end

--- Check if a heuristic value represents a direct projection (Format B)
M.is_direct_projection = function(value)
	if type(value) ~= "table" then
		return false
	end
	local attr_keys = {
		type = true,
		alternate = true,
		console = true,
		dispatch = true,
		template = true,
		start = true,
		makeprg = true,
		make = true,
		path = true,
		suffixesadd = true,
		compiler = true,
	}
	for k, _ in pairs(value) do
		if type(k) == "string" and attr_keys[k] then
			return true
		end
	end
	return false
end

--- Load projections for a given file
--- @param file string|nil: File path
--- @return table|nil: Merged projections
M.get_projections = function(file)
	file = utils.get_current_file(file)
	local root = M._external_root_resolver and M._external_root_resolver(file) or M.get_project_root(file)
	if not root then
		return nil
	end

	if M._projections and M._projections[root] then
		return M._projections[root]
	end

	local projections = {}

	-- 1. Load from files (walking up from root)
	local dir = root
	while dir and dir ~= "/" do
		for _, filename in ipairs({ ".projections.json", "projections.json", "heuristic.json" }) do
			local json_file = utils.path_join(dir, filename)
			local data = utils.read_json(json_file)
			if data then
				if filename == "heuristic.json" then
					for req, h_proj in pairs(data) do
						if M.has_requirements(root, req) then
							merge_projections(projections, h_proj)
						end
					end
				else
					merge_projections(projections, data)
				end
			end
		end

		-- Special case for test/heuristic.json
		if dir == root then
			local data = utils.read_json(utils.path_join(dir, "test", "heuristic.json"))
			if data then
				for req, h_proj in pairs(data) do
					if M.has_requirements(root, req) then
						merge_projections(projections, h_proj)
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
	local heuristics = M.get_all_heuristics()
	for requirement, value in pairs(heuristics) do
		if M.is_direct_projection(value) then
			-- Format B: Direct Projection
			merge_projections(projections, { [requirement] = value })
		else
			-- Format A: Requirement-keyed
			if M.has_requirements(root, requirement) then
				merge_projections(projections, value)
			end
		end
	end

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
