local M = {}
local uv = vim.loop

local IGNORED_DIRS = {
  ['.git'] = true,
  ['node_modules'] = true,
  ['bin'] = true,
  ['obj'] = true,
  ['.vs'] = true,
  ['packages'] = true,
  ['.idea'] = true,
  ['.vscode'] = true,
}

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

local function directory_node(kind, parent_path, name, path, children)
  return {
    id = make_child_id(kind, parent_path, name),
    name = name,
    type = 'directory',
    path = path,
    loaded = true,
    extra = {
      dotnet_type = kind,
    },
    children = children,
  }
end

local function group_node(kind, parent_path, name, children)
  return directory_node(kind, parent_path, name, parent_path, children)
end

local function is_ignored_dir(name)
  return IGNORED_DIRS[name] or name:sub(1, 1) == '.'
end

local function scan_project_directory(path, ignore_name)
  local handle = uv.fs_scandir(path)
  if not handle then
    return {}
  end

  local entries = {}
  while true do
    local name, file_type = uv.fs_scandir_next(handle)
    if not name then
      break
    end

    if name ~= '.' and name ~= '..' then
      local full_path = path .. '/' .. name
      if not file_type then
        local stat = uv.fs_stat(full_path)
        file_type = stat and stat.type
      end

      if file_type == 'directory' and not is_ignored_dir(name) then
        table.insert(entries, { name = name, type = 'directory' })
      elseif file_type == 'file' and name ~= ignore_name then
        table.insert(entries, { name = name, type = 'file' })
      end
    end
  end

  table.sort(entries, function(a, b)
    if a.type == b.type then
      return a.name < b.name
    end
    return a.type == 'directory'
  end)

  local nodes = {}
  for _, entry in ipairs(entries) do
    local full_path = path .. '/' .. entry.name
    if entry.type == 'directory' then
      table.insert(nodes,
        directory_node('project_folder', path, entry.name, full_path, scan_project_directory(full_path)))
    else
      table.insert(nodes, leaf_node('project_file', path, entry.name, full_path))
    end
  end

  return nodes
end

local function project_file_nodes(project)
  local project_dir = project.dir or vim.fn.fnamemodify(project.path, ':h')
  local ignore_name = vim.fn.fnamemodify(project.path, ':t')
  return scan_project_directory(project_dir, ignore_name)
end

local function framework_nodes(project)
  local children = {}
  local project_dir = project.dir or vim.fn.fnamemodify(project.path, ':h')

  for index, framework in ipairs((project.properties and project.properties.target_frameworks) or {}) do
    table.insert(children, leaf_node('framework', project_dir, framework, nil, index .. ':' .. framework))
  end

  return children
end

local function package_nodes(project)
  local children = {}
  local project_dir = project.dir or vim.fn.fnamemodify(project.path, ':h')

  for index, package in ipairs(project.packages or {}) do
    local name = package.name

    if package.version then
      name = name .. ' (' .. package.version .. ')'
    end

    table.insert(children, leaf_node('package', project_dir, name, nil, index .. ':' .. name))
  end

  return children
end

local function project_reference_nodes(project)
  local children = {}
  local project_dir = project.dir or vim.fn.fnamemodify(project.path, ':h')

  for index, reference in ipairs(project.references or {}) do
    table.insert(children,
      leaf_node('project_reference', project_dir, reference.name, reference.path, index .. ':' .. reference.name))
  end

  return children
end

local function import_nodes(project)
  local children = {}
  local project_dir = project.dir or vim.fn.fnamemodify(project.path, ':h')

  for index, import in ipairs(project.imports or {}) do
    table.insert(children, leaf_node('import', project_dir, import.project, nil, index .. ':' .. import.project))
  end

  return children
end

local function dependencies_node(project)
  local children = {}
  local project_dir = project.dir or vim.fn.fnamemodify(project.path, ':h')
  local frameworks = framework_nodes(project)
  local packages = package_nodes(project)
  local project_references = project_reference_nodes(project)
  local imports = import_nodes(project)

  if #frameworks > 0 then
    table.insert(children, group_node('dependency_group', project_dir, 'Frameworks', frameworks))
  end

  if #packages > 0 then
    table.insert(children, group_node('dependency_group', project_dir, 'Packages', packages))
  end

  if #project_references > 0 then
    table.insert(children, group_node('dependency_group', project_dir, 'Projects', project_references))
  end

  if #imports > 0 then
    table.insert(children, group_node('dependency_group', project_dir, 'Imports', imports))
  end

  if #children == 0 then
    return nil
  end

  return group_node('dependencies', project_dir, 'Dependencies', children)
end

local function project_node(project)
  local project_dir = project.dir or vim.fn.fnamemodify(project.path, ':h')
  local children = {}

  local dependencies = dependencies_node(project)
  if dependencies then
    table.insert(children, dependencies)
  end

  local files = project_file_nodes(project)
  for _, child in ipairs(files) do
    table.insert(children, child)
  end

  return {
    id = make_id('project', project_dir),
    name = project.name,
    type = 'directory',
    path = project_dir,
    loaded = true,
    extra = {
      dotnet_type = 'project',
    },
    children = children,
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
      path = vim.fn.fnamemodify(solution.path, ':h'),
      loaded = true,
      extra = {
        dotnet_type = 'solution',
      },
      children = children,
    },
  }
end

return M
