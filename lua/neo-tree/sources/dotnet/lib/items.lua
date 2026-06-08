local M = {}

local function make_id(kind, path)
  return 'dotnet://' .. kind .. '/' .. path
end

local function project_node(project)
  return {
    id = make_id('project', project.path),
    name = project.name,
    type = 'dotnet_project',
    path = project.path,
  }
end

local function folder_node(folder)
  local children = {}

  for _, child in ipairs(folder.children or {}) do
    table.insert(children, folder_node(child))
  end

  for _, project in ipairs(folder.projects or {}) do
    table.insert(children, project_node(project))
  end

  return {
    id = make_id('folder', folder.path),
    name = folder.name,
    type = 'dotnet_folder',
    path = folder.path,
    children = children,
  }
end

function M.build_nodes(solution)
  local children = {}

  for _, folder in ipairs(solution.folders or {}) do
    table.insert(children, folder_node(folder))
  end

  for _, project in ipairs(solution.projects or {}) do
    table.insert(children, project_node(project))
  end

  return {
    {
      id = make_id('solution', solution.path),
      name = solution.name,
      type = 'dotnet_solution',
      path = solution.path,
      children = children,
    },
  }
end

return M
