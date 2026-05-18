local M = {}

local valid_output_kinds = {
  split = true,
  float = true,
  tab = true,
}

M.defaults = {
  cmd = nil,
  prefer_local = true,
  local_bin = 'solidity-code-metrics',
  timeout = 120000,
  scopefile = 'scope.txt',
  file_limit = 5000,
  workspace_root_markers = {
    '.git',
    'foundry.toml',
    'hardhat.config.js',
    'hardhat.config.ts',
    'truffle-config.js',
    'truffle.js',
    'package.json',
  },
  exclude = {
    '**/node_modules/**',
    '**/mock*/**',
    '**/test*/**',
    '**/migrations/**',
    '**/Migrations.sol',
  },
  output = {
    kind = 'split',
    split = 'botright new',
    float = {
      border = 'rounded',
      width = 0.9,
      height = 0.9,
    },
  },
  html = {
    open = true,
    filename = 'solidity-metrics.html',
  },
  visual = {
    enabled = true,
    strict = true,
  },
  notify = true,
}

M.options = vim.deepcopy(M.defaults)

function M.validate(opts)
  opts = opts or {}

  vim.validate {
    cmd = { opts.cmd, { 'table', 'function' }, true },
    prefer_local = { opts.prefer_local, 'boolean', true },
    local_bin = { opts.local_bin, 'string', true },
    timeout = { opts.timeout, 'number', true },
    scopefile = { opts.scopefile, 'string', true },
    file_limit = { opts.file_limit, 'number', true },
    workspace_root_markers = { opts.workspace_root_markers, 'table', true },
    exclude = { opts.exclude, 'table', true },
    output = { opts.output, 'table', true },
    html = { opts.html, 'table', true },
    visual = { opts.visual, 'table', true },
    notify = { opts.notify, 'boolean', true },
  }

  local output = opts.output or {}
  if output.kind ~= nil and not valid_output_kinds[output.kind] then
    error 'solidity-metrics.nvim: output.kind must be one of split, float, tab'
  end
end

function M.setup(opts)
  M.validate(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
end

return M
