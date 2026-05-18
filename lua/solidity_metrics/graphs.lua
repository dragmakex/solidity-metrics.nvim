local uv = vim.uv or vim.loop
local ansi = require 'solidity_metrics.ansi'
local util = require 'solidity_metrics.util'

local M = {}

local function cleanup(path)
  if path and util.exists(path) then
    pcall(uv.fs_unlink, path)
  end
end

local function render_with_dot(dot_source)
  if vim.fn.executable 'dot' ~= 1 then
    return nil
  end

  local dot_path = vim.fn.tempname() .. '.dot'
  vim.fn.writefile(vim.split(dot_source, '\n', { plain = true }), dot_path)

  local format = vim.o.termguicolors and 'vt-24bit' or 'vt'
  local result = vim.system({ 'dot', '-T' .. format, dot_path }, { text = false }):wait()
  cleanup(dot_path)

  if result.code ~= 0 or not result.stdout or result.stdout == '' then
    return nil
  end

  local output = result.stdout
  if type(output) ~= 'string' then
    output = table.concat(output)
  end
  return output:gsub('\n+$', '')
end

local function parse_clusters(dot_source)
  local clusters = {}
  local current

  for line in dot_source:gmatch('[^\n]+') do
    local cluster = line:match('^subgraph%s+"cluster([^"]+)"%s+{$')
    if cluster then
      current = cluster
      clusters[current] = clusters[current] or { functions = {}, calls = {} }
    elseif current and line:match '^}$' then
      current = nil
    elseif current then
      local node_name, label = line:match('^%s*"([^"]+)"%s+%[%s*label%s*=%s*"([^"]+)"')
      if node_name and label then
        clusters[current].functions[#clusters[current].functions + 1] = {
          name = node_name,
          label = label,
        }
      end
    end
  end

  for line in dot_source:gmatch('[^\n]+') do
    local from_node, to_node, color = line:match('^%s*"([^"]+)"%s*%-%>%s*"([^"]+)"%s*%[%s*color%s*=%s*"([^"]+)"')
    if from_node and to_node then
      local cluster = from_node:match '^([^.]+)%.'
      clusters[cluster] = clusters[cluster] or { functions = {}, calls = {} }
      clusters[cluster].calls[#clusters[cluster].calls + 1] = {
        from_node = from_node,
        to_node = to_node,
        color = color,
      }
    end
  end

  return clusters
end

local function render_cluster_summary(dot_source)
  local clusters = parse_clusters(dot_source)
  local lines = {
    ansi.dim 'graphviz terminal renderer unavailable; showing structural summary.',
    '',
  }

  local names = vim.tbl_keys(clusters)
  table.sort(names)

  local legend = {
    green = 'internal',
    orange = 'external',
    red = 'custom error',
  }

  for _, cluster in ipairs(names) do
    lines[#lines + 1] = ansi.bold(cluster)
    local items = clusters[cluster]
    table.sort(items.functions, function(a, b)
      return a.label < b.label
    end)

    for _, fn in ipairs(items.functions) do
      lines[#lines + 1] = '  • ' .. fn.label
      for _, call in ipairs(items.calls) do
        if call.from_node == fn.name then
          local suffix = call.to_node:gsub('^[^.]+%.', '')
          local label = legend[call.color] and (' [' .. legend[call.color] .. ']') or ''
          lines[#lines + 1] = '    → ' .. suffix .. label
        end
      end
    end
    lines[#lines + 1] = ''
  end

  return table.concat(lines, '\n'):gsub('\n+$', '')
end

local function render_inheritance_summary(dot_source)
  local parents = {}
  local children = {}
  local nodes = {}

  for line in dot_source:gmatch('[^\n]+') do
    local child, parent = line:match('^%s*"([^"]+)"%s*%-%>%s*"([^"]+)"')
    if child and parent then
      parents[child] = parent
      children[parent] = children[parent] or {}
      table.insert(children[parent], child)
      nodes[child] = true
      nodes[parent] = true
    end

    local node = line:match('^%s*"([^"]+)";%s*$')
    if node then
      nodes[node] = true
    end
  end

  local roots = {}
  for node in pairs(nodes) do
    if not parents[node] then
      roots[#roots + 1] = node
    end
  end
  table.sort(roots)

  local lines = { ansi.dim 'graphviz terminal renderer unavailable; showing inheritance tree.', '' }

  local function walk(node, prefix)
    lines[#lines + 1] = prefix .. node
    local descendants = children[node] or {}
    table.sort(descendants)
    for index, child in ipairs(descendants) do
      local joint = index == #descendants and '└─ ' or '├─ '
      local next_prefix = prefix .. (index == #descendants and '   ' or '│  ')
      lines[#lines + 1] = prefix .. joint .. child
      walk(child, next_prefix)
    end
  end

  for _, root in ipairs(roots) do
    walk(root, '')
    lines[#lines + 1] = ''
  end

  return table.concat(lines, '\n'):gsub('\n+$', '')
end

function M.render(name, dot_source)
  if not dot_source or dot_source == '' then
    return ansi.dim 'no graph data available'
  end

  local rendered = render_with_dot(dot_source)
  if rendered then
    return rendered
  end

  if name == '#surya-inheritance' then
    return render_inheritance_summary(dot_source)
  end
  return render_cluster_summary(dot_source)
end

return M
