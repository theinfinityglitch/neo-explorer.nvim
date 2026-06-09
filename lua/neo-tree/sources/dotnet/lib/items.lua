local M = {}

local function make_id(kind, path)
  return 'dotnet://' .. kind .. '/' .. path
end

local function make_child_id(kind, parent_path, name)
  return make_id(kind, parent_path .. '#' .. name)
end

local function leaf_node(kind, parent_path, name, path, id_suffix)
  return {
    id = make_child_id(kind, parent_path, id_suffix or name),
    name = name,
    type = 'file',
    path = path,
    extra = {
      dotnet_type = kind,
    },
  }
end

local function group_node(kind, parent_path, name, children)
  return {
    id = make_child_id(kind, parent_path, name),
    name = name,
    type = 'directory',
    path = parent_path,
    loaded = true,
    extra = {
      dotnet_type = kind,
    },
    children = children,
  }
end

local function framework_nodes(project)
  local children = {}

  for index, framework in ipairs((project.properties and project.properties.target_frameworks) or {}) do
    table.insert(
      children,
      leaf_node('framework', project.path, framework, project.path, index .. ':' .. framework)
    )
  end

  return children
end

local function package_nodes(project)
  local children = {}

  for index, package in ipairs(project.packages or {}) do
    local name = package.name

    if package.version then
      name = name .. ' (' .. package.version .. ')'
    end

    table.insert(children, leaf_node('package', project.path, name, project.path, index .. ':' .. name))
  end

  return children
end

local function project_reference_nodes(project)
  local children = {}

  for index, reference in ipairs(project.references or {}) do
    table.insert(
      children,
      leaf_node(
        'project_reference',
        project.path,
        reference.name,
        reference.path,
        index .. ':' .. reference.name
      )
    )
  end

  return children
end

local function import_nodes(project)
  local children = {}

  for index, import in ipairs(project.imports or {}) do
    table.insert(
      children,
      leaf_node('import', project.path, import.project, project.path, index .. ':' .. import.project)
    )
  end

  return children
end

local function dependencies_node(project)
  local children = {}
  local frameworks = framework_nodes(project)
  local packages = package_nodes(project)
  local project_references = project_reference_nodes(project)
  local imports = import_nodes(project)

  if #frameworks > 0 then
    table.insert(children, group_node('dependency_group', project.path, 'Frameworks', frameworks))
  end

  if #packages > 0 then
    table.insert(children, group_node('dependency_group', project.path, 'Packages', packages))
  end

  if #project_references > 0 then
    table.insert(children, group_node('dependency_group', project.path, 'Projects', project_references))
  end

  if #imports > 0 then
    table.insert(children, group_node('dependency_group', project.path, 'Imports', imports))
  end

  return group_node('dependencies', project.path, 'Dependencies', children)
end

local function project_node(project)
  return {
    id = make_id('project', project.path),
    name = project.name,
    type = 'directory',
    path = project.path,
    loaded = true,
    extra = {
      dotnet_type = 'project',
    },
    children = {
      dependencies_node(project),
    },
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
    type = 'directory',
    path = folder.path,
    loaded = true,
    extra = {
      dotnet_type = 'folder',
    },
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
      type = 'directory',
      path = solution.path,
      loaded = true,
      extra = {
        dotnet_type = 'solution',
      },
      children = children,
    },
  }
end

return M
