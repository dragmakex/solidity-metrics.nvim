local uv = vim.uv or vim.loop

local M = {}
local matcher_cache = {}
local plugin_root

function M.is_windows()
  return vim.fn.has 'win32' == 1 or vim.fn.has 'win64' == 1
end

function M.notify(msg, level, opts)
  opts = opts or {}
  vim.schedule(function()
    vim.notify(msg, level or vim.log.levels.INFO, vim.tbl_extend('force', { title = 'solidity-metrics.nvim' }, opts))
  end)
end

function M.normalize(path)
  return vim.fs.normalize(path):gsub('\\', '/')
end

function M.exists(path)
  return uv.fs_stat(path) ~= nil
end

function M.is_file(path)
  local stat = uv.fs_stat(path)
  return stat and stat.type == 'file' or false
end

function M.is_dir(path)
  local stat = uv.fs_stat(path)
  return stat and stat.type == 'directory' or false
end

function M.join(...)
  return M.normalize(table.concat({ ... }, '/'))
end

function M.buf_dir(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr or 0)
  if name == '' then
    return uv.cwd()
  end
  return vim.fs.dirname(name)
end

function M.find_root(start, markers)
  local path = start or M.buf_dir(0)
  path = M.normalize(path)
  if not M.is_dir(path) then
    path = vim.fs.dirname(path)
  end

  local found = vim.fs.find(markers, { upward = true, path = path })[1]
  if found then
    return vim.fs.dirname(found)
  end

  return path
end

function M.make_glob_matcher(glob)
  if not matcher_cache[glob] then
    matcher_cache[glob] = vim.regex(vim.fn.glob2regpat(glob))
  end
  return matcher_cache[glob]
end

function M.matches_any(path, globs)
  if not globs or vim.tbl_isempty(globs) then
    return false
  end

  local normalized = M.normalize(path)
  for _, glob in ipairs(globs) do
    if M.make_glob_matcher(glob):match_str(normalized) then
      return true
    end
  end
  return false
end

function M.relpath(path, root)
  local normalized_path = M.normalize(path)
  local normalized_root = M.normalize(root)
  local prefix = normalized_root
  if not prefix:match '/$' then
    prefix = prefix .. '/'
  end
  if normalized_path:sub(1, #prefix) == prefix then
    return normalized_path:sub(#prefix + 1)
  end
  return normalized_path
end

function M.is_abs(path)
  if vim.fs.isabs then
    return vim.fs.isabs(path)
  end
  return path:match '^/' ~= nil or path:match '^%a:[/\\]' ~= nil
end

function M.system_open(target)
  if vim.ui and vim.ui.open then
    return vim.ui.open(target)
  end

  if M.is_windows() then
    return vim.system({ 'cmd', '/c', 'start', '', target }, { detach = true })
  end

  local opener = vim.fn.executable 'open' == 1 and 'open' or 'xdg-open'
  return vim.system({ opener, target }, { detach = true })
end

function M.executable_name(name)
  if M.is_windows() and not name:match '%.cmd$' and not name:match '%.exe$' then
    return name .. '.cmd'
  end
  return name
end

function M.to_list(value)
  if type(value) == 'table' then
    return vim.deepcopy(value)
  end
  return { value }
end

function M.package_root_from_cli(script)
  if not script or script == '' then
    return nil
  end

  local normalized = M.normalize(script)
  if normalized:sub(-11) == '/src/cli.js' then
    return vim.fs.dirname(vim.fs.dirname(normalized))
  end

  local parent = vim.fs.dirname(normalized)
  if parent and M.is_file(M.join(parent, 'package.json')) then
    return parent
  end

  local grandparent = parent and vim.fs.dirname(parent) or nil
  if grandparent and M.is_file(M.join(grandparent, 'package.json')) then
    return grandparent
  end
end

function M.resolve_executable(path)
  if not path or path == '' then
    return nil
  end
  return uv.fs_realpath(path) or path
end

function M.plugin_root()
  if plugin_root then
    return plugin_root
  end

  local source = debug.getinfo(1, 'S').source:sub(2)
  plugin_root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))
  return plugin_root
end

return M
