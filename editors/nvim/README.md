# Neovim (0.12+)

```lua
vim.opt.rtp:append("/path/to/xcode-mcp-autocomplete/editors/nvim")
require("plan_complete").setup({
  cmd = { "/path/to/xcode-mcp-autocomplete/.build/release/plan-complete", "serve" },
  -- filetypes = { "swift", "python" },   -- default: every file type
  -- settings = { model = "qwen2.5-coder" },  -- overrides .plan-complete.json
})
```

`<Tab>` accepts, `<M-]>` / `<M-[>` cycle. Neovim debounces requests by 200 ms.

Check: `PC_BIN=$PWD/.build/debug/plan-complete PC_LINE=13 PC_COL=18 nvim --headless -u scripts/nvim-smoke.lua FILE`
