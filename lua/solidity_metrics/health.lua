local config = require 'solidity_metrics.config'
local runner = require 'solidity_metrics.runner'

local M = {}

function M.check()
  vim.health.start 'solidity-metrics.nvim'

  local ok, cmd, source = runner.detect_command()
  if ok then
    vim.health.ok(('metrics command found (%s): %s'):format(source, cmd))
  else
    vim.health.error(('metrics command not found (%s): %s'):format(source, cmd), {
      'Install `solidity-code-metrics` in the project with `npm i -D solidity-code-metrics`,',
      'or install it globally with `npm i -g solidity-code-metrics`,',
      "or set `require('solidity_metrics').setup({ cmd = { 'node', '/path/to/solidity-metrics/src/cli.js' } })`.",
    })
  end

  if vim.fn.executable 'node' == 1 then
    vim.health.ok 'node is available'
  else
    vim.health.warn 'node is not available in PATH'
  end

  if vim.fn.executable 'rg' == 1 then
    vim.health.ok 'ripgrep found for fast workspace discovery'
  else
    vim.health.info 'ripgrep not found; plugin will use Lua filesystem scanning'
  end

  if config.options.visual.enabled then
    if vim.fn.executable 'dot' == 1 then
      vim.health.ok 'graphviz dot found for visual report rendering'
    else
      vim.health.error 'graphviz dot not found; visual report rendering is unavailable'
    end

    if vim.fn.executable 'node' == 1 then
      vim.health.ok 'node found for PNG chart rendering'
    else
      vim.health.error 'node not found; visual report rendering is unavailable'
    end

    local image_ok = pcall(require, 'image')
    if image_ok then
      vim.health.ok 'image.nvim found for inline chart/graph rendering'
    else
      vim.health.error 'image.nvim not found; visual report rendering is unavailable'
    end
  else
    vim.health.info 'visual report mode disabled in config'
  end

  vim.health.info(('default scopefile: %s'):format(config.options.scopefile))
  vim.health.info(('prefer_local: %s'):format(tostring(config.options.prefer_local)))
end

return M
