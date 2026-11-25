-- Plan-guided ghost text for Neovim 0.12+.
--
--   require("plan_complete").setup({ cmd = { "/path/to/plan-complete", "serve" } })
--
-- Attaches beside the real language server for every file type. The server stays quiet unless the
-- project has a .plan-complete.json and its plan (PLAN.md by default).
-- :PlanCompleteEnable opts the project in. <Tab> accepts, <M-]> / <M-[> cycle.
-- :PlanCompleteToggle turns it off and on for this session.
local symbols = require("plan_complete.symbols")

local M = {}

local defaults = {
  cmd = { "plan-complete", "serve" },
  filetypes = nil,
  root_markers = { ".plan-complete.json", "PLAN.md", ".git" },
  settings = {},
  accept_key = "<Tab>",
  next_key = "<M-]>",
  prev_key = "<M-[>",
}

local state = { active = false, reason = "not started" }
local enabled = true

--- The plan state that the server reported last: { active = bool, reason = string }.
function M.status()
  return state
end

--- A short text for a statusline: "Plan: on", "Plan: no model" or "Plan: off (no PLAN.md)".
function M.statusline()
  if not state.active then
    return "Plan: off (" .. state.reason .. ")"
  end
  return state.problem and "Plan: no model" or "Plan: on"
end

local function sends_symbols()
  return state.context ~= nil and state.context.symbols == true
end

local function with_symbol_path(client)
  local request = client.request
  client.request = function(self, method, params, handler, bufnr)
    if method == "textDocument/inlineCompletion" and sends_symbols() then
      local buf = vim.uri_to_bufnr(params.textDocument.uri)
      params = vim.tbl_extend("force", params, { symbolPath = symbols.at(buf, params.position) })
    end
    return request(self, method, params, handler, bufnr)
  end
end

local function clients()
  return vim.lsp.get_clients({ name = "plan_complete" })
end

function M.set_enabled(value)
  enabled = value
  for _, client in ipairs(clients()) do
    client:request("planComplete/setEnabled", { enabled = value }, function() end)
  end
end

--- Writes .plan-complete.json, and a starter plan when there is none, then opens the plan.
function M.enable()
  local client = clients()[1]
  if not client then
    return vim.notify("plan-complete: the server is not running", vim.log.levels.WARN)
  end
  M.set_enabled(true)
  client:request("planComplete/enable", vim.empty_dict(), function(err, result)
    if err then
      return vim.notify("plan-complete: " .. err.message, vim.log.levels.ERROR)
    end
    for _, name in ipairs(result.created) do
      if name:lower():match("%.md$") then
        vim.cmd.edit(vim.fs.joinpath(client.root_dir, name))
      end
    end
    vim.notify("plan-complete: " .. (#result.created > 0 and "wrote " .. table.concat(result.created, ", ") or "already enabled"))
  end)
end

function M.toggle()
  M.set_enabled(not enabled)
  vim.notify("plan-complete: " .. (enabled and "on" or "off for this session"))
end

function M.setup(opts)
  opts = vim.tbl_deep_extend("force", defaults, opts or {})

  vim.lsp.config("plan_complete", {
    cmd = opts.cmd,
    filetypes = opts.filetypes,
    root_markers = opts.root_markers,
    init_options = opts.settings,
    workspace_required = false,
    handlers = {
      ["planComplete/status"] = function(_, params)
        state = params
        vim.cmd.redrawstatus()
      end,
    },
    on_init = function(client)
      with_symbol_path(client)
      if not enabled then
        client:request("planComplete/setEnabled", { enabled = false }, function() end)
      end
    end,
  })

  local group = vim.api.nvim_create_augroup("plan_complete", { clear = true })
  symbols.watch(group)

  if opts.filetypes then
    vim.lsp.enable("plan_complete")
  else
    vim.api.nvim_create_autocmd("FileType", {
      group = group,
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

  vim.api.nvim_create_user_command("PlanCompleteToggle", M.toggle, { desc = "Turn plan-complete off or on" })
  vim.api.nvim_create_user_command("PlanCompleteEnable", M.enable, { desc = "Opt this project in to plan-complete" })
  vim.api.nvim_create_user_command("PlanCompleteStatus", function()
    vim.notify("plan-complete: " .. M.statusline() .. (state.problem and (": " .. state.problem) or ""))
  end, { desc = "Show the plan state" })

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
