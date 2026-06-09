local xml2lua = require('xml2lua')

local ok, tree_handler = pcall(require, 'xmlhandler.tree')

if not ok then
  tree_handler = require('xml2lua.xmlhandler.tree')
end

local M = {}

local function new_tree_handler()
  local handler

  if type(tree_handler.new) == 'function' then
    handler = tree_handler:new()
  else
    tree_handler.root = {}
    tree_handler.options = tree_handler.options or { noreduce = {} }
    tree_handler._stack = { tree_handler.root }
    handler = tree_handler
  end

  handler.reduce = function() end

  return handler
end

local function as_list(value)
  if value == nil then
    return {}
  end

  if type(value) ~= 'table' then
    return { value }
  end

  if value[1] ~= nil then
    return value
  end

  return { value }
end

local function attr(node, key)
  return type(node) == 'table' and node._attr and node._attr[key] or nil
end

local function child_text(node, key)
  local value = type(node) == 'table' and node[key] or nil

  while type(value) == 'table' do
    value = value[1]
  end

  return value
end

local function normalize_path(base_dir, path)
  if not path then
    return nil
  end

  path = path:gsub('\\', '/')

  return vim.fn.resolve(base_dir .. '/' .. path)
end

local function split_frameworks(value)
  local frameworks = {}

  if not value then
    return frameworks
  end

  for framework in value:gmatch('[^;]+') do
    table.insert(frameworks, framework)
  end

  return frameworks
end

function M.parse(target_file)
  local file = io.open(target_file, 'r')
  if not file then
    return nil
  end

  local content = file:read('*a')
  file:close()

  local handler = new_tree_handler()
  local parser = xml2lua.parser(handler)
  parser:parse(content)

  local project_data = as_list(handler.root.Project)[1]
  if not project_data then
    return nil
  end

  local project_dir = vim.fn.fnamemodify(target_file, ':h')
  local properties = {
    sdk = attr(project_data, 'Sdk'),
    target_frameworks = {},
  }

  for _, property_group in ipairs(as_list(project_data.PropertyGroup)) do
    local target_framework = child_text(property_group, 'TargetFramework')
    local target_frameworks = child_text(property_group, 'TargetFrameworks')

    vim.list_extend(properties.target_frameworks, split_frameworks(target_framework))
    vim.list_extend(properties.target_frameworks, split_frameworks(target_frameworks))
  end

  local packages = {}
  local references = {}
  local imports = {}

  for _, item_group in ipairs(as_list(project_data.ItemGroup)) do
    for _, package in ipairs(as_list(item_group.PackageReference)) do
      local name = attr(package, 'Include') or attr(package, 'Update')

      if name then
        table.insert(packages, {
          name = name,
          version = attr(package, 'Version') or child_text(package, 'Version'),
          private_assets = attr(package, 'PrivateAssets') or child_text(package, 'PrivateAssets'),
          include_assets = attr(package, 'IncludeAssets') or child_text(package, 'IncludeAssets'),
          exclude_assets = attr(package, 'ExcludeAssets') or child_text(package, 'ExcludeAssets'),
        })
      end
    end

    for _, reference in ipairs(as_list(item_group.ProjectReference)) do
      local include = attr(reference, 'Include')

      if include then
        local path = normalize_path(project_dir, include)

        table.insert(references, {
          name = vim.fn.fnamemodify(include:gsub('\\', '/'), ':t:r'),
          include = include,
          path = path,
        })
      end
    end
  end

  for _, import in ipairs(as_list(project_data.Import)) do
    local import_project = attr(import, 'Project')

    if import_project then
      table.insert(imports, {
        project = import_project,
        condition = attr(import, 'Condition'),
      })
    end
  end

  return {
    properties = properties,
    packages = packages,
    references = references,
    imports = imports,
  }
end

---@param project DotnetProject
function M.enrich(project)
  local data = M.parse(project.path)

  if not data then
    project.properties = project.properties or { target_frameworks = {} }
    project.packages = project.packages or {}
    project.references = project.references or {}
    project.imports = project.imports or {}
    return
  end

  project.properties = data.properties
  project.packages = data.packages
  project.references = data.references
  project.imports = data.imports
end

return M
