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

local function parse_dotnet_templates(lines)
  local templates = {}
  local started = false

  for _, line in ipairs(lines) do
    if not started then
      if line:match('^%s*Template Name%s+Short Name') then
        started = true
      end
    else
      if line:match('^%s*$') then
        goto continue
      end
      if line:match('^%s*-+') then
        goto continue
      end
      if line:match('^%s*item%s+') or line:match('^%s*project%s+') then
        goto continue
      end

      local name, short = line:match('^%s*(.-)%s%s+([%w%-%.,]+)%s+%S')
      if name and short then
        name = vim.trim(name)
        short = vim.trim(short)
        if name ~= '' and short ~= '' then
          table.insert(templates, { name = name, short = short })
        end
      end
    end
    ::continue::
  end

  return templates
end

local function create_file_from_template(state, directory, template, callback)
  if template == 'empty' then
    fs_actions.create_node(directory, function(_)
      if callback then
        callback()
      end
      manager.refresh('dotnet', state)
    end, directory)
    return
  end

  local cmd = { 'dotnet', 'new', template.short, '-o', directory, '--force' }
  if template.name_input and template.name_input ~= '' then
    table.insert(cmd, '-n')
    table.insert(cmd, template.name_input)
  end

  local output = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    vim.notify('dotnet new failed: ' .. table.concat(output, '\n'), vim.log.levels.ERROR)
    return
  end

  if callback then
    callback()
  end
  vim.notify('Created ' .. template.short .. ' in ' .. directory, vim.log.levels.INFO)
  manager.refresh('dotnet', state)
end

M.add = function(state, callback)
  local node = get_folder_node(state)
  if not node then
    return
  end

  local directory = node.path
  local templates = {}

  if vim.fn.executable('dotnet') == 1 then
    local lines = vim.fn.systemlist({ 'dotnet', 'new', 'list', '--type', 'item', '--columns-all' })
    if vim.v.shell_error == 0 and lines and #lines > 0 then
      templates = parse_dotnet_templates(lines)
    end
  end

  local choices = { 'Empty file' }
  for _, template in ipairs(templates) do
    table.insert(choices, template.name)
  end

  vim.ui.select(choices, { prompt = 'Create file from template:' }, function(choice, idx)
    if not choice or not idx then
      return
    end

    if idx == 1 then
      create_file_from_template(state, directory, 'empty', callback)
      return
    end

    local template = templates[idx - 1]
    vim.ui.input({ prompt = 'Name (leave empty to use default): ' }, function(name)
      template.name_input = name
      create_file_from_template(state, directory, template, callback)
    end)
  end)
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
  return M.add(state)
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
