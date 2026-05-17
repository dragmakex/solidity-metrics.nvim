local uv = vim.uv or vim.loop
local config = require 'solidity_metrics.config'
local util = require 'solidity_metrics.util'

local M = {}

local function scandir(root, base_root, exclude, acc)
  local fd = uv.fs_scandir(root)
  if not fd then
    return
  end

  while true do
    local name, entry_type = uv.fs_scandir_next(fd)
    if not name then
      break
    end

    local full = util.join(root, name)
    local relative = util.relpath(full, base_root)
    if entry_type == 'directory' then
      if not util.matches_any(relative, exclude) and not util.matches_any(relative .. '/', exclude) then
        scandir(full, base_root, exclude, acc)
      end
    elseif entry_type == 'file' and name:sub(-4) == '.sol' then
      acc[#acc + 1] = full
    end
  end
end

local function list_with_rg(root)
  if vim.fn.executable 'rg' ~= 1 then
    return nil
  end

  local result = vim.system({ 'rg', '--files', '-g', '*.sol' }, { cwd = root, text = true }):wait()
  if result.code ~= 0 then
    return nil
  end

  local found = {}
  for line in vim.gsplit(result.stdout or '', '\n', { plain = true, trimempty = true }) do
    found[#found + 1] = util.join(root, line)
  end
  return found
end

function M.collect_solidity_files(root, opts)
  opts = opts or {}
  local exclude = opts.exclude or config.options.exclude
  local found = list_with_rg(root)
  if not found then
    found = {}
    scandir(root, root, exclude, found)
  end

  local filtered = {}
  for _, file in ipairs(found) do
    local relative = util.relpath(file, root)
    if not util.matches_any(relative, exclude) and not util.matches_any(file, exclude) then
      filtered[#filtered + 1] = file
    end
  end

  table.sort(filtered)
  return filtered
end

return M
