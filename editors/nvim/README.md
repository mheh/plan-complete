# Neovim (0.12 or later)

```lua
vim.opt.rtp:append("/path/to/plan-complete/editors/nvim")
require("plan_complete").setup({
  -- cmd = { "/path/to/plan-complete", "serve" },   -- default: plan-complete on PATH
  -- filetypes = { "swift", "python" },             -- default: every file type
  -- settings = { model = "qwen2.5-coder" },        -- overrides the settings files
  -- accept_key = "<Tab>", next_key = "<M-]>", prev_key = "<M-[>",   -- false: no mapping
})
```

The server attaches to every buffer but stays quiet unless the project has a `.plan-complete.json`
and its plan (`PLAN.md` by default).

| Command | Does |
|---|---|
| `:PlanCompleteEnable` | Writes `.plan-complete.json`, and a starter `PLAN.md` when there is none, then opens the plan |
| `:PlanCompleteToggle` | Turns completions off or on for this session |
| `:PlanCompleteStatus` | Shows the state, and why the model server failed when it did |

- `<Tab>` accepts, `<M-]>` / `<M-[>` cycle. Neovim debounces requests by 200 ms.
- Statusline: `require("plan_complete").statusline()` gives `Plan: on`, `Plan: no model` or
  `Plan: off (no PLAN.md)`.

Check: `PC_BIN=$PWD/.build/debug/plan-complete PC_LINE=13 PC_COL=18 nvim --headless -u scripts/nvim-smoke.lua examples/sample/Sources/Net/Cache.swift`
(`PC_EXPECT=off` for a project that is not opted in).
