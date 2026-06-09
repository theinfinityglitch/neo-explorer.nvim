local renderer = require('neo-tree.ui.renderer')

local project_parser = require('parser.project')
local sln = require('parser.sln')
local slnx = require('parser.slnx')

local git = require('neo-tree.git')
local events = require('neo-tree.events')
local manager = require('neo-tree.sources.manager')
local items = require('neo-tree.sources.dotnet.lib.items')

local M = {
  name = 'dotnet',
  display_name = '󰘐 .NET',
}

local function get_state(tabid)
  return manager.get_state(M.name, tabid)
end

M.setup = function(config, global_config)
  if not global_config.enable_git_status then
    return
  end

  manager.subscribe(M.name, {
    event = events.BEFORE_RENDER,
    handler = function(state)
      local this_state = get_state()
      if state == this_state and this_state and this_state.path then
        git.status(this_state.path, this_state.git_base_by_worktree)
      end
    end,
  })

  manager.subscribe(M.name, {
    event = events.GIT_EVENT,
    handler = function()
      manager.refresh(M.name)
    end,
  })
end

local function find_solution(cwd)
  local slnx_files = vim.fn.glob(cwd .. '/*.slnx', false, true)

  if #slnx_files > 0 then
    return slnx_files[1], 'slnx'
  end

  local sln_files = vim.fn.glob(cwd .. '/*.sln', false, true)

  if #sln_files > 0 then
    return sln_files[1], 'sln'
  end
end

local function enrich_projects(projects)
  for _, project in ipairs(projects or {}) do
    project_parser.enrich(project)
  end
end

local function enrich_folder_projects(folders)
  for _, folder in ipairs(folders or {}) do
    enrich_projects(folder.projects)
    enrich_folder_projects(folder.children)
  end
end

local function enrich_solution(solution)
  enrich_projects(solution.projects)
  enrich_folder_projects(solution.folders)
end

M.navigate = function(state, path)
  path = path or vim.fn.getcwd()

  state.path = path

  local file, ext = find_solution(path)

  if not file then
    state.default_expanded_nodes = {}
    renderer.show_nodes({}, state)
    return
  end

  local solution

  if ext == 'slnx' then
    solution = slnx.parse(path, file)
  else
    solution = sln.parse(path, file)
  end

  if not solution then
    state.default_expanded_nodes = {}
    renderer.show_nodes({}, state)
    return
  end

  enrich_solution(solution)

  local nodes = items.build_nodes(solution)
  state.default_expanded_nodes = { nodes[1].id }

  renderer.show_nodes(nodes, state)

  local config = require('neo-tree').config
  if config.enable_git_status then
    if config.git_status_async and config.git_status_async_options then
      git.status_async(state.path, state.git_base_by_worktree, config.git_status_async_options)
    else
      git.status(state.path, state.git_base_by_worktree, false)
    end
  end
end

M.get_cwd = function(state)
  return state.path or vim.fn.getcwd()
end

M.default_config = {
  bind_to_cwd = false,

  window = {
    mappings = {
      ['<cr>'] = 'open',
      ['o'] = 'open',
      ['R'] = 'refresh',
    },
  },

  renderers = {
    directory = {
      { 'indent' },
      { 'icon' },
      { 'name',       use_git_status_colors = true },
      { 'git_status', zindex = 10,                 align = 'right', hide_when_expanded = true },
    },

    file = {
      { 'indent' },
      { 'icon' },
      { 'name',       use_git_status_colors = true },
      { 'git_status', zindex = 10,                 align = 'right' },
    },
  },
}

return M
