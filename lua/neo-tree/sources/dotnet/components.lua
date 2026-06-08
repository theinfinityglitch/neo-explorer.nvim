local highlights = require('neo-tree.ui.highlights')
local common = require('neo-tree.sources.common.components')

local M = {}

local icons = {
  solution = '󰘐',
  folder_closed = '',
  folder_open = '',
  project = '',
}

M.icon = function(config, node, state)
  local icon = ' '
  local hl = highlights.FILE_ICON

  if node.type == 'dotnet_solution' then
    icon = icons.solution
  elseif node.type == 'dotnet_folder' then
    hl = highlights.DIRECTORY_ICON
    icon = node:is_expanded() and icons.folder_open or icons.folder_closed
  elseif node.type == 'dotnet_project' then
    icon = icons.project
  end

  return {
    text = icon .. ' ',
    highlight = hl,
  }
end

M.name = function(config, node, state)
  local hl = highlights.FILE_NAME

  if node.type == 'dotnet_solution' then
    hl = highlights.ROOT_NAME
  elseif node.type == 'dotnet_folder' then
    hl = highlights.DIRECTORY_NAME
  end

  return {
    text = node.name,
    highlight = hl,
  }
end

return vim.tbl_deep_extend('force', common, M)
