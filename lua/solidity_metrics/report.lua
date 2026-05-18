local ansi = require 'solidity_metrics.ansi'
local charts = require 'solidity_metrics.charts'
local graphs = require 'solidity_metrics.graphs'
local visuals = require 'solidity_metrics.visuals'

local M = {}

local chart_width = 28
local chart_label_width = 24

local function trim(text)
  return text:gsub('^%s+', ''):gsub('%s+$', '')
end

local function strip_banner(text)
  local heading = text:find('# Solidity Metrics', 1, true)
  if heading then
    return text:sub(heading)
  end
  return text
end

local function replace_html_breaks(text)
  text = text:gsub('<br%s*/?>%s*\n', '\n')
  return text:gsub('<br%s*/?>', ' / ')
end

local function replace_inline_html(text)
  text = text:gsub('<span[^>]->(.-)</span>', '%1')
  text = text:gsub('<abbr[^>]->(.-)</abbr>', '%1')
  text = text:gsub('<code>(.-)</code>', '`%1`')
  text = text:gsub('<b>(.-)</b>', '**%1**')
  text = text:gsub('<a%s+href="([^"]+)"[^>]*>(.-)</a>', '[%2](%1)')
  text = text:gsub("<a%s+href='([^']+)'[^>]*>(.-)</a>", '[%2](%1)')
  return text
end

local function replace_list_html(text)
  text = text:gsub('<ul[^>]*>', '')
  text = text:gsub('</ul>', '')
  text = text:gsub('<li>%s*', '- ')
  text = text:gsub('</li>%s*', '\n')
  return text
end

local function strip_container_html(text)
  text = text:gsub('</?sub>', '')
  text = text:gsub('</?sup>', '')
  text = text:gsub('</?div[^>]*>', '')
  return text
end

