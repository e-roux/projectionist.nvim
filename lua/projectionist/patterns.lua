--- @class ProjectionistPatterns
--- Pattern matching and placeholder expansion for projectionist.nvim
local M = {}

--- Convert vim glob pattern to lua pattern with capture groups
--- @param pattern string: Vim glob pattern
--- @return string: Lua pattern with captures
--- @return number: Number of capture groups
M.glob_to_pattern = function(pattern)
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
M.expand_placeholders = function(template, captures)
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
	}

	-- Apply all expansions
	for placeholder, expansion_func in pairs(expansions) do
		result = result:gsub(vim.pesc(placeholder), expansion_func)
	end

	return result
end

--- Test if a file path matches a glob pattern
--- @param pattern string: Glob pattern to test
--- @param file_path string: File path to test against
--- @return table|nil: Match result with pattern, captures, and file_path, or nil if no match
M.match_pattern = function(pattern, file_path)
	local lua_pattern, capture_count = M.glob_to_pattern(pattern)
	local captures = { file_path:match(lua_pattern) }

	-- Check if we got the expected number of captures
	if #captures == capture_count and captures[1] then
		return {
			pattern = pattern,
			captures = captures,
			file_path = file_path,
		}
	end

	return nil
end

--- Test multiple patterns against a file path and return all matches
--- @param patterns table: Array of glob patterns
--- @param file_path string: File path to test
--- @return table: Array of match results, sorted by specificity
M.match_patterns = function(patterns, file_path)
	local matches = {}

	for _, pattern in ipairs(patterns) do
		local match = M.match_pattern(pattern, file_path)
		if match then
			table.insert(matches, match)
		end
	end

	-- Sort by pattern specificity (fewer wildcards = more specific)
	table.sort(matches, function(a, b)
		local a_wildcards = select(2, a.pattern:gsub("%*", ""))
		local b_wildcards = select(2, b.pattern:gsub("%*", ""))
		if a_wildcards ~= b_wildcards then
			return a_wildcards < b_wildcards
		end
		return #a.pattern > #b.pattern
	end)

	return matches
end

return M