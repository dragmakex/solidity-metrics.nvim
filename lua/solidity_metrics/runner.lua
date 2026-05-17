local uv = vim.uv or vim.loop
local config = require 'solidity_metrics.config'
local files = require 'solidity_metrics.files'
local util = require 'solidity_metrics.util'

local M = {}

local function resolve_local_bin(root)
  if not config.options.prefer_local then
    return nil
  end

  local local_bin = util.join(root, 'node_modules', '.bin', util.executable_name(config.options.local_bin))
  if util.is_file(local_bin) then
    return { local_bin }
  end
end

local function resolve_cmd(root)
  local cmd = config.options.cmd
  if type(cmd) == 'function' then
    cmd = cmd(root)
  end
  if cmd and #cmd > 0 then
    return util.to_list(cmd), 'custom'
  end

  local local_cmd = resolve_local_bin(root)
  if local_cmd then
    return local_cmd, 'local'
  end

  if vim.fn.executable 'solidity-code-metrics' == 1 then
    return { 'solidity-code-metrics' }, 'global'
  end

  if config.options.use_npx then
    return { 'npx', '--yes', config.options.npx_package }, 'npx'
  end

  return { 'solidity-code-metrics' }, 'missing'
end

local function write_scope_file(root, paths)
  local scope = util.join(root, ('.solidity-metrics.nvim.%d.scope.txt'):format(uv.hrtime()))
  local relative_paths = {}
  for _, path in ipairs(paths) do
    relative_paths[#relative_paths + 1] = util.relpath(path, root)
  end
  vim.fn.writefile(relative_paths, scope)
  return scope
end

local function cleanup(path)
  if path and util.exists(path) then
    pcall(uv.fs_unlink, path)
  end
end

local function extend_args(base, extra)
  local args = vim.list_extend({}, base)
  for _, item in ipairs(extra or {}) do
    args[#args + 1] = item
  end
  return args
end

function M.build_request(opts)
  opts = opts or {}
  local root = opts.root and vim.fs.normalize(opts.root)
    or util.find_root(util.buf_dir(opts.bufnr or 0), config.options.workspace_root_markers)

  if opts.kind == 'scope' then
    local scope_file = opts.scope_file or util.join(root, config.options.scopefile)
    return {
      kind = 'scope',
      root = root,
      display_name = vim.fs.basename(scope_file),
      args = { '--scope-file', scope_file },
    }
  end

  if opts.kind == 'file' then
    local file = opts.file or vim.api.nvim_buf_get_name(opts.bufnr or 0)
    if file == '' then
      return nil, 'Current buffer has no file name'
    end
    if file:sub(-4) ~= '.sol' then
      return nil, ('Not a Solidity file: %s'):format(file)
    end
    return {
      kind = 'file',
      root = root,
      display_name = vim.fs.basename(file),
      args = { file },
    }
  end

  local selected = files.collect_solidity_files(root, { exclude = opts.exclude })
  if vim.tbl_isempty(selected) then
    return nil, ('No Solidity files found in %s'):format(root)
  end

  local scope_file = write_scope_file(root, selected)
  return {
    kind = 'workspace',
    root = root,
    display_name = vim.fs.basename(root),
    args = { '--scope-file', scope_file },
    temp_scope_file = scope_file,
    selected_files = selected,
  }
end

function M.run(request, opts, callback)
  opts = opts or {}
  local cmd = select(1, resolve_cmd(request.root))
  local args = extend_args(cmd, request.args)
  if opts.html then
    args[#args + 1] = '--html'
  end

  local ok, err = pcall(vim.system, args, {
    cwd = request.root,
    text = true,
    timeout = opts.timeout or config.options.timeout,
  }, function(result)
    cleanup(request.temp_scope_file)

    if result.code ~= 0 then
      local message = result.stderr ~= '' and result.stderr
        or result.stdout ~= '' and result.stdout
        or 'solidity-code-metrics failed'
      callback(false, vim.trim(message), result)
      return
    end

    callback(true, result.stdout, result)
  end)

  if not ok then
    cleanup(request.temp_scope_file)
    callback(false, tostring(err))
  end
end

function M.detect_command(root)
  local resolved_root = root or util.find_root(util.buf_dir(0), config.options.workspace_root_markers)
  local cmd, source = resolve_cmd(resolved_root)
  local executable = cmd[1]

  if source == 'local' then
    return true, table.concat(cmd, ' '), source
  end
  if executable == 'npx' then
    return vim.fn.executable 'npx' == 1, table.concat(cmd, ' '), source
  end
  if executable == 'node' or executable == 'bun' then
    local runtime_ok = vim.fn.executable(executable) == 1
    local script = cmd[2]
    return runtime_ok and script and util.exists(script), table.concat(cmd, ' '), source
  end
  return vim.fn.executable(executable) == 1 or util.exists(executable), table.concat(cmd, ' '), source
end

return M
