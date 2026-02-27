--- @class ProjectionistPatterns
--- Pattern matching and placeholder expansion for projectionist.nvim
local utils = require("projectionist.utils")
local M = {}

--- Convert vim glob pattern to lua pattern with capture groups
--- @param pattern string: Vim glob pattern
--- @return string: Lua pattern with captures
--- @return number: Number of capture groups
M.glob_to_pattern = function(pattern)
	-- If pattern has only ONE asterisk and no double star, make it recursive like Vim-projectionist
	-- unless it's the only character
	local p = pattern
	if p ~= "*" and not p:find("%*%*") and select(2, p:gsub("%*", "")) == 1 then
		p = p:gsub("%*", "**/*")
	end

	local capture_count = 0
	local lua_pattern = p:gsub("%%", "%%%%")
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
	local double_star_token = "___DOUBLE_STAR___"
	lua_pattern = lua_pattern:gsub("%*%*", function()
		capture_count = capture_count + 1
		return double_star_token
	end)

	lua_pattern = lua_pattern:gsub("%*", function()
		capture_count = capture_count + 1
		return "([^/]*)" -- Match single segment
	end)

	-- Restore double star pattern
	lua_pattern = lua_pattern:gsub(double_star_token, "(.*)") -- Match any path including /

	return "^" .. lua_pattern .. "$", capture_count
end

--- Apply placeholder expansions using standard transformations
--- @param template string: Template with placeholders like {match|dot} or {}
--- @param match_or_captures any: The matched value (string) or captured groups (table)
--- @return string: Expanded template
M.expand_placeholders = function(template, match_or_captures)
	if not template or not match_or_captures then
		return template or ""
	end

	local match_val
	local captures

	if type(match_or_captures) == "string" then
		match_val = match_or_captures
		captures = { match_or_captures }
	else
		captures = match_or_captures
		match_val = captures[#captures] or ""
	end

	local result = template
	local capture_idx = 1

	-- Replace {} with sequential captures (Vim-style)
	-- But if there's only one capture, always use it
	result = result:gsub("{}", function()
		if #captures == 1 then
			return captures[1]
		end
		local value = captures[capture_idx] or ""
		capture_idx = capture_idx + 1
		return value
	end)

	-- Replace placeholders with transformations: {match|transformation}
	result = result:gsub("{([^{}]*)}", function(content)
		if content == "" then -- Already handled above?
			return "{}"
		end

		local parts = vim.split(content, "|")
		-- If it's a known transformation, treat first part as 'match' if it's not a capture index
		local value = match_val

		-- Check if first part is a number (capture index)
		local first = parts[1]
		if tonumber(first) then
			value = captures[tonumber(first)] or ""
			table.remove(parts, 1)
		elseif first == "match" or first == "basename" or first == "dirname" then
			-- 'match' is default. basename/dirname were legacy tokens
			if first == "basename" then
				value = M.transformations.basename(match_val)
			elseif first == "dirname" then
				value = M.transformations.dirname(match_val)
			end
			table.remove(parts, 1)
		end

		-- Apply transformations sequentially
		for _, transform in ipairs(parts) do
			if M.transformations[transform] then
				value = M.transformations[transform](value)
			end
		end

		return value
	end)

	return result
end

--- Standard transformations from projectionist.vim
M.transformations = {
	dot = function(input)
		return input:gsub("/", ".")
	end,
	underscore = function(input)
		return input:gsub("/", "_")
	end,
	backslash = function(input)
		return input:gsub("/", "\\")
	end,
	colons = function(input)
		return input:gsub("/", "::")
	end,
	hyphenate = function(input)
		return input:gsub("_", "-")
	end,
	blank = function(input)
		return input:gsub("[_-]", " ")
	end,
	uppercase = function(input)
		return input:upper()
	end,
	camelcase = function(input)
		return vim.fn.substitute(input, [[[_-]\(.\)]], [[\u\1]], "g")
	end,
	capitalize = function(input)
		return vim.fn.substitute(input, [[\%(^\|/\)\zs\(.\)]], [[\u\1]], "g")
	end,
	snakecase = function(input)
		local str = vim.fn.substitute(input, [[\v(\u+)(\u\l)]], [[\1_\2]], "g")
		str = vim.fn.substitute(str, [[\v(\l|\d)(\u)]], [[\1_\2]], "g")
		return str:lower()
	end,
	dirname = function(input)
		if not input:find("/") then
			return "."
		end
		return input:match("^(.*)/[^/]*$")
	end,
	basename = function(input)
		local b = input:match("([^/]*)$") or input
		return b:match("^(.*)%.[^.]*$") or b
	end,
	singular = function(input)
		return vim.fn
			.substitute(input, [[\v%([Mm]ov|[aeio])@<!ies$]], "ys", "")
			:gsub("ves$", "fs")
			:gsub("ices$", "exs")
			:gsub("s$", "")
	end,
	plural = function(input)
		return vim.fn.substitute(input, [[\v[aeio]@<!y$]], "ie", "") .. "s"
	end,
	open = function()
		return "{"
	end,
	close = function()
		return "}"
	end,
	nothing = function()
		return ""
	end,
	vim = function(input)
		return input
	end,
}

--- Port of Tim Pope's s:match from projectionist.vim (internal usage)
--- @param file string: The relative path to test
--- @param pattern string: The projection pattern
--- @return string: The matched value, or empty string if no match
M.vim_match = function(file, pattern)
	-- Support recursive transformation like vim-projectionist
	local p = pattern
	if p ~= "*" and not p:find("%*%*") and select(2, p:gsub("%*", "")) == 1 then
		p = p:gsub("%*", "**/*")
	end

	local parts = vim.split(p, "**", true)
	if #parts < 2 then
		return ""
	end

	local prefix = parts[1]:gsub("\\", "/")
	local rest = parts[2]
	local infix, suffix

	if rest:find("%*") then
		infix = rest:match("^(.*)%*"):gsub("\\", "/")
		suffix = rest:match("%*([^%*]*)$"):gsub("\\", "/")
	else
		infix = ""
		suffix = rest:gsub("\\", "/")
	end

	local f = file:gsub("\\", "/")
	if not utils.starts_with(f, prefix) or not utils.ends_with(f, suffix) then
		return ""
	end

	local match_val = f:sub(#prefix + 1, #f - #suffix)
	if infix == "/" then
		return match_val
	end

	local search_str = "/" .. match_val
	local pattern_regex = [[\V]] .. infix .. [[\ze[^/]*$]]
	local clean = vim.fn.substitute(search_str, pattern_regex, "/", ""):sub(2)

	return (clean == match_val) and "" or clean
end

return M
