local M = {}

function M.parse(root_dir, target_file)
  local file = io.open(target_file, 'r')
  if not file then
    return nil
  end

  local content = file:read('*a')
  file:close()

  ---@type DotnetSolution
  local solution = {
    name = vim.fn.fnamemodify(target_file, ':t:r'),
    path = target_file,
    projects = {},
    folders = {},
  }

  for project_type, project_name, project_path, project_guid in
    content:gmatch('Project%("({[A-Fa-f0-9%-]+})"%) = "([^"]+)", "([^"]+)", "({[A-Fa-f0-9%-]+})"')
  do
    project_path = project_path:gsub('\\', '/')

    table.insert(solution.projects, {
      type = project_type,
      name = project_name,
      path = vim.fn.resolve(root_dir .. '/' .. project_path),
      dir = vim.fn.resolve(root_dir .. '/' .. vim.fn.fnamemodify(project_path, ':h')),
      guid = project_guid,
    })
  end

  return solution
end

return M
