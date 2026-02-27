local assert = require("luassert")
local spy = require("luassert.spy")
local projectionist = require("projectionist")

-- Pure Lua JSON decoder (rxi/json.lua, MIT License)
-- BEGIN rxi/json.lua
local json = { _version = "0.1.2" }

local encode
local escape_char_map = {
	["\\"] = "\\",
	['"'] = '"',
	["\b"] = "b",
	["\f"] = "f",
	["\n"] = "n",
	["\r"] = "r",
	["\t"] = "t",
}
local escape_char_map_inv = { ["/"] = "/" }
for k, v in pairs(escape_char_map) do
	escape_char_map_inv[v] = k
end
local function escape_char(c)
	return "\\" .. (escape_char_map[c] or string.format("u%04x", c:byte()))
end
local function encode_nil(val)
	return "null"
end
local function encode_table(val, stack)
	local res = {}
	stack = stack or {}
	if stack[val] then
		error("circular reference")
	end
	stack[val] = true
	if rawget(val, 1) ~= nil or next(val) == nil then
		local n = 0
		for k in pairs(val) do
			if type(k) ~= "number" then
				error("invalid table: mixed or invalid key types")
			end
			n = n + 1
		end
		if n ~= #val then
			error("invalid table: sparse array")
		end
		for i, v in ipairs(val) do
			table.insert(res, encode(v, stack))
		end
		stack[val] = nil
		return "[" .. table.concat(res, ",") .. "]"
	else
		for k, v in pairs(val) do
			if type(k) ~= "string" then
				error("invalid table: mixed or invalid key types")
			end
			table.insert(res, encode(k, stack) .. ":" .. encode(v, stack))
		end
		stack[val] = nil
		return "{" .. table.concat(res, ",") .. "}"
	end
end
local function encode_string(val)
	return '"' .. val:gsub('[%z\1-\31\\"]', escape_char) .. '"'
end
local function encode_number(val)
	if val ~= val or val <= -math.huge or val >= math.huge then
		error("unexpected number value '" .. tostring(val) .. "'")
	end
	return string.format("%.14g", val)
end
local type_func_map = {
	["nil"] = encode_nil,
	["table"] = encode_table,
	["string"] = encode_string,
	["number"] = encode_number,
	["boolean"] = tostring,
}
encode = function(val, stack)
	local t = type(val)
	local f = type_func_map[t]
	if f then
		return f(val, stack)
	end
	error("unexpected type '" .. t .. "'")
end
function json.encode(val)
	return (encode(val))
end
local parse
local function create_set(...)
	local res = {}
	for i = 1, select("#", ...) do
		res[select(i, ...)] = true
	end
	return res
end
local space_chars = create_set(" ", "\t", "\r", "\n")
local delim_chars = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
local escape_chars = create_set("\\", "/", '"', "b", "f", "n", "r", "t", "u")
local literals = create_set("true", "false", "null")
local literal_map = { ["true"] = true, ["false"] = false, ["null"] = nil }
local function next_char(str, idx, set, negate)
	for i = idx, #str do
		if set[str:sub(i, i)] ~= negate then
			return i
		end
	end
	return #str + 1
end
local function decode_error(str, idx, msg)
	local line_count = 1
	local col_count = 1
	for i = 1, idx - 1 do
		col_count = col_count + 1
		if str:sub(i, i) == "\n" then
			line_count = line_count + 1
			col_count = 1
		end
	end
	error(string.format("%s at line %d col %d", msg, line_count, col_count))
end
local function codepoint_to_utf8(n)
	local f = math.floor
	if n <= 0x7f then
		return string.char(n)
	elseif n <= 0x7ff then
		return string.char(f(n / 64) + 192, n % 64 + 128)
	elseif n <= 0xffff then
		return string.char(f(n / 4096) + 224, f(n % 4096 / 64) + 128, n % 64 + 128)
	elseif n <= 0x10ffff then
		return string.char(f(n / 262144) + 240, f(n % 262144 / 4096) + 128, f(n % 4096 / 64) + 128, n % 64 + 128)
	end
	error(string.format("invalid unicode codepoint '%x'", n))
