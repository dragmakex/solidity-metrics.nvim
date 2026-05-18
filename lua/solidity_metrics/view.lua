local config = require 'solidity_metrics.config'
local visuals = require 'solidity_metrics.visuals'

local M = {}

local function reset_buffer(buf)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
end

local function set_buffer_keymaps(buf)
  vim.keymap.set('n', 'q', '<cmd>close<cr>', { buffer = buf, silent = true, nowait = true })
end

local function setup_buffer(buf, name)
  local bo = vim.bo[buf]
  bo.bufhidden = 'wipe'
  bo.buftype = 'nofile'
  bo.swapfile = false
  bo.modifiable = true
  bo.buflisted = true
  vim.api.nvim_buf_set_name(buf, name)
  set_buffer_keymaps(buf)
end

local function create_buffer(name)
  local buf = vim.api.nvim_create_buf(true, false)
  setup_buffer(buf, name)
  vim.bo[buf].filetype = 'markdown'
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

local function open_output(title)
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
    setup_buffer(buf, title)
  end

  vim.wo[win].wrap = false
  vim.wo[win].linebreak = false
  return buf, win
end

function M.render(markdown, title)
  local buf, win = open_output(title)
  vim.bo[buf].filetype = 'markdown'
  reset_buffer(buf)

  local lines = vim.split(markdown, '\n', { plain = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  return buf, win
end

function M.render_ansi(text, title)
  local buf, win = open_output(title)
  vim.bo[buf].filetype = 'solidity_metrics'
  reset_buffer(buf)

  local chan = vim.api.nvim_open_term(buf, {})
  vim.api.nvim_chan_send(chan, text)
  vim.bo[buf].modifiable = false
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  return buf, win
end

function M.render_visual(markdown, prepared, title)
  local buf, win = open_output(title)
  vim.bo[buf].filetype = 'markdown'
  reset_buffer(buf)

  local lines = vim.split(markdown, '\n', { plain = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local ok, err = visuals.render(buf, win, prepared)
  if not ok then
    return nil, err
  end
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  return buf, win
end

return M
