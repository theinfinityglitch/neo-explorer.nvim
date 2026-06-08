local cc = require('neo-tree.sources.common.commands')
local manager = require('neo-tree.sources.manager')

local M = {}

M.open = function(state, toggle_directory)
  local node = state.tree:get_node()

  if not node then
    return
  end

  if node.type == 'dotnet_solution' or node.type == 'dotnet_folder' then
    toggle_directory(node)
    return
  end

  if node.type == 'dotnet_project' then
    vim.cmd.edit(vim.fn.fnameescape(node.path))
  end
end

M.refresh = function(state)
  manager.refresh('dotnet', state)
end

cc._add_common_commands(M)

return M
