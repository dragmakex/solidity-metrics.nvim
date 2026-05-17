# solidity-metrics.nvim

Neovim integration for [`solidity-code-metrics`](https://www.npmjs.com/package/solidity-code-metrics).

It wraps the official npm package, discovers Solidity files, renders Markdown reports inside Neovim, and exports HTML reports that match the upstream tool.

## Features

- Analyze the current Solidity file
- Analyze a workspace or any supplied directory
- Analyze from `scope.txt` or another scope file
- Render reports in a split, tab, or floating window
- Export HTML reports
- Health checks for Node / ripgrep / metrics command
- No Lua dependencies

## Requirements

- Neovim >= 0.9
- Node.js
- `solidity-code-metrics` available in one of these ways:
  - project-local install in `node_modules/.bin` (preferred; auto-detected)
  - globally in `$PATH`
  - via a custom `cmd`
  - via `npx` fallback

## Installation

### lazy.nvim

```lua
{
  "dragmakex/solidity-metrics.nvim",
  ft = "solidity",
  opts = {},
}
```

### Recommended: project-local install

```sh
npm i -D solidity-code-metrics
```

The plugin will automatically prefer:

1. `./node_modules/.bin/solidity-code-metrics`
2. global `solidity-code-metrics`
3. `npx` if `use_npx = true`

### Using a local checkout of the upstream CLI

```lua
require("solidity_metrics").setup({
  cmd = { "node", "/absolute/path/to/solidity-metrics/src/cli.js" },
})
```

## Default configuration

```lua
require("solidity_metrics").setup({
  cmd = nil,
  prefer_local = true,
  local_bin = "solidity-code-metrics",
  use_npx = false,
  npx_package = "solidity-code-metrics@0.0.28",
  timeout = 120000,
  scopefile = "scope.txt",
  workspace_root_markers = {
    ".git",
    "foundry.toml",
    "hardhat.config.js",
    "hardhat.config.ts",
    "truffle-config.js",
    "truffle.js",
    "package.json",
  },
  exclude = {
    "**/node_modules/**",
    "**/mock*/**",
    "**/test*/**",
    "**/migrations/**",
    "**/Migrations.sol",
  },
  output = {
    kind = "split", -- split | float | tab
    split = "botright new",
    float = {
      border = "rounded",
      width = 0.9,
      height = 0.9,
    },
  },
  html = {
    open = true,
    filename = "solidity-metrics.html",
  },
  notify = true,
})
```

## Commands

- `:SolidityMetricsFile`
- `:SolidityMetricsWorkspace [path]`
- `:SolidityMetricsScope [file]`
- `:SolidityMetricsHtml [output]`

`SolidityMetricsHtml` exports the **last request** by default.

## Scope files

Scope files are passed directly to the upstream CLI. Each line should contain a file path or glob pattern accepted by `solidity-code-metrics`.

## Health

```vim
:checkhealth solidity_metrics
```

## Notes

- Workspace analysis is implemented by building a temporary scope file from discovered `.sol` files.
- If `rg` is installed, it is used for faster file discovery.
- HTML export uses `vim.ui.open()` when available, otherwise `open`/`xdg-open`/`start`.

## License

MIT
