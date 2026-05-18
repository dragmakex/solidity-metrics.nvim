# solidity-metrics.nvim

Neovim integration for [`solidity-code-metrics`](https://www.npmjs.com/package/solidity-code-metrics).

It wraps the official npm package, discovers Solidity files, renders a native Neovim report with inline charts and graphs via `image.nvim` + Graphviz derived from the upstream data, and exports HTML reports that match the upstream tool.

## Features

- Analyze the current Solidity file
- Analyze a workspace or any supplied directory
- Analyze from `scope.txt` or another scope file
- Render reports in a split, tab, or floating window
- Native Neovim charts for risk, source lines, summary, AST, function calls, and assembly calls via `image.nvim`
- Native Neovim inheritance and call graph rendering via Graphviz + `image.nvim`
- Export full HTML reports

## Requirements

- Neovim >= 0.9
- Node.js (install via [nvm](https://github.com/nvm-sh/nvm))
- [3rd/image.nvim](https://github.com/3rd/image.nvim) configured and working
- [Graphviz](https://graphviz.org/download/) (provides the `dot` binary)
- `solidity-code-metrics` available in one of these ways:
  - project-local install in `node_modules/.bin` (preferred; auto-detected)
  - globally in `$PATH`
  - via a custom `cmd`

## Installation

### lazy.nvim

```lua
{
  "dragmakex/solidity-metrics.nvim",
  ft = "solidity",
  dependencies = { "3rd/image.nvim" },
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
  visual = {
    enabled = true,
    strict = true,
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
- Visual report mode is strict by default: if `image.nvim` or Graphviz `dot` is missing, the native visual report will not render.
- HTML export uses `vim.ui.open()` when available, otherwise `open`/`xdg-open`/`start`.

## License

MIT
