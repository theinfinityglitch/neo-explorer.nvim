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

local function get_project_node(state)
  local tree = state.tree
  local node = tree:get_node()
  if not node then
    return nil
  end

  local last_id = node:get_id()
  while node do
    if node.type == 'directory' and node.path then
      local dotnet_type = node.extra and node.extra.dotnet_type or nil
      if dotnet_type == 'project' then
        return node
      end
    end

    local parent_id = node:get_parent_id()
    if not parent_id or parent_id == last_id then
      return nil
    end

    last_id = parent_id
    node = tree:get_node(parent_id)
  end
  return nil
end

local function parse_project_root_namespace(project_path)
  local file = io.open(project_path, 'r')
  if not file then
    return nil
  end
  local content = file:read('*a')
  file:close()

  local root_ns = content:match('<RootNamespace>([^<]+)</RootNamespace>')
  if root_ns then
    return root_ns
  end

  local project_name = vim.fn.fnamemodify(project_path, ':t:r')
  return project_name
end

local function calculate_namespace(project_dir, current_folder, base_namespace)
  if not base_namespace then
    return base_namespace
  end

  local rel_path = current_folder:sub(#project_dir + 2)
  if rel_path == '' or rel_path == '.' then
    return base_namespace
  end

  local ns_parts = { base_namespace }
  for part in rel_path:gmatch('[^/\\]+') do
    if part ~= '.' and part ~= '..' then
      table.insert(ns_parts, part)
    end
  end

  return table.concat(ns_parts, '.')
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
  local project_info = nil

  local project_node = get_project_node(state)
  if project_node and project_node.path then
    local project_files = vim.fn.glob(project_node.path .. '/*.csproj', false, true)
    if project_files and #project_files > 0 then
      local project_path = project_files[1]
      local base_ns = parse_project_root_namespace(project_path)
      local computed_ns = calculate_namespace(project_node.path, directory, base_ns)
      project_info = {
        project_path = project_path,
        base_namespace = base_ns,
        computed_namespace = computed_ns,
      }
    end
  end

  local choices = { 'Empty file' }

  if project_info then
    table.insert(choices, '--- Custom C# Templates ---')
    table.insert(templates, { type = 'header' })
    
    local template_dir = debug.getinfo(1, 'S').source:match('@(.+)/commands.lua$') .. '/templates'
    local template_files = vim.fn.glob(template_dir .. '/*.cs', false, true)
    for _, template_file in ipairs(template_files) do
      local short_name = vim.fn.fnamemodify(template_file, ':t:r')
      table.insert(choices, short_name:sub(1, 1):upper() .. short_name:sub(2))
      table.insert(templates, {
        type = 'custom',
        name = short_name,
        template_file = template_file,
        namespace = project_info.computed_namespace,
      })
    end
    
    table.insert(choices, '--- Dotnet Templates ---')
    table.insert(templates, { type = 'header' })
  end

  if vim.fn.executable('dotnet') == 1 then
    local lines = vim.fn.systemlist({ 'dotnet', 'new', 'list', '--type', 'item', '--language', 'C#', '--columns-all' })
    if vim.v.shell_error == 0 and lines and #lines > 0 then
      local dotnet_templates = parse_dotnet_templates(lines)
      for _, template in ipairs(dotnet_templates) do
        table.insert(choices, template.name)
        table.insert(templates, {
          type = 'dotnet',
          name = template.name,
          short = template.short,
        })
      end
    end
  end

  vim.ui.select(choices, { prompt = 'Create file from template:' }, function(choice, idx)
    if not choice or not idx then
      return
    end

    if choice:match('^%s*-+') then
      return
    end

    if idx == 1 then
      create_file_from_template(state, directory, 'empty', callback)
      return
    end

    if idx <= #templates then
      local template = templates[idx]
      if template.type == 'header' then
        return
      end

      if template.type == 'custom' then
        vim.ui.input({ prompt = 'Class name: ' }, function(class_name)
          if not class_name or class_name == '' then
            return
          end
          local file_path = directory .. '/' .. class_name .. '.cs'
          local template_file = io.open(template.template_file, 'r')
          if not template_file then
            vim.notify('Template file not found: ' .. template.template_file, vim.log.levels.ERROR)
            return
          end
          local content = template_file:read('*a')
          template_file:close()

          content = content:gsub('{{NAMESPACE}}', template.namespace)
          content = content:gsub('{{CLASS_NAME}}', class_name)

          local out_file = io.open(file_path, 'w')
          if not out_file then
            vim.notify('Failed to create file: ' .. file_path, vim.log.levels.ERROR)
            return
          end
          out_file:write(content)
          out_file:close()

          vim.notify('Created ' .. class_name .. '.cs in ' .. directory, vim.log.levels.INFO)
          manager.refresh('dotnet', state)
        end)
        return
      end

      if template.type == 'dotnet' then
        local template_obj = template
        vim.ui.input({ prompt = 'Name (leave empty to use default): ' }, function(name)
          template_obj.name_input = name
          create_file_from_template(state, directory, template_obj, callback)
        end)
        return
      end
    end
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
