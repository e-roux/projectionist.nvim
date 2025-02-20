local Path = require("plenary.path")

local M = {}

-- heuristic
-- @return table of the raw projectionist configuration.
local function query_raw(key, file)
  local candidates = {}
  file = file or vim.api.nvim_buf_get_name(0)
  local projections = s_all()
  for _, projection in ipairs(projections) do
    local path, projections = unpack(projection)
    local pre = path .. Path.path.sep
    local attrs = { project = path, file = file }
    local name = file:sub(#path + 2)
    if file:sub(1, #path) ~= path then
      name = ""
    end
    if projections[name] and projections[name][key] then
      table.insert(candidates, { projections[name][key], attrs })
    end
    local patterns = vim.tbl_keys(projections)
    table.sort(patterns, function(a, b)
      return #a > #b
    end)
    for _, pattern in ipairs(patterns) do
      if pattern:find("*") then
        local match = s_match(name, pattern)
        if (match and #match > 0) or pattern == "*" then
          if projections[pattern] and projections[pattern][key] then
            local expansions = vim.tbl_extend("force", { match = match }, attrs)
            table.insert(candidates, { projections[pattern][key], expansions })
          end
        end
      end
    end
  end
  return candidates
end

M.query_raw = function(...)
  return vim.fn["projectionist#query_raw"](...)
end

---query_file
---@param ... A variable number of arguments to pass to the 'projectionist#query_file' function.
---@return The return value of the 'projectionist#query_file' function.
---document t pope's projectionist query_file function
M.query_file = function(...)
  return vim.fn["projectionist#query_file"](...)
end

--- Gets the file type by querying the projectionist.
-- @return string The file type.
M.get_file_type = function()
  local file_type = M.query_raw("type")

  -- Get the first element while file_type is a list
  while type(file_type) == "table" and #file_type > 0 do
    file_type = file_type[1]
  end
  return file_type
end

M.get_alternate_file = function()
  if
    vim.g.loaded_projectionist and (M.get_file_type() == "test" or M.get_file_type() == "source")
  then
    local alternate_file = M.query_file("alternate")
    if #alternate_file then -- take the fist result
      -- print('test.lua: len(alternate_file): ' .. #alternate_file)
      local test_file = alternate_file[1]
      -- print('test.lua: alternate_file: ' .. alternate_file[1])
      return test_file
    end
    -- end
  end
end
--
--
-- function M.type_from_heuristic(file)
--   local file_type = M.heuristic('type')
--
--   if #file_type then -- take the fist result
--     file_type = file_type[1]
--   end
--
--   -- BUG: file_type can be empty
--   file_type = file_type[1]
-- end
--
-- function M.get_alternate_file(file_type)
--   if file_type == 'source' and vim.g.loaded_projectionist then
--     -- if vim.g.loaded_projectionist then
--     local alternate_file = vim.fn['projectionist#query_file']('alternate')
--     if #alternate_file then -- take the fist result
--       -- print('test.lua: len(alternate_file): ' .. #alternate_file)
--       file = alternate_file[1]
--       -- print('test.lua: alternate_file: ' .. alternate_file[1])
--     end
--     -- end
--   end
--
--   return file
-- end

M.setup = function() end

return M