local function cleanup_lines(text)
  local lines = vim.split(text, '\n', { plain = true })
  local cleaned = {}

  for _, line in ipairs(lines) do
    line = line:gsub('%s+$', '')
    if line:find('toggleVisibility', 1, true) then
      line = ''
    end
    if line ~= '' or (#cleaned > 0 and cleaned[#cleaned] ~= '') then
      cleaned[#cleaned + 1] = line
    end
  end

  while cleaned[#cleaned] == '' do
    cleaned[#cleaned] = nil
  end

  return table.concat(cleaned, '\n')
end

local function chart_opts()
  return {
    width = chart_width,
    label_width = chart_label_width,
  }
end

local function render_chart_block(name, totals, chart_data)
  chart_data = chart_data or {}

  if name == 'chart-risk-summary' then
    return charts.render_risk(chart_data.risk or totals, chart_opts())
  end
  if name == 'chart-nsloc-total' then
    return charts.render_sloc(chart_data.sloc or totals, { width = 48 })
  end
  if name == 'chart-num-bar' then
    return charts.render_summary(chart_data.summary or totals, chart_opts())
  end
  if name == 'chart-num-bar-ast' then
    return charts.render_ast(chart_data.ast or totals, chart_opts())
  end
  if name == 'chart-num-bar-ast-funccalls' then
    return charts.render_function_calls(chart_data.function_calls or totals, chart_opts())
  end
  if name == 'chart-num-bar-ast-asmcalls' then
    return charts.render_assembly_calls(chart_data.assembly_calls or totals, chart_opts())
  end
  return ansi.dim 'chart unavailable'
end

local function replace_chart_wrappers(text, totals, chart_data)
  return text:gsub('<div class="wrapper".-<canvas id="([^"]+)"></canvas>%s*</div>', function(name)
    return '\n' .. render_chart_block(name, totals, chart_data) .. '\n'
  end)
end

local function replace_graph_wrappers(text, dot_graphs)
  text = text:gsub('<div class="wrapper".-<div id="([^"]+)".-</div>%s*</div>', function(name)
    local graph_name = '#' .. name
    return '\n' .. graphs.render(graph_name, dot_graphs[graph_name]) .. '\n'
  end)
  return text
end

local function remove_toggle_anchors(text)
  text = text:gsub('<a%s+onclick="toggleVisibility.-">%[[^%]]+%]</a>', '')
  return text
end

local function strip_remaining_html(text)
  return text:gsub('</?[^>]+>', '')
end

local function strip_markdown_links(text)
  return text:gsub('%[([^%]]+)%]%([^%)]+%)', '%1')
end

local function split_table_row(line)
  if not line:match '^|' then
    return nil
  end

  local content = line:gsub('^|', ''):gsub('|%s*$', '')
  local cells = vim.split(content, '|', { plain = true, trimempty = false })
  for i, cell in ipairs(cells) do
    cells[i] = trim(cell)
  end
  return cells
end

local function is_table_separator(line)
  return line:match '^|[%s:%-%|]+$' ~= nil
end

local function format_cell(cell)
  cell = cell:gsub('%*%*', '')
  cell = cell:gsub('`', '')
  cell = cell:gsub('%s+', ' ')
  return trim(cell)
end

local function cell_width(cell)
  return vim.fn.strdisplaywidth(cell)
end

local function format_table_block(block)
  local rows = {}
  local widths = {}

  for _, line in ipairs(block) do
    local cells = split_table_row(line)
    if cells then
      for i, cell in ipairs(cells) do
        cells[i] = format_cell(cell)
      end
      rows[#rows + 1] = cells
      for i, cell in ipairs(cells) do
        widths[i] = math.max(widths[i] or 0, cell_width(cell))
      end
    end
  end

  if #rows == 0 then
    return block
  end

  local function border(left, middle, right, fill)
    local parts = { left }
    for i, width in ipairs(widths) do
      parts[#parts + 1] = string.rep(fill, width + 2)
      parts[#parts + 1] = i == #widths and right or middle
    end
    return table.concat(parts)
  end

  local function row(cells)
    local parts = { '│' }
    for i, width in ipairs(widths) do
      local cell = cells[i] or ''
      local pad = math.max(width - cell_width(cell), 0)
      parts[#parts + 1] = ' ' .. cell .. string.rep(' ', pad + 1)
      parts[#parts + 1] = '│'
    end
    return table.concat(parts)
  end

  local out = { border('┌', '┬', '┐', '─') }
  for i, cells in ipairs(rows) do
    out[#out + 1] = row(cells)
    if i == 1 and #rows > 1 then
      out[#out + 1] = border('├', '┼', '┤', '─')
    elseif i < #rows then
      out[#out + 1] = border('├', '┼', '┤', '─')
    end
  end
  out[#out + 1] = border('└', '┴', '┘', '─')
  return out
end

local function format_tables(text)
  local lines = vim.split(text, '\n', { plain = true })
  local out = {}
  local i = 1

  while i <= #lines do
    if lines[i]:match '^|' then
      local block = {}
      while i <= #lines and lines[i]:match '^|' do
        if not is_table_separator(lines[i]) then
          block[#block + 1] = lines[i]
        end
        i = i + 1
      end
      local formatted = format_table_block(block)
      for _, line in ipairs(formatted) do
        out[#out + 1] = line
      end
    else
      out[#out + 1] = lines[i]
      i = i + 1
    end
  end

  return table.concat(out, '\n')
end

local function stylize_headings(text)
  local lines = vim.split(text, '\n', { plain = true })
  for i, line in ipairs(lines) do
    local hashes, title = line:match('^(#+)%s+(.+)$')
    if hashes and title then
      local indent = string.rep('  ', math.max(#hashes - 1, 0))
      lines[i] = indent .. ansi.bold(title)
    elseif line:match '^____$' then
      lines[i] = ansi.gray(string.rep('─', 72))
    end
  end
  return table.concat(lines, '\n')
end

function M.render_native(report)
  local text = report.markdown
  text = strip_banner(text)
  text = replace_chart_wrappers(text, report.totals, report.charts)
  text = replace_graph_wrappers(text, report.dot_graphs or {})
  text = remove_toggle_anchors(text)
  text = replace_html_breaks(text)
  text = replace_inline_html(text)
  text = replace_list_html(text)
  text = strip_container_html(text)
  text = strip_remaining_html(text)
  text = strip_markdown_links(text)
  text = cleanup_lines(text)
  text = format_tables(text)
  text = stylize_headings(text)
  return text .. '\n'
end

function M.render_visual_text(markdown)
  local text = strip_banner(markdown)
  text = text:gsub('<div class="wrapper".-<canvas id="([^"]+)"></canvas>%s*</div>', function(name)
    return '\n' .. visuals.marker(name) .. '\n'
  end)
  text = text:gsub('<div class="wrapper".-<div id="([^"]+)".-</div>%s*</div>', function(name)
    return '\n' .. visuals.marker(name) .. '\n'
  end)
  text = remove_toggle_anchors(text)
  text = replace_html_breaks(text)
  text = replace_inline_html(text)
  text = replace_list_html(text)
  text = strip_container_html(text)
  text = strip_remaining_html(text)
  text = strip_markdown_links(text)
  text = cleanup_lines(text)
  text = format_tables(text)
  return trim(text)
end

function M.sanitize_for_nvim(markdown)
  local text = M.render_visual_text(markdown)
  text = text:gsub('%[%[SM_VISUAL:[^%]]+%]%]', '')
  return trim(cleanup_lines(text))
end

return M
