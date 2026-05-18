local ansi = require 'solidity_metrics.ansi'

local M = {}

local block = '█'
local empty = '░'
local default_width = 32

local palette = {
  ansi.blue,
  ansi.cyan,
  ansi.green,
  ansi.yellow,
  ansi.magenta,
  ansi.red,
  ansi.white,
}

local function pad_right(text, width)
  if #text >= width then
    return text
  end
  return text .. string.rep(' ', width - #text)
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

local function render_bar(value, max_value, width, colorize, use_log)
  local filled = math.floor(scale_value(value, max_value, use_log) * width + 0.5)
  filled = clamp(filled, 0, width)
  local bar = string.rep(block, filled) .. string.rep(empty, width - filled)
  if colorize then
    return colorize(string.rep(block, filled)) .. ansi.gray(string.rep(empty, width - filled))
  end
  return bar
end

local function truncate_label(label, width)
  if #label <= width then
    return label
  end
  if width <= 1 then
    return label:sub(1, width)
  end
  return label:sub(1, width - 1) .. '…'
end

local function get_risks(data)
  local avg = data.avg.summary or {}
  local totals = data.totals.summary or {}
  local keys = {}
  local seen = {}

  for key in pairs(avg) do
    if not seen[key] then
      seen[key] = true
      keys[#keys + 1] = key
    end
  end
  for key in pairs(totals) do
    if not seen[key] then
      seen[key] = true
      keys[#keys + 1] = key
    end
  end

  table.sort(keys)

  local overall = {}
  local average = {}
  for _, key in ipairs(keys) do
    overall[#overall + 1] = totals[key] or 0
    average[#average + 1] = avg[key] or 0
  end

  return {
    keys = keys,
    totals = overall,
    avg = average,
  }
end

local function get_sloc(data)
  local keys = {}
  for key in pairs(data.totals.nsloc or {}) do
    if key ~= 'total' and key ~= 'commentToSourceRatio' then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys)

  local sloc = {}
  local nsloc = {}
  for _, key in ipairs(keys) do
    sloc[#sloc + 1] = (data.totals.sloc or {})[key] or 0
    nsloc[#nsloc + 1] = (data.totals.nsloc or {})[key] or 0
  end

  return {
    keys = keys,
    sloc = sloc,
    nsloc = nsloc,
  }
end

local function get_num(data)
  local keys = {}
  for key in pairs(data.totals.num or {}) do
    keys[#keys + 1] = key
  end
  table.sort(keys)

  local totals = {}
  local avg = {}
  for _, key in ipairs(keys) do
    totals[#totals + 1] = (data.totals.num or {})[key] or 0
    avg[#avg + 1] = (data.avg.num or {})[key] or 0
  end

  return {
    keys = keys,
    totals = totals,
    avg = avg,
  }
end

local function get_num_ast(data, filter_key)
  local keys = {}
  for key, value in pairs(data.totals.ast or {}) do
    if type(value) == 'number' and (not filter_key or filter_key(key)) then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys)

  local totals = {}
  local avg = {}
  for _, key in ipairs(keys) do
    totals[#totals + 1] = (data.totals.ast or {})[key] or 0
    avg[#avg + 1] = (data.avg.ast or {})[key] or 0
  end

  return {
    keys = keys,
    totals = totals,
    avg = avg,
  }
end

local function render_dual_series(dataset, opts)
  opts = opts or {}
  local keys = dataset.keys or {}
  local totals = dataset.totals or {}
  local avg = dataset.avg or {}
  local label_width = opts.label_width or 22
  local width = opts.width or default_width
  local use_log = opts.use_log or false
  local max_value = 0
  local lines = {}

  for i = 1, #keys do
    max_value = math.max(max_value, totals[i] or 0, avg[i] or 0)
  end

  lines[#lines + 1] = ansi.bold('  total') .. ' vs ' .. ansi.bold('average') .. (use_log and ansi.dim('  (log scale)') or '')
  for i, key in ipairs(keys) do
    local total_bar = render_bar(totals[i] or 0, max_value, width, ansi.blue, use_log)
    local avg_bar = render_bar(avg[i] or 0, max_value, width, ansi.cyan, use_log)
    local label = pad_right(truncate_label(key, label_width), label_width)
    lines[#lines + 1] = string.format(
      '%s  %s %6s  %s %6s',
      label,
      total_bar,
      tostring(totals[i] or 0),
      avg_bar,
      tostring(avg[i] or 0)
    )
  end

  return table.concat(lines, '\n')
end

local function render_stacked_bar(values, total, width)
  if total <= 0 then
    return ansi.gray(string.rep(empty, width))
  end

  local segments = {}
  local remaining = width
  for i, value in ipairs(values) do
    local segment_width = i == #values and remaining or math.floor((value / total) * width + 0.5)
    segment_width = clamp(segment_width, 0, remaining)
    remaining = remaining - segment_width
    local painter = palette[((i - 1) % #palette) + 1]
    segments[#segments + 1] = painter(string.rep(block, segment_width))
  end
  if remaining > 0 then
    segments[#segments + 1] = ansi.gray(string.rep(empty, remaining))
  end
  return table.concat(segments)
end

local function render_sloc(dataset, opts)
  opts = opts or {}
  local width = opts.width or 48
  local legend = {}
  local lines = {}
  local sloc_total = 0
  local nsloc_total = 0

  for i, _ in ipairs(dataset.keys or {}) do
    sloc_total = sloc_total + (dataset.sloc[i] or 0)
    nsloc_total = nsloc_total + (dataset.nsloc[i] or 0)
    local painter = palette[((i - 1) % #palette) + 1]
    legend[#legend + 1] = painter(dataset.keys[i]) .. '=' .. tostring(dataset.sloc[i] or 0)
  end

  lines[#lines + 1] = 'legend: ' .. table.concat(legend, '  ')
  lines[#lines + 1] = string.format('sloc  %s  %s', render_stacked_bar(dataset.sloc, sloc_total, width), sloc_total)
  lines[#lines + 1] = string.format('nsloc %s  %s', render_stacked_bar(dataset.nsloc, nsloc_total, width), nsloc_total)
  return table.concat(lines, '\n')
end

function M.render_risk(data, opts)
  local dataset = data.keys and data or get_risks(data)
  return render_dual_series(dataset, opts)
end

function M.render_sloc(data, opts)
  local dataset = data.keys and data or get_sloc(data)
  return render_sloc(dataset, opts)
end

function M.render_summary(data, opts)
  local dataset = data.keys and data or get_num(data)
  return render_dual_series(dataset, vim.tbl_extend('force', { use_log = true }, opts or {}))
end

function M.render_ast(data, opts)
  local dataset = data.keys and data or get_num_ast(data, function(key)
    return not key:find('^FunctionCall:Name:') and not key:find('^AssemblyCall:Name:')
  end)
  return render_dual_series(dataset, vim.tbl_extend('force', { use_log = true }, opts or {}))
end

function M.render_function_calls(data, opts)
  local dataset = data.keys and data or get_num_ast(data, function(key)
    return key:find('^FunctionCall:Name:') ~= nil
  end)
  return render_dual_series(dataset, vim.tbl_extend('force', { use_log = true }, opts or {}))
end

function M.render_assembly_calls(data, opts)
  local dataset = data.keys and data or get_num_ast(data, function(key)
    return key:find('^AssemblyCall:Name:') ~= nil
  end)
  return render_dual_series(dataset, vim.tbl_extend('force', { use_log = true }, opts or {}))
end

return M
