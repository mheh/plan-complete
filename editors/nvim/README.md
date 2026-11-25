# Neovim (0.12+)

```lua
vim.opt.rtp:append("/path/to/plan-complete/editors/nvim")
require("plan_complete").setup({
  cmd = { "/path/to/plan-complete/.build/release/plan-complete", "serve" },
  -- filetypes = { "swift", "python" },        -- default: every file type
  -- settings = { model = "qwen2.5-coder" },   -- overrides the config files
})
```

The server attaches to every buffer but stays quiet unless the project has a `.plan-complete.json`
and its plan (`PLAN.md` by default).

- `<Tab>` accepts, `<M-]>` / `<M-[>` cycle. Neovim debounces requests by 200 ms.
- `:PlanCompleteToggle` turns it off or on for this session; `:PlanCompleteStatus` shows the state.
- Statusline: `require("plan_complete").statusline()` gives `Plan: on` or `Plan: off (no PLAN.md)`.

Check: `PC_BIN=$PWD/.build/debug/plan-complete PC_LINE=13 PC_COL=18 nvim --headless -u scripts/nvim-smoke.lua examples/sample/Sources/Net/Cache.swift`
(`PC_EXPECT=off` for a project that is not opted in).
