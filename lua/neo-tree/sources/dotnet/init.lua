local renderer = require('neo-tree.ui.renderer')
local manager = require('neo-tree.sources.manager')

local sln = require('parser.sln')
local slnx = require('parser.slnx')

local items = require('neo-tree.sources.dotnet.lib.items')

local M = {
  name = 'dotnet',
  display_name = '󰘐 .NET',
}

M.setup = function(config, global_config) end

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

M.navigate = function(state, path)
  path = path or vim.fn.getcwd()

  state.path = path

  local file, ext = find_solution(path)

  if not file then
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
    renderer.show_nodes({}, state)
    return
  end

  renderer.show_nodes(items.build_nodes(solution), state)
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
    dotnet_solution = {
      { 'indent' },
      { 'icon' },
      { 'name' },
    },

    dotnet_folder = {
      { 'indent' },
      { 'icon' },
      { 'name' },
    },

    dotnet_project = {
      { 'indent' },
      { 'icon' },
      { 'name' },
    },
  },
}

return M
