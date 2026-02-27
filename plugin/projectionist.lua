-- Projectionist plugin initialization
-- Registers commands and autocmds
if vim.g.projectionist_loaded then
	return
end
vim.g.projectionist_loaded = 1

local projectionist = require("projectionist")
local utils = require("projectionist.utils")

--- Setup vim commands
local function setup_commands()
	vim.api.nvim_create_user_command("A", function(args)
		projectionist.cmd_alternate(args, "edit")
	end, {
		nargs = "*",
		complete = projectionist.complete_projections,
		desc = "Edit alternate file",
	})

	vim.api.nvim_create_user_command("AS", function(args)
		projectionist.cmd_alternate(args, "split")
	end, {
		nargs = "*",
		complete = projectionist.complete_projections,
		desc = "Split alternate file",
	})

	vim.api.nvim_create_user_command("AV", function(args)
		projectionist.cmd_alternate(args, "vsplit")
	end, {
		nargs = "*",
		complete = projectionist.complete_projections,
		desc = "Vertical split alternate file",
	})

	vim.api.nvim_create_user_command("AT", function(args)
		projectionist.cmd_alternate(args, "tabedit")
	end, {
		nargs = "*",
		complete = projectionist.complete_projections,
		desc = "Tab alternate file",
	})

	vim.api.nvim_create_user_command("Cd", function(args)
		projectionist.cmd_cd(args, "cd")
	end, {
		nargs = 0,
		desc = "Change to project root",
	})

	vim.api.nvim_create_user_command("Lcd", function(args)
		projectionist.cmd_cd(args, "lcd")
	end, {
		nargs = 0,
		desc = "Change to project root (local)",
	})

	vim.api.nvim_create_user_command("ProjectDo", function(args)
		projectionist.cmd_project_do(args)
	end, {
		nargs = "+",
		desc = "Execute command in project root",
	})

	vim.api.nvim_create_user_command("Console", function(args)
		projectionist.cmd_console(args)
	end, {
		nargs = 0,
		desc = "Open project console",
	})

	vim.api.nvim_create_user_command("Projectionist", function(args)
		local subcommand = args.fargs[1]
		local file_arg = args.fargs[2]

		if subcommand == "inspect" then
			-- Print using tostring metamethod
			print(tostring(projectionist.inspect(file_arg)))
		else
			vim.notify("Unknown Projectionist subcommand: " .. (subcommand or "nil"), vim.log.levels.ERROR)
		end
	end, {
		nargs = "+",
		complete = function(arg_lead, cmd_line, cursor_pos)
			local args = vim.split(cmd_line, "%s+", { trimempty = true })

			-- First argument: subcommand
			if #args <= 2 then
				local subcommands = { "inspect" }
				return vim.tbl_filter(function(cmd)
					return vim.startswith(cmd, arg_lead)
				end, subcommands)
			end

			-- Second argument: file completion for inspect
			if args[2] == "inspect" then
				-- Use built-in file completion
				return vim.fn.getcompletion(arg_lead, "file")
			end

			return {}
		end,
		desc = "Projectionist commands (inspect)",
	})
end

--- Setup autocmds for file detection and template application
local function setup_autocmds()
	local group = vim.api.nvim_create_augroup("projectionist", { clear = true })

	-- Detect projectionist files
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
		group = group,
		callback = function(ev)
			projectionist.detect(ev.file)
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
				projectionist.apply_template(ev.file)
			end, 1)
		end,
		desc = "Apply projectionist templates",
	})

	-- Clear cache when projection files change
	vim.api.nvim_create_autocmd({ "BufWritePost" }, {
		group = group,
		pattern = { ".projections.json", "heuristic.json" },
		callback = function()
			projectionist.invalidate_cache()
		end,
		desc = "Invalidate projectionist cache",
	})
end

-- Setup with default options (commands and autocmds enabled)
projectionist.setup({
	commands = true,
	autocmds = true,
})

-- Register commands and autocmds (always do this in plugin/)
setup_commands()
setup_autocmds()
