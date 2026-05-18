local M = {}

local esc = string.char(27)

function M.reset()
  return esc .. '[0m'
end

function M.bold(text)
  return esc .. '[1m' .. text .. M.reset()
end

function M.dim(text)
  return esc .. '[2m' .. text .. M.reset()
end

function M.fg(code, text)
  return esc .. '[' .. code .. 'm' .. text .. M.reset()
end

function M.blue(text)
  return M.fg('34', text)
end

function M.cyan(text)
  return M.fg('36', text)
end

function M.green(text)
  return M.fg('32', text)
end

function M.yellow(text)
  return M.fg('33', text)
end

function M.magenta(text)
  return M.fg('35', text)
end

function M.red(text)
  return M.fg('31', text)
end

function M.white(text)
  return M.fg('37', text)
end

function M.gray(text)
  return M.fg('90', text)
end

function M.strip(text)
  return text:gsub(esc .. '%[[0-9;]*m', '')
end

return M
