local cc = require('neo-tree.sources.common.commands')
local manager = require('neo-tree.sources.manager')

local M = {}

M.open = function(state, toggle_directory)
  local node = state.tree:get_node()

  if not node then
    return
  end

  local dotnet_type = node.extra and node.extra.dotnet_type

  if
    dotnet_type == 'solution'
    or dotnet_type == 'folder'
    or dotnet_type == 'project'
    or dotnet_type == 'dependencies'
    or dotnet_type == 'dependency_group'
  then
    cc.toggle_node(state, toggle_directory)
    return
  end

  if dotnet_type == 'project_reference' and node.path then
    vim.cmd.edit(vim.fn.fnameescape(node.path))
  end
end

M.refresh = function(state)
  manager.refresh('dotnet', state)
end

cc._add_common_commands(M)

return M
