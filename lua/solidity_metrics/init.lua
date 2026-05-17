local config = require 'solidity_metrics.config'
local runner = require 'solidity_metrics.runner'
local util = require 'solidity_metrics.util'
local view = require 'solidity_metrics.view'

local M = {}

local state = {
  last_request = nil,
  last_html_path = nil,
}

local function notify(msg, level)
  if config.options.notify then
    util.notify(msg, level)
  end
end

local function build_request(opts)
  local request, err = runner.build_request(opts)
  if request then
    return request
  end

  notify(err, vim.log.levels.ERROR)
end

local function run_markdown(request)
  notify(('Running Solidity Metrics for %s…'):format(request.display_name))
  runner.run(request, {}, function(ok, output)
    if not ok then
      notify(output, vim.log.levels.ERROR)
      return
    end

    vim.schedule(function()
      view.render(output, ('solidity-metrics://%s.md'):format(request.display_name))
    end)
  end)
end

function M.setup(opts)
  config.setup(opts)
end

function M.file(opts)
  local request = build_request(vim.tbl_extend('force', { kind = 'file' }, opts or {}))
  if not request then
    return
  end

  state.last_request = request
  run_markdown(request)
end

function M.workspace(opts)
  local request = build_request(vim.tbl_extend('force', { kind = 'workspace' }, opts or {}))
  if not request then
    return
  end

  state.last_request = request
  run_markdown(request)
end

function M.scope(opts)
  local request = build_request(vim.tbl_extend('force', { kind = 'scope' }, opts or {}))
  if not request then
    return
  end

  state.last_request = request
  run_markdown(request)
end

function M.export_html(opts)
  local request = state.last_request
  if opts and opts.kind then
    request = build_request(opts)
  elseif not request then
    request = build_request { kind = 'workspace' }
  end

  if not request then
    return
  end

  local output = opts and opts.output
  if not output or output == '' then
    output = util.join(request.root, config.options.html.filename)
  elseif not util.is_abs(output) then
    output = util.join(request.root, output)
  end
  output = vim.fs.normalize(output)

  notify(('Exporting Solidity Metrics HTML to %s'):format(output))
  runner.run(request, { html = true }, function(ok, html)
    if not ok then
      notify(html, vim.log.levels.ERROR)
      return
    end

    vim.schedule(function()
      vim.fn.mkdir(vim.fs.dirname(output), 'p')
      vim.fn.writefile(vim.split(html, '\n', { plain = true }), output)
      state.last_html_path = output
      notify(('Wrote %s'):format(output))
      if config.options.html.open then
        util.system_open(output)
      end
    end)
  end)
end

function M.last_request()
  return state.last_request
end

function M.last_html_path()
  return state.last_html_path
end

return M
