local xml2lua = require('xml2lua')

local ok, tree_handler = pcall(require, 'xmlhandler.tree')

if not ok then
  tree_handler = require('xml2lua.xmlhandler.tree')
end

local M = {}

local function new_tree_handler()
  if type(tree_handler.new) == 'function' then
    return tree_handler:new()
  end

  tree_handler.root = {}
  tree_handler.options = tree_handler.options or { noreduce = {} }
  tree_handler._stack = { tree_handler.root }

  return tree_handler
end

function M.parse(root_dir, target_file)
  local file = io.open(target_file, 'r')
  if not file then
    return nil
  end
  local content = file:read('*a')
  file:close()

  local handler = new_tree_handler()
  local parser = xml2lua.parser(handler)
  parser:parse(content)

  ---@type DotnetSolution
  local solution = {
    name = vim.fn.fnamemodify(target_file, ':t:r'),
    path = target_file,
    projects = {},
    folders = {},
  }

  local solution_data = handler.root.Solution

  local function create_project(project_path)
    project_path = project_path:gsub('\\', '/')

    return {
      name = vim.fn.fnamemodify(project_path, ':t:r'),
      path = vim.fn.resolve(root_dir .. '/' .. project_path),
      dir = vim.fn.resolve(root_dir .. '/' .. vim.fn.fnamemodify(project_path, ':h')),
    }
  end

  ---@type DotnetFolder[]
  local parsed_folders = {}

  if solution_data and solution_data.Folder then
    local folders = solution_data.Folder[1] and solution_data.Folder or { solution_data.Folder }

    for _, folder in ipairs(folders) do
      local folder_path = folder._attr.Name:gsub('\\', '/')
      folder_path = folder_path:gsub('^/', '')
      folder_path = folder_path:gsub('/$', '')

      ---@type DotnetFolder
      local folder_table = {
        name = vim.fn.fnamemodify(folder_path, ':t:r'),
        path = folder_path,
        parent_path = folder_path:match('(.+)/[^/]+$'),
        children = {},
        projects = {},
      }

      if folder.Project ~= nil then
        -- Handle cases where there is only one project (single table) or multiple (array)
        local projects = folder.Project[1] and folder.Project or { folder.Project }

        for _, project in ipairs(projects) do
          -- The project path is stored in the Path attribute
          local project_path = project._attr.Path:gsub('\\', '/')

          table.insert(folder_table.projects, create_project(project_path))
        end
      end

      table.insert(parsed_folders, folder_table)
    end
  end

  local folder_index = {}

  for _, folder in ipairs(parsed_folders) do
    folder_index[folder.path] = folder
  end

  local root_folders = {}

  for _, folder in ipairs(parsed_folders) do
    local parent_path = folder.parent_path

    if parent_path and folder_index[parent_path] then
      table.insert(folder_index[parent_path].children, folder)
    else
      table.insert(root_folders, folder)
    end
  end

  solution.folders = root_folders

  if solution_data and solution_data.Project then
    -- Handle cases where there is only one project (single table) or multiple (array)
    local projects = solution_data.Project[1] and solution_data.Project or { solution_data.Project }

    for _, project in ipairs(projects) do
      -- The project path is stored in the Path attribute
      local project_path = project._attr.Path:gsub('\\', '/')

      table.insert(solution.projects, create_project(project_path))
    end
  end

  return solution
end

return M