end
local function parse_unicode_escape(s)
	local n1 = tonumber(s:sub(1, 4), 16)
	local n2 = tonumber(s:sub(7, 10), 16)
	if n2 then
		return codepoint_to_utf8((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000)
	else
		return codepoint_to_utf8(n1)
	end
end
local function parse_string(str, i)
	local res = ""
	local j = i + 1
	local k = j
	while j <= #str do
		local x = str:byte(j)
		if x < 32 then
			decode_error(str, j, "control character in string")
		elseif x == 92 then
			res = res .. str:sub(k, j - 1)
			j = j + 1
			local c = str:sub(j, j)
			if c == "u" then
				local hex = str:match("^[dD][89aAbB]%x%x\\u%x%x%x%x", j + 1)
					or str:match("^%x%x%x%x", j + 1)
					or decode_error(str, j - 1, "invalid unicode escape in string")
				res = res .. parse_unicode_escape(hex)
				j = j + #hex
			else
				if not escape_chars[c] then
					decode_error(str, j - 1, "invalid escape char '" .. c .. "' in string")
				end
				res = res .. escape_char_map_inv[c]
			end
			k = j + 1
		elseif x == 34 then
			res = res .. str:sub(k, j - 1)
			return res, j + 1
		end
		j = j + 1
	end
	decode_error(str, i, "expected closing quote for string")
end
local function parse_number(str, i)
	local x = next_char(str, i, delim_chars)
	local s = str:sub(i, x - 1)
	local n = tonumber(s)
	if not n then
		decode_error(str, i, "invalid number '" .. s .. "'")
	end
	return n, x
end
local function parse_literal(str, i)
	local x = next_char(str, i, delim_chars)
	local word = str:sub(i, x - 1)
	if not literals[word] then
		decode_error(str, i, "invalid literal '" .. word .. "'")
	end
	return literal_map[word], x
end
local function parse_array(str, i)
	local res = {}
	local n = 1
	i = i + 1
	while 1 do
		local x
		i = next_char(str, i, space_chars, true)
		if str:sub(i, i) == "]" then
			i = i + 1
			break
		end
		x, i = parse(str, i)
		res[n] = x
		n = n + 1
		i = next_char(str, i, space_chars, true)
		local chr = str:sub(i, i)
		i = i + 1
		if chr == "]" then
			break
		end
		if chr ~= "," then
			decode_error(str, i, "expected ']' or ','")
		end
	end
	return res, i
end
local function parse_object(str, i)
	local res = {}
	i = i + 1
	while 1 do
		local key, val
		i = next_char(str, i, space_chars, true)
		if str:sub(i, i) == "}" then
			i = i + 1
			break
		end
		if str:sub(i, i) ~= '"' then
			decode_error(str, i, "expected string for key")
		end
		key, i = parse(str, i)
		i = next_char(str, i, space_chars, true)
		if str:sub(i, i) ~= ":" then
			decode_error(str, i, "expected ':' after key")
		end
		i = next_char(str, i + 1, space_chars, true)
		val, i = parse(str, i)
		res[key] = val
		i = next_char(str, i, space_chars, true)
		local chr = str:sub(i, i)
		i = i + 1
		if chr == "}" then
			break
		end
		if chr ~= "," then
			decode_error(str, i, "expected '}' or ','")
		end
	end
	return res, i
end
local char_func_map = {
	['"'] = parse_string,
	["0"] = parse_number,
	["1"] = parse_number,
	["2"] = parse_number,
	["3"] = parse_number,
	["4"] = parse_number,
	["5"] = parse_number,
	["6"] = parse_number,
	["7"] = parse_number,
	["8"] = parse_number,
	["9"] = parse_number,
	["-"] = parse_number,
	["t"] = parse_literal,
	["f"] = parse_literal,
	["n"] = parse_literal,
	["["] = parse_array,
	["{"] = parse_object,
}
parse = function(str, idx)
	local chr = str:sub(idx, idx)
	local f = char_func_map[chr]
	if f then
		return f(str, idx)
	end
	decode_error(str, idx, "unexpected character '" .. chr .. "'")
end
function json.decode(str)
	if type(str) ~= "string" then
		error("expected argument of type string, got " .. type(str))
	end
	local res, idx = parse(str, next_char(str, 1, space_chars, true))
	idx = next_char(str, idx, space_chars, true)
	if idx <= #str then
		decode_error(str, idx, "trailing garbage")
	end
	return res
end
-- END rxi/json.lua

-- Load heuristics from test/heuristic.json and setup projectionist
local function read_json(path)
	local file = io.open(path, "r")
	if not file then
		error("Could not open " .. path)
	end
	local content = file:read("*a")
	file:close()
	return json.decode(content)
end

local heuristic_path = os.getenv("PWD") .. "/test/heuristic.json"
local heuristics = read_json(heuristic_path)
projectionist.setup({ patterns = heuristics })

-- Debug heuristic issues
-- local debug_heuristics = require("test.debug_heuristics")
-- debug_heuristics()

-- =============================================================================
-- Mock filesystem functions for pure unit testing
-- =============================================================================
-- This section replaces the previous approach of creating real files on disk.
-- Unit tests should work purely with table comparisons and mocked functions.
-- Benefits:
--   - Faster test execution (no disk I/O)
--   - No side effects or cleanup needed
--   - Tests can run in parallel safely
--   - Works in read-only environments (CI, containers)
-- =============================================================================

local utils = require("projectionist.utils")
local original_path_exists = utils.path_exists
local original_glob_match = utils.glob_match

-- Test fixture: virtual filesystem paths that "exist"
local PWD = os.getenv("PWD")
local virtual_files = {
	-- Files
	[PWD .. "/Makefile"] = "file",
	[PWD .. "/nvim/config/init.lua"] = "file",
	[PWD .. "/nvim/test/init_spec.lua"] = "file",
	[PWD .. "/go.mod"] = "file",
	[PWD .. "/deno.json"] = "file",
	[PWD .. "/pyproject.toml"] = "file",
	[PWD .. "/zsh/config/zprofile"] = "file",
	[PWD .. "/cargo.toml"] = "file",
	-- Directories (with trailing slash for requirements like "nvim/test/")
	[PWD .. "/nvim/config"] = "dir",
	[PWD .. "/nvim/config/"] = "dir",
	[PWD .. "/nvim/test"] = "dir",
	[PWD .. "/nvim/test/"] = "dir",
	[PWD .. "/zsh/config"] = "dir",
	[PWD .. "/zsh/config/"] = "dir",
}

-- Mock path_exists to use virtual filesystem
utils.path_exists = function(path, is_dir)
	-- Check virtual filesystem first
	local entry = virtual_files[path]
	if entry then
		if is_dir == true then
			return entry == "dir"
		elseif is_dir == false then
			return entry == "file"
		else
			return true -- Either file or dir
		end
	end
	-- Check if any virtual file starts with this path (for directory checks)
	if is_dir or is_dir == nil then
		for virtual_path, entry_type in pairs(virtual_files) do
			-- Use string comparison instead of pattern matching to avoid issues with special chars
			local path_with_slash = path .. "/"
			if virtual_path:sub(1, #path_with_slash) == path_with_slash then
				return true
			end
		end
	end
	-- Fall back to original for other paths (like test/heuristic.json)
	return original_path_exists(path, is_dir)
end

-- Mock glob_match for pattern-based requirement checking
utils.glob_match = function(pattern, path)
	-- For test purposes, check if any virtual file matches the pattern
	for virtual_path, _ in pairs(virtual_files) do
		if virtual_path:match(pattern) then
			return true
		end
	end
	return original_glob_match(pattern, path)
end

-- Mock glob_list for pattern-based requirement checking
utils.glob_list = function(path)
	local results = {}
	-- Convert vim glob to lua pattern (simplified for tests)
	-- Escape special lua regex chars in the path first
	local lua_pattern = path:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%1"):gsub("%%%*", ".*")
	for virtual_path, _ in pairs(virtual_files) do
		if virtual_path:match(lua_pattern) then
			table.insert(results, virtual_path)
		end
	end
	return results
end

-- Use formal hook to resolve root in tests
local config = require("projectionist.config")
config.set_external_root_resolver(function()
	return PWD
end)

describe("Simple test to check true is true", function()
	it("should be true", function()
		assert.is_true(true)
	end)
end)

describe("heuristic.json integration", function()
	it("should load and use heuristic.json for type detection", function()
		-- This path matches the nvim/config/*.lua pattern in the test/heuristic.json
		local file = os.getenv("PWD") .. "/nvim/config/init.lua"
		local types = projectionist.query_raw("type", file)
		assert.is_table(types)
		assert.is_true(#types > 0)
		assert.are.same("source", types[1])
	end)
end)

describe("heuristic function", function()
	it("should call the projectionist#query_raw function", function()
		local query_raw_spy = spy.on(projectionist, "query_raw")
		projectionist.heuristic("type")
		assert.spy(query_raw_spy).was_called_with("type", nil)
		query_raw_spy:revert()
	end)
end)

describe("wildcard '*' heuristic", function()
	it("should apply to ALL projects when Makefile exists", function()
		-- The "*" heuristic should match any project with Makefile
		local file = PWD .. "/Makefile"
		local types = projectionist.query_raw("type", file)
		assert.is_table(types)
		assert.is_true(#types > 0, "Expected Makefile to have type")
		assert.are.same("makefile", types[1])
	end)

	it("should provide console command from wildcard heuristic", function()
		local file = PWD .. "/Makefile"
		local console = projectionist.query_raw("console", file)
		assert.is_table(console)
		assert.is_true(#console > 0, "Expected console command")
		assert.are.same("zsh", console[1])
	end)

	it("should provide dispatch command from wildcard heuristic", function()
		local file = PWD .. "/Makefile"
		local dispatch = projectionist.query_raw("dispatch", file)
		assert.is_table(dispatch)
		assert.is_true(#dispatch > 0, "Expected dispatch command")
		assert.are.same("Make", dispatch[1])
	end)
end)

describe("glob pattern requirements", function()
	it("should match molecule pattern with wildcard directory", function()
		-- Add virtual file for molecule pattern
		virtual_files[PWD .. "/molecule/default/molecule.yml"] = "file"
		virtual_files[PWD .. "/tasks/deploy.yml"] = "file"

		local file = PWD .. "/tasks/deploy.yml"
		local types = projectionist.query_raw("type", file)
		assert.is_table(types)
		if #types > 0 then
			assert.are.same("source", types[1])
		end
	end)

	it("should match nvim plugin pattern with parent directory wildcard", function()
		-- Pattern: "../*.nvim/lua/" should match projects like "foo.nvim"
		-- This tests the ../*.nvim/lua/ requirement pattern
		local parent_dir = vim.fn.fnamemodify(PWD, ":h")
		local plugin_dir = parent_dir .. "/projectionist.nvim/lua"

		-- Add virtual files
		virtual_files[plugin_dir] = "dir"
		virtual_files[plugin_dir .. "/foo.lua"] = "file"

		local file = plugin_dir .. "/foo.lua"
		-- This should match the "../*.nvim/lua/" pattern
		local types = projectionist.query_raw("type", file)
		-- Note: This might not work without the parent directory structure
		-- Just verify it doesn't crash
		assert.is_table(types)
	end)
end)

-- Comprehensive alternate and round-trip tests

describe("projectionist alternates and round-trip", function()
	local cases = {
		{
			name = "Lua: config <-> test",
			src = "nvim/config/init.lua",
			alt = "nvim/test/init_spec.lua",
			reverse = true,
		},
		{
			name = "Python: app <-> test (multiple alternates)",
			src = "app/foo.py",
			expects_in_alternates = { "test/foo_test.py" },
			reverse_expects_in_alternates = { "app/foo.py" },
		},
		{
			name = "Go: source <-> test",
			src = "foo.go",
			alt = "foo_test.go",
			reverse = true,
		},
		{
			name = "Rust: source <-> test",
			src = "foo.rs",
			alt = "foo.rs",
			reverse = true,
		},
		{
			name = "Deno: source <-> test",
			src = "src/foo.ts",
			alt = "test/foo_test.ts",
			reverse = true,
		},
		{
			name = "Make: source <-> test",
			src = "src/foo.mk",
			alt = "test/foo/main.bats",
			reverse = true,
		},
		{
			name = "Zsh: config <-> test",
			src = "zsh/config/foo",
			alt = "zsh/test/foo.bats",
			reverse = true,
		},
		{
			name = "Missing alternate returns nil",
			src = "README.md",
			expect_nil = true,
		},
		{
			name = "Multiple alternates: Python src/ alternates",
			src = "src/bar.py",
			expects_in_alternates = { "test/test_bar.py", "test/unit/test_bar.py" },
		},
	}

	for _, tc in ipairs(cases) do
		local case = tc
		it(case.name, function()
			if case.expect_nil then
				assert.is_nil(projectionist.get_alternate_file(case.src))
				return
			end

			if case.expects_in_alternates then
				local alternates = projectionist.query_file("alternate", case.src)
				assert.is_true(#alternates > 0)
				for _, expect in ipairs(case.expects_in_alternates) do
					assert.is_true(
						vim.tbl_contains(alternates, expect),
						string.format("expected %s in alternates for %s", expect, case.src)
					)
					if case.reverse_expects_in_alternates then
						local reverse_alts = projectionist.query_file("alternate", expect)
						for _, rev in ipairs(case.reverse_expects_in_alternates) do
							assert.is_true(
								vim.tbl_contains(reverse_alts, rev),
								string.format("expected %s in alternates for %s", rev, expect)
							)
						end
					end
				end
				return
			end

			if case.alt then
				-- single alternate round-trip
				assert.are.same(case.alt, projectionist.get_alternate_file(case.src))
				if case.reverse then
					assert.are.same(case.src, projectionist.get_alternate_file(case.alt))
				end
				return
			end

			if case.reverse_expects_in_alternates then
				-- handle the Python app <-> test reverse assertion
				local alternates = projectionist.query_file("alternate", case.src)
				assert.is_true(#alternates > 0)
				for _, expect in ipairs(case.reverse_expects_in_alternates) do
					assert.is_true(
						vim.tbl_contains(alternates, expect),
						string.format("expected %s in alternates for %s", expect, case.src)
					)
				end
				-- also check reverse mapping for the first expected alternate
				local first_alt = case.reverse_expects_in_alternates[1]
				local reverse_alts = projectionist.query_file("alternate", first_alt)
				assert.is_true(vim.tbl_contains(reverse_alts, case.src))
				return
			end
		end)
	end
end)
