local highlights = require('neo-tree.ui.highlights')
local common = require('neo-tree.sources.common.components')

local M = {}

local icons = {
  solution = '󰘐',
  folder_closed = '',
  folder_open = '',
  project = '󰏗',
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
  end

  return {
    text = icon .. ' ',
    highlight = hl,
  }
end

M.name = function(config, node, state)
  local hl = highlights.FILE_NAME
  local dotnet_type = node.extra and node.extra.dotnet_type

  if dotnet_type == 'solution' then
    hl = highlights.ROOT_NAME
  elseif dotnet_type == 'folder' then
    hl = highlights.DIRECTORY_NAME
  end

  return {
    text = node.name,
    highlight = hl,
  }
end

return vim.tbl_deep_extend('force', common, M)
