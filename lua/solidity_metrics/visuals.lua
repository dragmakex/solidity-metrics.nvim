local util = require 'solidity_metrics.util'

local M = {}

local marker_prefix = '[[SM_VISUAL:'
local marker_suffix = ']]'

local function xml_escape(text)
  text = tostring(text or '')
  text = text:gsub('&', '&amp;')
  text = text:gsub('<', '&lt;')
  text = text:gsub('>', '&gt;')
  text = text:gsub('"', '&quot;')
  return text
end

local function clamp(value, min_value, max_value)
  if value < min_value then
    return min_value
  end
  if value > max_value then
    return max_value
  end
  return value
end

local function scale_value(value, max_value, use_log)
  if max_value <= 0 or value <= 0 then
    return 0
  end
  if not use_log then
    return value / max_value
  end
  return math.log(value + 1) / math.log(max_value + 1)
end

local function color(index)
  local palette = {
    '#4e79a7',
    '#59a14f',
    '#f28e2b',
    '#e15759',
    '#76b7b2',
    '#edc949',
    '#af7aa1',
    '#ff9da7',
    '#9c755f',
    '#bab0ab',
  }
  return palette[((index - 1) % #palette) + 1]
end

local function write_file(path, content)
  vim.fn.writefile(vim.split(content, '\n', { plain = true }), path)
end

local function ensure_dir(path)
  vim.fn.mkdir(path, 'p')
end

local function png_path(dir, name)
  return util.join(dir, name .. '.png')
end

local function marker(name)
  return marker_prefix .. name .. marker_suffix
end

local function create_chart_assets(dir, charts)
  local assets = {}
  local definitions = {
    { key = 'chart-risk-summary', title = 'Risk Summary', source = charts.risk, kind = 'radar', width = 88, height = 28, pixel_width = 1200 },
    { key = 'chart-nsloc-total', title = 'Source Lines', source = charts.sloc, kind = 'sloc', width = 88, height = 24, pixel_width = 1200 },
    { key = 'chart-num-bar', title = 'Summary', source = charts.summary, kind = 'bar_log', width = 96, height = 36, pixel_width = 1400 },
    { key = 'chart-num-bar-ast', title = 'AST Total', source = charts.ast, kind = 'bar_log', width = 100, height = 44, pixel_width = 1500 },
    { key = 'chart-num-bar-ast-funccalls', title = 'Function Calls', source = charts.function_calls, kind = 'bar_log', width = 100, height = 36, pixel_width = 1500 },
    { key = 'chart-num-bar-ast-asmcalls', title = 'Assembly Calls', source = charts.assembly_calls, kind = 'bar_log', width = 100, height = 32, pixel_width = 1500 },
  }

  local script = util.join(util.plugin_root(), 'scripts', 'chart_png.js')
  for _, definition in ipairs(definitions) do
    if definition.source and definition.source.keys and #definition.source.keys > 0 then
      local json_path = util.join(dir, definition.key .. '.json')
      local path = png_path(dir, definition.key)
      write_file(json_path, vim.json.encode(definition.source))
      local result = vim.system({
        'node',
        script,
        definition.kind,
        definition.title,
        json_path,
        tostring(definition.pixel_width),
        path,
      }, { text = true }):wait()
      if result.code ~= 0 then
        return nil, vim.trim(result.stderr ~= '' and result.stderr or result.stdout)
      end
      assets[definition.key] = {
        path = path,
        width = definition.width,
        height = definition.height,
      }
    end
  end

  return assets
end

local function dot_to_png(dir, name, dot_source)
  local dot_path = util.join(dir, name .. '.dot')
  local png = png_path(dir, name)
  write_file(dot_path, dot_source)
  local result = vim.system({ 'dot', '-Tpng', dot_path, '-o', png }, { text = true }):wait()
  if result.code ~= 0 then
    return nil, vim.trim(result.stderr ~= '' and result.stderr or result.stdout)
  end
  return png
end

local function create_graph_assets(dir, dot_graphs)
  local assets = {}
  local definitions = {
    { key = '#surya-inheritance', marker = 'surya-inheritance', width = 100, height = 34 },
    { key = '#surya-callgraph', marker = 'surya-callgraph', width = 100, height = 44 },
  }

  for _, definition in ipairs(definitions) do
    local dot_source = dot_graphs[definition.key]
    if dot_source and dot_source ~= '' then
      local path, err = dot_to_png(dir, definition.marker, dot_source)
      if path then
        assets[definition.marker] = {
          path = path,
          width = definition.width,
          height = definition.height,
        }
      else
        return nil, err
      end
    end
  end

  return assets
end

function M.is_available()
  local ok, image = pcall(require, 'image')
  if not ok then
    return false, 'image.nvim is not installed'
  end
  if vim.fn.executable 'dot' ~= 1 then
    return false, 'graphviz `dot` is required for visual report rendering'
  end
  if vim.fn.executable 'node' ~= 1 then
    return false, 'node is required for PNG chart rendering'
  end
  return true, image
end

function M.marker(name)
  return marker(name)
end

function M.prepare(report)
  local ok, image_or_err = M.is_available()
  if not ok then
    return nil, image_or_err
  end

  local dir = vim.fn.tempname()
  ensure_dir(dir)

  local assets, chart_err = create_chart_assets(dir, report.charts or {})
  if not assets then
    return nil, chart_err
  end
  local graph_assets, err = create_graph_assets(dir, report.dot_graphs or {})
  if not graph_assets then
    return nil, err
  end
  for key, value in pairs(graph_assets) do
    assets[key] = value
  end

  return {
    dir = dir,
    assets = assets,
  }
end

function M.clear(bufnr)
  local ok, image = pcall(require, 'image')
  if not ok then
    return
  end

  local namespace = 'solidity_metrics:' .. tostring(bufnr)
  local ok_images, images = pcall(image.get_images, { buffer = bufnr, namespace = namespace })
  if not ok_images then
    return
  end
  for _, item in ipairs(images) do
    item:clear()
  end
end

function M.render(bufnr, winid, prepared)
  local ok, image = pcall(require, 'image')
  if not ok then
    return false, 'image.nvim is not installed'
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local namespace = 'solidity_metrics:' .. tostring(bufnr)
  local placements = {}
  M.clear(bufnr)

  for index, line in ipairs(lines) do
    local name = line:match('^%[%[SM_VISUAL:([^%]]+)%]%]$')
    if name then
      lines[index] = ''
      if prepared.assets[name] then
        placements[#placements + 1] = {
          name = name,
          row = index - 1,
          asset = prepared.assets[name],
        }
      end
    end
  end

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false

  for _, placement in ipairs(placements) do
    local asset = placement.asset
    local width = clamp(asset.width, 20, math.max(vim.api.nvim_win_get_width(winid) - 4, 20))
    local ok_image, img = pcall(image.from_file, asset.path, {
      id = namespace .. ':' .. placement.name,
      window = winid,
      buffer = bufnr,
      namespace = namespace,
      x = 0,
      y = placement.row,
      width = width,
      height = asset.height,
      inline = true,
      with_virtual_padding = true,
    })
    if not ok_image then
      return false, img
    end
    if img then
      local ok_render, render_err = pcall(function()
        img:render()
      end)
      if not ok_render then
        return false, render_err
      end
    end
  end

  return true
end

return M
