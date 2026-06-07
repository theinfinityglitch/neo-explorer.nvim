local sln = require('parser.sln')
local slnx = require('parser.slnx')

local M = {}

---@param solution DotnetSolution
local debug = function(solution)
  ---@param projects DotnetProject[]
  local list_projects = function(projects)
    for _, project in ipairs(projects) do
      print('--- Project ---')
      if project.type ~= nil then
        print('Project type: ' .. project.type)
      end
      if project.name ~= nil then
        print('Project name: ' .. project.name)
      end
      if project.path ~= nil then
        print('Project path: ' .. project.path)
      end
      if project.dir ~= nil then
        print('Project dir: ' .. project.dir)
      end
      if project.guid ~= nil then
        print('Project GUID: ' .. project.guid)
      end
      print('--- Project ' .. project.name .. ' End ---')
    end
  end

  ---@param folders DotnetFolder[]
  ---@param list_folders function
  local list_folders = function(folders, list_folders)
    for _, folder in ipairs(folders) do
      print('--- Folder ---')
      if folder.name ~= nil then
        print('Folder name: ' .. folder.name)
      end
      if folder.path ~= nil then
        print('Folder path: ' .. folder.path)
      end
      if folder.parent_path ~= nil then
        print('Folder parent path: ' .. folder.parent_path)
      end
      if folder.guid ~= nil then
        print('Folder GUID: ' .. folder.guid)
      end
      if folder.parent_guid ~= nil then
        print('Folder parent GUID: ' .. folder.parent_guid)
      end
      if folder.children ~= nil then
        list_folders(folder.children, list_folders)
      end
      if folder.projects ~= nil then
        list_projects(folder.projects)
      end
      print('--- Folder ' .. folder.name .. ' End ---')
    end
  end

  print('--- Solution ---')
  print('Solution name: ' .. solution.name)
  print('Solution path: ' .. solution.path)

  if solution.folders ~= nil then
    list_folders(solution.folders, list_folders)
  end

  if solution.projects ~= nil then
    list_projects(solution.projects)
  end

  print('--- Solution End ---')
end

M.setup = function(_)
  vim.api.nvim_create_user_command('ParseSolutionSln', function(opts)
    local arg = opts.fargs[1]
    local output = sln.parse(vim.fn.getcwd(), arg)

    if output ~= nil then
      debug(output)
    end
  end, {
    nargs = 1, -- Accepts any number of arguments
    desc = 'Parse sln solution test command',
  })

  vim.api.nvim_create_user_command('ParseSolutionSlnx', function(opts)
    local arg = opts.fargs[1]
    local output = slnx.parse(vim.fn.getcwd(), arg)

    if output ~= nil then
      debug(output)
    end
  end, {
    nargs = 1, -- Accepts any number of arguments
    desc = 'Parse sln solution test command',
  })
end

return M
