local M = {}

local SOLUTION_FOLDER_GUID = '{2150E333-8FDC-42A3-9474-1A3956D46DE8}'

M.assign_folder_paths = function(folder, parent_path)
  if parent_path then
    folder.parent_path = parent_path
    folder.path = parent_path .. '/' .. folder.name
  else
    folder.parent_path = nil
    folder.path = folder.name
  end

  for _, child in ipairs(folder.children) do
    M.assign_folder_paths(child, folder.path)
  end
end

M.parse = function(root_dir, target_file)
  local file = io.open(target_file, 'r')
  if not file then
    return nil
  end

  local content = file:read('*a')
  file:close()

  ---@type DotnetSolution
  local solution = {
    name = vim.fn.fnamemodify(target_file, ':t:r'),
    path = target_file,
    projects = {},
    folders = {},
  }

  local projects_by_guid = {}
  local folders_by_guid = {}

  for project_type, project_name, project_path, project_guid in
    content:gmatch('Project%("({[A-Fa-f0-9%-]+})"%) = "([^"]+)", "([^"]+)", "({[A-Fa-f0-9%-]+})"')
  do
    project_path = project_path:gsub('\\', '/')

    if project_type == SOLUTION_FOLDER_GUID then
      local folder_path = project_path
      folder_path = folder_path:gsub('^/', '')
      folder_path = folder_path:gsub('/$', '')

      ---@type DotnetFolder
      local folder = {
        name = vim.fn.fnamemodify(folder_path, ':t:r'),
        path = folder_path,
        guid = project_guid,
        children = {},
        projects = {},
      }

      folders_by_guid[project_guid] = folder
    else
      ---@type DotnetProject
      local project = {
        type = project_type,
        name = project_name,
        path = vim.fn.resolve(root_dir .. '/' .. project_path),
        dir = vim.fn.resolve(root_dir .. '/' .. vim.fn.fnamemodify(project_path, ':h')),
        guid = project_guid,
        references = {},
        packages = {},
      }

      projects_by_guid[project_guid] = project
    end
  end

  local nested_section = content:match('GlobalSection%(NestedProjects%).-\n%s*EndGlobalSection')
  local nested_folders = {}
  local nested_projects = {}

  if nested_section ~= nil then
    for child_guid, parent_guid in nested_section:gmatch('({[%w%-]+})%s*=%s*({[%w%-]+})') do
      local folder = folders_by_guid[parent_guid]

      if projects_by_guid[child_guid] ~= nil then
        table.insert(folder.projects, projects_by_guid[child_guid])
        nested_projects[child_guid] = true
      end

      if folders_by_guid[child_guid] ~= nil then
        local child = folders_by_guid[child_guid]
        child.parent_guid = parent_guid

        table.insert(folder.children, child)
        nested_folders[child_guid] = true
      end
    end
  end

  solution.projects = {}

  for guid, project in pairs(projects_by_guid) do
    if not nested_projects[guid] then
      table.insert(solution.projects, project)
    end
  end

  for guid, folder in pairs(folders_by_guid) do
    if not nested_folders[guid] then
      table.insert(solution.folders, folder)
    end
  end

  for _, folder in ipairs(solution.folders) do
    M.assign_folder_paths(folder, nil)
  end

  return solution
end

return M
