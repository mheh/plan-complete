-- Plan-guided ghost text for Neovim 0.12+.
--
--   require("plan_complete").setup({ cmd = { "/path/to/plan-complete", "serve" } })
--
-- Attaches beside the real language server for every file type. <Tab> accepts, <M-]> / <M-[> cycle.
local M = {}

local defaults = {
  cmd = { "plan-complete", "serve" },
  filetypes = nil,
  root_markers = { ".plan-complete.json", ".git" },
  settings = {},
  accept_key = "<Tab>",
  next_key = "<M-]>",
  prev_key = "<M-[>",
}

function M.setup(opts)
  opts = vim.tbl_deep_extend("force", defaults, opts or {})

  vim.lsp.config("plan_complete", {
    cmd = opts.cmd,
    filetypes = opts.filetypes,
    root_markers = opts.root_markers,
    init_options = opts.settings,
    workspace_required = false,
  })

  if opts.filetypes then
    vim.lsp.enable("plan_complete")
  else
    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("plan_complete", { clear = true }),
      callback = function(args)
        if vim.bo[args.buf].buftype ~= "" then
          return
        end
        local root = vim.fs.root(args.buf, opts.root_markers) or vim.fs.dirname(vim.api.nvim_buf_get_name(args.buf))
        vim.lsp.start(vim.tbl_extend("force", vim.lsp.config.plan_complete, {
          name = "plan_complete",
          root_dir = root,
        }), { bufnr = args.buf })
      end,
    })
  end

  vim.lsp.inline_completion.enable()

  if opts.accept_key then
    vim.keymap.set("i", opts.accept_key, function()
      if not vim.lsp.inline_completion.get() then
        return opts.accept_key == "<Tab>" and "\t" or vim.keycode(opts.accept_key)
      end
    end, { expr = true, replace_keycodes = true, desc = "Accept plan-complete suggestion" })
  end
  if opts.next_key then
    vim.keymap.set("i", opts.next_key, function() vim.lsp.inline_completion.select({ count = 1 }) end)
  end
  if opts.prev_key then
    vim.keymap.set("i", opts.prev_key, function() vim.lsp.inline_completion.select({ count = -1 }) end)
  end
end

return M
