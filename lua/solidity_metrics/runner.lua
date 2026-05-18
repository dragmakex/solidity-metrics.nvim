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

  return { 'solidity-code-metrics' }, 'missing'
end

local function resolve_package_root(root)
  local cmd, source = resolve_cmd(root)

  if source == 'custom' then
    local script = cmd[2]
    local package_root = util.package_root_from_cli(script)
    if package_root then
      return package_root, source
    end
  end

  local local_package = util.join(root, 'node_modules', 'solidity-code-metrics')
  if util.is_file(util.join(local_package, 'package.json')) then
    return local_package, 'local-package'
  end

  if source == 'local' or source == 'global' then
    local executable = util.resolve_executable(vim.fn.exepath 'solidity-code-metrics')
    local package_root = util.package_root_from_cli(executable)
    if package_root then
      return package_root, 'resolved-' .. source
    end
  end

  if source == 'global' and vim.fn.executable 'npm' == 1 then
    local result = vim.system({ 'npm', 'root', '-g' }, { text = true }):wait()
    if result.code == 0 then
      local package_root = util.join(vim.trim(result.stdout), 'solidity-code-metrics')
      if util.is_file(util.join(package_root, 'package.json')) then
        return package_root, 'npm-global'
      end
    end
  end

  return nil, source
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
      scope_file = scope_file,
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
      file = file,
    }
  end

  local selected, info = files.collect_solidity_files(root, {
    exclude = opts.exclude,
    limit = config.options.file_limit,
  })
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
    truncated = info and info.truncated or false,
    discovered_count = info and info.total or #selected,
    limit = info and info.limit or config.options.file_limit,
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

local function run_structured_internal(request, opts, callback)
  opts = opts or {}
  local package_root, source = resolve_package_root(request.root)
  if not package_root then
    callback(false, ('solidity-code-metrics package could not be resolved for native rendering (%s)'):format(source))
    return
  end

  local request_path = vim.fn.tempname() .. '.json'
  vim.fn.writefile({ vim.json.encode {
    kind = request.kind,
    root = request.root,
    display_name = request.display_name,
    file = request.file,
    scope_file = request.scope_file,
    selected_files = request.selected_files,
    exclude = config.options.exclude,
    limit = config.options.file_limit,
    output_html = opts.html and true or false,
  } }, request_path)

  local script = util.join(util.plugin_root(), 'scripts', 'report_data.js')
  local result = vim.system({ 'node', script, request_path, package_root }, {
    cwd = request.root,
    text = true,
    timeout = config.options.timeout,
  }, function(output)
    cleanup(request_path)

    if output.code ~= 0 then
      local message = output.stderr ~= '' and output.stderr or output.stdout ~= '' and output.stdout or 'solidity-code-metrics native report failed'
      callback(false, vim.trim(message))
      return
    end

    if opts.html then
      cleanup(request.temp_scope_file)
      callback(true, output.stdout)
      return
    end

    local ok, decoded = pcall(vim.json.decode, output.stdout)
    if not ok then
      callback(false, 'Failed to decode native report payload')
      return
    end

    cleanup(request.temp_scope_file)
    callback(true, decoded)
  end)

  if not result then
    cleanup(request_path)
    callback(false, 'Failed to start native report process')
  end
end

function M.run_structured(request, callback)
  run_structured_internal(request, { html = false }, callback)
end

function M.run_structured_html(request, callback)
  run_structured_internal(request, { html = true }, callback)
end

function M.detect_command(root)
  local resolved_root = root or util.find_root(util.buf_dir(0), config.options.workspace_root_markers)
  local cmd, source = resolve_cmd(resolved_root)
  local executable = cmd[1]

  if source == 'local' then
    return true, table.concat(cmd, ' '), source
  end
  if executable == 'node' or executable == 'bun' then
    local runtime_ok = vim.fn.executable(executable) == 1
    local script = cmd[2]
    return runtime_ok and script and util.exists(script), table.concat(cmd, ' '), source
  end
  return vim.fn.executable(executable) == 1 or util.exists(executable), table.concat(cmd, ' '), source
end

return M
