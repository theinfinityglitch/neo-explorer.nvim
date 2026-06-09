local highlights = require('neo-tree.ui.highlights')
local common = require('neo-tree.sources.common.components')

local M = {}

local icons = {
  solution = '󰘐',
  folder_closed = '',
  folder_open = '',
  project = '󰏗',
  dependencies = '󰆧',
  dependency_group = '',
  framework = '󰪮',
  package = '󰏗',
  project_reference = '󰘦',
  import = '󰈙',
}

M.icon = function(config, node, state)
  local icon = ' '
  local hl = highlights.FILE_ICON
  local dotnet_type = node.extra and node.extra.dotnet_type

  if dotnet_type == 'solution' then
    icon = icons.solution
  elseif dotnet_type == 'folder' then
    hl = highlights.DIRECTORY_ICON
    icon = node:is_expanded() and icons.folder_open or icons.folder_closed
  elseif dotnet_type == 'project' then
    icon = icons.project
  elseif dotnet_type == 'project_files' or dotnet_type == 'project_folder' then
    hl = highlights.DIRECTORY_ICON
    icon = node:is_expanded() and icons.folder_open or icons.folder_closed
  elseif dotnet_type == 'dependencies' then
    hl = highlights.SYMBOLIC_LINK_TARGET
    icon = icons.dependencies
  elseif dotnet_type == 'dependency_group' then
    hl = highlights.SYMBOLIC_LINK_TARGET
    icon = icons.dependency_group
  elseif dotnet_type == 'framework' then
    icon = icons.framework
  elseif dotnet_type == 'package' then
    icon = icons.package
  elseif dotnet_type == 'project_reference' then
    icon = icons.project_reference
  elseif dotnet_type == 'import' then
    icon = icons.import
  end

  if icon == ' ' then
    return common.icon(config, node, state)
  end

  return {
    text = icon .. ' ',
    highlight = hl,
  }
end

M.name = function(config, node, state)
  local dotnet_type = node.extra and node.extra.dotnet_type
  local is_actual_node = not dotnet_type
      or dotnet_type == 'solution'
      or dotnet_type == 'folder'
      or dotnet_type == 'project'
      or dotnet_type == 'project_folder'
      or dotnet_type == 'project_files'
      or dotnet_type == 'project_file'
      or dotnet_type == 'project_reference'

  if config.use_git_status_colors and is_actual_node then
    return common.name(config, node, state)
  end

  local hl = highlights.FILE_NAME
  if dotnet_type == 'solution' then
    hl = highlights.ROOT_NAME
  elseif dotnet_type == 'folder' or dotnet_type == 'project' or dotnet_type == 'project_folder' or dotnet_type == 'project_files' then
    hl = highlights.DIRECTORY_NAME
  elseif dotnet_type == 'dependencies' or dotnet_type == 'dependency_group' then
    hl = highlights.SYMBOLIC_LINK_TARGET
  end

  return {
    text = node.name,
    highlight = hl,
  }
end

M.git_status = function(config, node, state)
  local dotnet_type = node.extra and node.extra.dotnet_type
  if dotnet_type and dotnet_type ~= 'solution' and dotnet_type ~= 'folder' and dotnet_type ~= 'project' and dotnet_type ~= 'project_folder' and dotnet_type ~= 'project_files' and dotnet_type ~= 'project_file' and dotnet_type ~= 'project_reference' then
    return {}
  end

  if not node.path then
    return {}
  end

  return common.git_status(config, node, state)
end

return vim.tbl_deep_extend('force', common, M)
