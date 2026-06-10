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

M.setup = function(_config, global_config)
  local register_selector_command = function(name)
    if vim.fn.exists(':' .. name) == 2 then
      vim.api.nvim_del_user_command(name)
    end
    vim.api.nvim_create_user_command(name, function()
      local state = get_state()
      if not state then
        vim.notify('NeoTree dotnet state is not available', vim.log.levels.WARN)
        return
      end
      require('neo-tree.sources.dotnet.commands').select_solution(state)
    end, {
      desc = 'Select .NET solution for NeoTree dotnet source',
      nargs = 0,
    })
  end

  register_selector_command('NeotreeDotnetSelectSolution')
  register_selector_command('DotnetSelectSolution')

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

local function find_solutions(cwd)
  local solutions = {}

  for _, path in ipairs(vim.fn.glob(cwd .. '/*.slnx', false, true)) do
    table.insert(solutions, { path = path, ext = 'slnx' })
  end
  for _, path in ipairs(vim.fn.glob(cwd .. '/*.sln', false, true)) do
    table.insert(solutions, { path = path, ext = 'sln' })
  end

  return solutions
end

local function normalize_solution_path(path)
  return path and vim.fs.normalize(path) or nil
end

local load_roslyn_plugin
local setup_roslyn_choose_target

local function roslyn_choose_target(targets)
  local selected = normalize_solution_path(vim.g.roslyn_nvim_selected_solution)
  local normalized_targets = {}

  for _, target in ipairs(targets) do
    normalized_targets[#normalized_targets + 1] = normalize_solution_path(target)
  end

  if selected and vim.tbl_contains(normalized_targets, selected) then
    return selected
  end

  local ok, roslyn_config_mod = pcall(require, 'roslyn.config')
  if ok and roslyn_config_mod then
    local config = roslyn_config_mod.get()
    if config.choose_target and config.choose_target ~= roslyn_choose_target then
      local choice = config.choose_target(targets)
      return normalize_solution_path(choice)
    end
  end

  return nil
end

load_roslyn_plugin = function()
  -- Consider plugin available if its config module can be required
  if pcall(require, 'roslyn.config') then
    return true
  end

  local ok = false
  if pcall(require, 'lazy') then
    local lazy = require('lazy')
    local plugin_key
    for _, p in ipairs(lazy.plugins()) do
      local name = p.name or (p._ and p._.spec and p._.spec[1])
      if name and (name:match('roslyn') or (p.url and p.url:match('roslyn'))) then
        plugin_key = p.name or name
        break
      end
    end
    if plugin_key then
      ok = pcall(lazy.load, { plugins = { plugin_key }, wait = true })
    else
      ok = pcall(lazy.load, { plugins = { 'roslyn.nvim' }, wait = true })
        or pcall(lazy.load, { plugins = { 'seblyng/roslyn.nvim' }, wait = true })
    end
  end

  if not ok then
    ok = pcall(vim.cmd, 'packadd roslyn.nvim')
  end

  if ok then
    return pcall(require, 'roslyn.config')
  end
  return false
end

setup_roslyn_choose_target = function()
  if not load_roslyn_plugin() then
    return false
  end

  local config = require('roslyn.config').get()
  local desired = vim.tbl_extend('force', config, {
    choose_target = roslyn_choose_target,
    lock_target = true,
  })
  require('roslyn.config').setup(desired)
  -- Ensure Roslyn user commands are created even if no C# buffer opened yet
  pcall(function()
    local cmds = require('roslyn.commands')
    if cmds and cmds.create_roslyn_commands then
      cmds.create_roslyn_commands()
    end
  end)
  return true
end

-- Removed unused helper: sync_roslyn_buffers

local function set_roslyn_target(solution_path)
  if not solution_path then
    return
  end

  local normalized_solution = normalize_solution_path(solution_path)
  vim.g.roslyn_nvim_selected_solution = normalized_solution
  setup_roslyn_choose_target()

  -- Stop existing roslyn clients so we can start new ones with the new target
  local existing = vim.lsp.get_clients({ name = 'roslyn' })
  for _, ex_client in ipairs(existing) do
    local force_stop = vim.uv.os_uname().sysname == 'Windows_NT'
    pcall(function()
      ex_client:stop(force_stop)
    end)
  end

  -- Wait briefly for clients to stop
  vim.wait(1500, function()
    return #vim.lsp.get_clients({ name = 'roslyn' }) == 0
  end, 50)

  -- Start roslyn for loaded C#/Razor buffers using the new solution
  local filetypes = { cs = true, razor = true, cshtml = true }
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local ft = vim.api.nvim_buf_get_option(bufnr, 'filetype')
      if filetypes[ft] then
        local client = vim.lsp.get_clients({ name = 'roslyn', bufnr = bufnr })[1]
        if not client then
          local config = vim.tbl_deep_extend('force', vim.lsp.config['roslyn'] or {}, {
            root_dir = vim.fs.dirname(normalized_solution),
            on_init = function(init_client)
              require('roslyn.lsp.on_init').sln(init_client, normalized_solution)
            end,
          })
          vim.lsp.start(config, { bufnr = bufnr })
        end
      end
    end
  end
end

local function preferred_solution(solutions, config)
  if config.prefer_slnx then
    for _, solution in ipairs(solutions) do
      if solution.ext == 'slnx' then
        return solution
      end
    end
    return solutions[1]
  end

  for _, solution in ipairs(solutions) do
    if solution.ext == 'sln' then
      return solution
    end
  end

  return solutions[1]
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

local function load_solution(state, cwd, solution)
  local data
  if solution.ext == 'slnx' then
    data = slnx.parse(cwd, solution.path)
  else
    data = sln.parse(cwd, solution.path)
  end

  if not data then
    state.default_expanded_nodes = {}
    renderer.show_nodes({}, state)
    return
  end

  enrich_solution(data)
  local nodes = items.build_nodes(data)
  state.default_expanded_nodes = { nodes[1].id }
  renderer.show_nodes(nodes, state)
  state._dotnet_solutions = nil
  local previous_selected = state._dotnet_selected_solution
  state._dotnet_selected_solution = solution

  local config = require('neo-tree').config
  if config.dotnet and config.dotnet.roslyn and config.dotnet.roslyn.enable then
    local prev_path = previous_selected and normalize_solution_path(previous_selected.path) or nil
    local new_path = normalize_solution_path(solution.path)
    if prev_path ~= new_path then
      set_roslyn_target(solution.path)
    end
  end

  if config.enable_git_status then
    if config.git_status_async and config.git_status_async_options then
      git.status_async(state.path, state.git_base_by_worktree, config.git_status_async_options)
    else
      git.status(state.path, state.git_base_by_worktree, false)
    end
  end
end

M.load_solution = load_solution
M.find_solutions = find_solutions
M.select_solution = function(state)
  require('neo-tree.sources.dotnet.commands').select_solution(state)
end
M.set_roslyn_target = set_roslyn_target

M.navigate = function(state, path)
  path = path or vim.fn.getcwd()

  state.path = path

  local solutions = find_solutions(path)
  if #solutions == 0 then
    state.default_expanded_nodes = {}
    renderer.show_nodes({}, state)
    return
  end

  if state._dotnet_selected_solution then
    for _, selected in ipairs(solutions) do
      if selected.path == state._dotnet_selected_solution.path then
        load_solution(state, path, selected)
        return
      end
    end
    state._dotnet_selected_solution = nil
  end

  local config = require('neo-tree').config
  if config.dotnet and config.dotnet.roslyn and config.dotnet.roslyn.enable then
    setup_roslyn_choose_target()
  end

  if #solutions > 1 and not config.auto_load_solution then
    state._dotnet_solutions = solutions
    state.default_expanded_nodes = {}
    renderer.show_nodes({}, state)
    M.select_solution(state)
    return
  end

  local solution = #solutions == 1 and solutions[1] or preferred_solution(solutions, config)
  load_solution(state, path, solution)
end

M.get_cwd = function(state)
  return state.path or vim.fn.getcwd()
end

M.default_config = {
  bind_to_cwd = false,
  auto_load_solution = true,
  prefer_slnx = true,
  roslyn = {
    enable = true,
  },

  window = {
    mappings = {
      ['<cr>'] = 'open',
      ['o'] = 'open',
      ['R'] = 'refresh',
      ['a'] = 'add',
      ['t'] = 'add_from_template',
    },
  },

  renderers = {
    directory = {
      { 'indent' },
      { 'icon' },
      { 'name', use_git_status_colors = true },
      { 'git_status', zindex = 10, align = 'right', hide_when_expanded = true },
    },

    file = {
      { 'indent' },
      { 'icon' },
      { 'name', use_git_status_colors = true },
      { 'git_status', zindex = 10, align = 'right' },
    },
  },
}

return M
