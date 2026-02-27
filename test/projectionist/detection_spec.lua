local assert = require("luassert")
local projectionist = require("projectionist")
local utils = require("projectionist.utils")

-- Mock filesystem functions

-- Test fixture: virtual filesystem
local PWD = "/tmp/project"
local virtual_files = {
	-- Root markers
	[PWD .. "/.git"] = "dir",
	-- Nested project markers (Makefile) that should be ignored as root
	[PWD .. "/app/Makefile"] = "file",
	-- Target file
	[PWD .. "/app/foo.py"] = "file",
	-- Dirs
	[PWD] = "dir",
	[PWD .. "/app"] = "dir",
}

-- Mock path_exists
utils.path_exists = function(path, is_dir)
	-- Normalize path (remove trailing slash for lookup)
	local lookup_path = path:match("^(.*)/$") or path

	-- Check virtual filesystem first
	local entry = virtual_files[lookup_path]
	if entry then
		if is_dir == true then
			return entry == "dir"
		elseif is_dir == false then
			return entry == "file"
		else
			return true
		end
	end

	-- Check parent dirs for generic directory existence checks
	-- This ensures that checks for /tmp/project, /tmp/project/app return true
	if is_dir or is_dir == nil then
		for virtual_path, _ in pairs(virtual_files) do
			-- If checking /foo/bar and we have /foo/bar/baz, return true
			if virtual_path:sub(1, #path + 1) == path .. "/" then
				return true
			end
			-- Exact match handled above
		end
	end
	return false
end

-- Clear cache before tests
projectionist.invalidate_cache()

describe("Project root detection", function()
	it("should ignore Makefile in subdirectory and find .git root", function()
		-- Ensure clean state
		require("projectionist.config").set_external_root_resolver(nil)
		projectionist.invalidate_cache()

		-- Define heuristics for the root
		local test_heuristics = {
			[".git/"] = {
				["app/*.py"] = { type = "source" },
			},
		}
		projectionist.setup({ heuristics = test_heuristics })

		local file = PWD .. "/app/foo.py"

		-- 1. Check Root Detection
		local root = projectionist.get_project_root(file)
		assert.are.same(PWD, root, "Should detect git root, ignoring nested Makefile")

		-- 2. Check Relative Path
		local relative = projectionist.get_relative_path(file)
		assert.are.same("app/foo.py", relative, "Relative path should be from git root")

		-- 3. Check Projection Query
		local types = projectionist.query_raw("type", file)
		assert.are.same(1, #types, "Should match app/*.py pattern")
		if #types > 0 then
			assert.are.same("source", types[1])
		end
	end)
end)
