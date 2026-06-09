local cc = require('neo-tree.sources.common.commands')
local fs_actions = require('neo-tree.sources.filesystem.lib.fs_actions')
local manager = require('neo-tree.sources.manager')

local M = {}

local function get_folder_node(state)
  local tree = state.tree
  local node = tree:get_node()
  if not node then
    return nil
  end

  local last_id = node:get_id()
  while node do
    if node.type == 'directory' and node.path then
      return node
    end

    local parent_id = node:get_parent_id()
    if not parent_id or parent_id == last_id then
      return nil
    end

    last_id = parent_id
    node = tree:get_node(parent_id)
  end
end

M.add = function(state, callback)
  local node = get_folder_node(state)
  if not node then
    return
  end

  local directory = node.path
  fs_actions.create_node(directory, function(destination)
    if callback then
      callback(destination)
    end
    manager.refresh('dotnet', state)
  end, directory)
end

M.add_directory = function(state, callback)
  local node = get_folder_node(state)
  if not node then
    return
  end

  local directory = node.path
  fs_actions.create_directory(directory, function(destination)
    if callback then
      callback(destination)
    end
    manager.refresh('dotnet', state)
  end, directory)
end

M.open = function(state, toggle_directory)
  local node = state.tree:get_node()

  if not node then
    return
  end

  if node.type == 'directory' then
    cc.toggle_node(state, toggle_directory)
    return
  end

  if node.path then
    vim.cmd.edit(vim.fn.fnameescape(node.path))
  end
end

M.refresh = function(state)
  manager.refresh('dotnet', state)
end

cc._add_common_commands(M)

return M
