local config = require 'solidity_metrics.config'

local M = {}

local last_buf

local function set_buffer_keymaps(buf)
  vim.keymap.set('n', 'q', '<cmd>close<cr>', { buffer = buf, silent = true, nowait = true })
end

local function create_buffer(name)
  local buf = vim.api.nvim_create_buf(true, false)
  local bo = vim.bo[buf]
  bo.bufhidden = 'wipe'
  bo.buftype = 'nofile'
  bo.swapfile = false
  bo.modifiable = true
  bo.filetype = 'markdown'
  bo.buflisted = true
  vim.api.nvim_buf_set_name(buf, name)
  set_buffer_keymaps(buf)
  return buf
end

local function open_split()
  vim.cmd(config.options.output.split)
  return vim.api.nvim_get_current_win()
end

local function open_float()
  local width = config.options.output.float.width
  local height = config.options.output.float.height

  if width < 1 then
    width = math.floor(vim.o.columns * width)
  end
  if height < 1 then
    height = math.floor(vim.o.lines * height)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    border = config.options.output.float.border,
    width = width,
    height = height,
    row = math.max(row, 0),
    col = math.max(col, 0),
    style = 'minimal',
  })

  return win, buf
end

local function open_tab()
  vim.cmd 'tabnew'
  return vim.api.nvim_get_current_win()
end

function M.render(markdown, title)
  local kind = config.options.output.kind
  local win, buf

  if kind == 'float' then
    win, buf = open_float()
  elseif kind == 'tab' then
    win = open_tab()
  else
    win = open_split()
  end

  if not buf then
    buf = create_buffer(title)
    vim.api.nvim_win_set_buf(win, buf)
  else
    vim.bo[buf].filetype = 'markdown'
    vim.api.nvim_buf_set_name(buf, title)
    set_buffer_keymaps(buf)
  end

  local lines = vim.split(markdown, '\n', { plain = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  last_buf = buf
  return buf, win
end

function M.last_buf()
  return last_buf
end

return M
