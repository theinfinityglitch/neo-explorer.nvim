local cc = require('neo-tree.sources.common.commands')
local fs_actions = require('neo-tree.sources.filesystem.lib.fs_actions')
local manager = require('neo-tree.sources.manager')
local dotnet_source = require('neo-tree.sources.dotnet.init')

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
      local dotnet_type = node.extra and node.extra.dotnet_type or nil
      if dotnet_type == 'project' or dotnet_type == 'project_folder' then
        return node
      end
      return nil
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

M.add_from_template = function(state)
  local node = get_folder_node(state)
  if not node then
    return
  end

  local directory = node.path
  if vim.fn.executable('dotnet') ~= 1 then
    vim.notify('dotnet CLI not found in PATH', vim.log.levels.ERROR)
    return
  end

  local lines = vim.fn.systemlist('dotnet new --list')
  if not lines or #lines == 0 then
    vim.notify('Failed to list dotnet templates', vim.log.levels.ERROR)
    return
  end

  local templates = {}
  local started = false
  for _, line in ipairs(lines) do
    if line:match('^%s*-+$') then
      started = true
      goto continue
    end
    if not started then
      goto continue
    end
    local short = line:match('%s([%w%-]+)%s+%w+%s*$') or line:match('%s([%w%-]+)%s*$')
    local name = line:match('^%s*(.-)%s[%s%w%-]+[%s%w%-]+$') or line
    if short then
      templates[#templates + 1] = { short = short, name = vim.trim(name) }
    end
    ::continue::
  end

  if #templates == 0 then
    vim.notify('No dotnet templates found', vim.log.levels.WARN)
    return
  end

  local choices = {}
  for _, t in ipairs(templates) do
    table.insert(choices, t.short .. ' — ' .. t.name)
  end

  vim.ui.select(choices, { prompt = 'dotnet template:' }, function(choice, idx)
    if not choice or not idx then
      return
    end
    local template = templates[idx]
    vim.ui.input({ prompt = 'Name (optional): ' }, function(name)
      local cmd = { 'dotnet', 'new', template.short, '-o', directory, '--force' }
      if name and name ~= '' then
        table.insert(cmd, '-n')
        table.insert(cmd, name)
      end
      local out = vim.fn.systemlist(table.concat(cmd, ' '))
      if vim.v.shell_error ~= 0 then
        vim.notify('dotnet new failed: ' .. table.concat(out, '\n'), vim.log.levels.ERROR)
        return
      end
      vim.notify('Created from template ' .. template.short, vim.log.levels.INFO)
      manager.refresh('dotnet', state)
    end)
  end)
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

M.select_solution = function(state)
  local cwd = state.path or vim.fn.getcwd()
  local solutions = dotnet_source.find_solutions(cwd)

  if #solutions == 0 then
    vim.notify('No .sln or .slnx solutions found in ' .. cwd, vim.log.levels.WARN)
    return
  end

  if #solutions == 1 then
    dotnet_source.load_solution(state, cwd, solutions[1])
    if dotnet_source.set_roslyn_target then
      dotnet_source.set_roslyn_target(solutions[1].path)
    end
    return
  end

  local options = {}
  for _, solution in ipairs(solutions) do
    table.insert(options, vim.fn.fnamemodify(solution.path, ':t') .. ' (' .. solution.ext .. ')')
  end

  vim.ui.select(options, { prompt = 'Select solution:' }, function(choice, idx)
    if not choice or not idx then
      return
    end
    dotnet_source.load_solution(state, cwd, solutions[idx])
    if dotnet_source.set_roslyn_target then
      dotnet_source.set_roslyn_target(solutions[idx].path)
    end
  end)
end

M.delete = function(state, callback)
  cc.delete(state, function(...)
    if callback then
      callback(...)
    end
    manager.refresh('dotnet', state)
  end)
end

M.delete_visual = function(state, selected_nodes, callback)
  cc.delete_visual(state, selected_nodes, function(...)
    if callback then
      callback(...)
    end
    manager.refresh('dotnet', state)
  end)
end

M.refresh = function(state)
  manager.refresh('dotnet', state)
end

cc._add_common_commands(M)

return M
