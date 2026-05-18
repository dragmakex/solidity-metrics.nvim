local config = require 'solidity_metrics.config'
local report = require 'solidity_metrics.report'
local runner = require 'solidity_metrics.runner'
local util = require 'solidity_metrics.util'
local view = require 'solidity_metrics.view'
local visuals = require 'solidity_metrics.visuals'

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

local function refresh_request(request)
  if not request then
    return nil
  end

  if request.kind == 'workspace' and (not request.temp_scope_file or not util.exists(request.temp_scope_file)) then
    return build_request { kind = 'workspace', root = request.root }
  end

  return request
end

local function maybe_notify_truncated(request)
  if request and request.truncated then
    notify(
      ('Solidity Metrics: capped analysis at %d of %d files (file_limit). Increase via setup({ file_limit = N }).'):format(
        request.limit or 0,
        request.discovered_count or 0
      ),
      vim.log.levels.WARN
    )
  end
end

local function run_markdown(request)
  notify(('Running Solidity Metrics for %s…'):format(request.display_name))
  maybe_notify_truncated(request)
  runner.run_structured(request, function(ok, output)
    if ok then
      vim.schedule(function()
        if config.options.visual.enabled then
          local prepared, prepare_err = visuals.prepare {
            markdown = output.markdown,
            totals = output.totals,
            dot_graphs = output.dot_graphs or {},
            charts = output.charts or {},
          }
          if prepared then
            local markdown = report.render_visual_text(output.markdown)
            local buf, render_err = view.render_visual(markdown, prepared, ('solidity-metrics://%s'):format(request.display_name))
            if buf then
              return
            end
            if config.options.visual.strict then
              notify(render_err or 'Failed to render visual report', vim.log.levels.ERROR)
              return
            end
            notify(render_err or 'Failed to render visual report, falling back', vim.log.levels.WARN)
          else
            if config.options.visual.strict then
              notify(prepare_err or 'Visual report requirements are missing', vim.log.levels.ERROR)
              return
            end
            notify(prepare_err or 'Visual report requirements are missing, falling back', vim.log.levels.WARN)
          end
        end

        local rendered = report.render_native {
          markdown = output.markdown,
          totals = output.totals,
          dot_graphs = output.dot_graphs or {},
          charts = output.charts or {},
        }
        view.render_ansi(rendered, ('solidity-metrics://%s'):format(request.display_name))
      end)
      return
    end

    notify(output, vim.log.levels.WARN)
    runner.run(request, {}, function(fallback_ok, fallback_output)
      if not fallback_ok then
        notify(fallback_output, vim.log.levels.ERROR)
        return
      end

      vim.schedule(function()
        local markdown = report.sanitize_for_nvim(fallback_output)
        view.render(markdown, ('solidity-metrics://%s.md'):format(request.display_name))
      end)
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
  local request = refresh_request(state.last_request)
  if opts and opts.kind then
    request = build_request(opts)
  elseif not request then
    request = build_request { kind = 'workspace' }
  end

  if not request then
    return
  end

  state.last_request = request

  local output = opts and opts.output
  if not output or output == '' then
    output = util.join(request.root, config.options.html.filename)
  elseif not util.is_abs(output) then
    output = util.join(request.root, output)
  end
  output = vim.fs.normalize(output)

  notify(('Exporting Solidity Metrics HTML to %s'):format(output))
  maybe_notify_truncated(request)

  local function write_html(html)
    vim.schedule(function()
      vim.fn.mkdir(vim.fs.dirname(output), 'p')
      vim.fn.writefile(vim.split(html, '\n', { plain = true }), output)
      state.last_html_path = output
      notify(('Wrote %s'):format(output))
      if config.options.html.open then
        util.system_open(output)
      end
    end)
  end

  runner.run_structured_html(request, function(ok, html)
    if ok then
      write_html(html)
      return
    end

    notify(html, vim.log.levels.WARN)
    runner.run(request, { html = true }, function(fallback_ok, fallback_html)
      if not fallback_ok then
        notify(fallback_html, vim.log.levels.ERROR)
        return
      end
      write_html(fallback_html)
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
