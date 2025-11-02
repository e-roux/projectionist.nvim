--- @class ProjectionistUtils
--- Common utility functions for projectionist.nvim
local M = {}

--- Check if string starts with prefix
--- @param str string: String to check
--- @param prefix string: Prefix to match
--- @return boolean: True if str starts with prefix
M.starts_with = function(str, prefix)
	return str:sub(1, #prefix) == prefix
end

--- Check if string ends with suffix
--- @param str string: String to check
--- @param suffix string: Suffix to match
--- @return boolean: True if str ends with suffix
M.ends_with = function(str, suffix)
	return str:sub(-#suffix) == suffix
end

--- Join path components into a single path
--- @param ... string: Path components to join
--- @return string: Joined path
M.path_join = function(...)
	local parts = { ... }
	local result = table.concat(parts, "/")
	return result:gsub("//+", "/")
end

--- Check if path is absolute
--- @param path string: Path to check
--- @return boolean: True if path is absolute
M.is_absolute = function(path)
	return path:match("^/") or path:match("^%a:")
end

--- Get current file path or fallback to cwd
--- @param file string|nil: Optional file path
--- @return string: Resolved file path
M.get_current_file = function(file)
	file = file or vim.api.nvim_buf_get_name(0)
	if file == "" then
		file = vim.fn.getcwd()
	end
	return file
end

--- Sort results by pattern specificity
--- @param results table: Array of result objects with pattern field
--- @return table: Sorted results (most specific first)
M.sort_by_specificity = function(results)
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

--- Extract values from result objects
--- @param results table: Array of result objects with value field
--- @return table: Array of values
M.extract_values = function(results)
	local values = {}
	for _, match in ipairs(results) do
		table.insert(values, match.value)
	end
	return values
end

--- Check if file/directory exists
--- @param path string: Path to check
--- @param is_dir boolean|nil: True to check for directory, false for file, nil for either
--- @return boolean: True if exists
M.path_exists = function(path, is_dir)
	if is_dir == true then
		return vim.fn.isdirectory(path) == 1
	elseif is_dir == false then
		return vim.fn.filereadable(path) == 1
	else
		return vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1
	end
end

--- Read JSON file safely
--- @param path string: Path to JSON file
--- @return table|nil: Parsed JSON data or nil on error
M.read_json = function(path)
	if vim.fn.filereadable(path) ~= 1 then
		return nil
	end

	local ok, data = pcall(function()
		local content = table.concat(vim.fn.readfile(path), "\n")
		return vim.json.decode(content, { luanil = { object = true, array = true } })
	end)

	if ok and data and type(data) == "table" then
		return data
	end

	return nil
end

--- Check glob pattern
--- @param pattern string: Glob pattern
--- @param path string: Full path to test
--- @return boolean: True if pattern matches
M.glob_match = function(pattern, path)
	return #vim.fn.glob(pattern) > 0
end

return M
