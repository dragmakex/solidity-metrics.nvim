if vim.g.loaded_solidity_metrics_nvim then
  return
end
vim.g.loaded_solidity_metrics_nvim = true

local sm = require 'solidity_metrics'
local api = vim.api

api.nvim_create_user_command('SolidityMetricsFile', function()
  sm.file()
end, { desc = 'Run Solidity Metrics for the current file' })

api.nvim_create_user_command('SolidityMetricsWorkspace', function(opts)
  sm.workspace { root = opts.args ~= '' and opts.args or nil }
end, {
  desc = 'Run Solidity Metrics for the workspace or supplied path',
  nargs = '?',
  complete = 'dir',
})

api.nvim_create_user_command('SolidityMetricsScope', function(opts)
  sm.scope { scope_file = opts.args ~= '' and opts.args or nil }
end, {
  desc = 'Run Solidity Metrics using a scope file',
  nargs = '?',
  complete = 'file',
})

api.nvim_create_user_command('SolidityMetricsHtml', function(opts)
  sm.export_html { output = opts.args ~= '' and opts.args or nil }
end, {
  desc = 'Export the last Solidity Metrics request as HTML',
  nargs = '?',
  complete = 'file',
})
