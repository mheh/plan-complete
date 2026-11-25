-- PC_BIN=... PC_LINE=13 PC_COL=18 nvim --headless -u scripts/nvim-smoke.lua FILE
-- PC_LINE is 1-based, PC_COL 0-based. Prints the ghost text, accepts it, prints the line.
local repo = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(repo .. "/editors/nvim")
vim.opt.swapfile = false
local line, col = tonumber(vim.env.PC_LINE), tonumber(vim.env.PC_COL)

local function finish(code, text)
  io.stdout:write(text .. "\n")
  vim.cmd("qa!")
  os.exit(code)
end

require("plan_complete").setup({ cmd = { vim.env.PC_BIN, "serve" } })

vim.api.nvim_create_autocmd("LspAttach", {
  once = true,
  callback = function(args)
    vim.schedule(function()
      vim.api.nvim_win_set_cursor(0, { line, col })
      vim.api.nvim_feedkeys("a", "n", false)
    end)
    local ns = vim.api.nvim_create_namespace("nvim.lsp.inline_completion")
    local started = vim.uv.now()
    local timer = vim.uv.new_timer()
    timer:start(100, 100, vim.schedule_wrap(function()
      local marks = vim.api.nvim_buf_get_extmarks(args.buf, ns, 0, -1, { details = true })
      if #marks > 0 then
        timer:stop()
        local parts = {}
        for _, m in ipairs(marks) do
          for _, chunk in ipairs(m[4].virt_text or {}) do table.insert(parts, chunk[1]) end
          for _, l in ipairs(m[4].virt_lines or {}) do
            local p = {}
            for _, chunk in ipairs(l) do table.insert(p, chunk[1]) end
            table.insert(parts, "\n" .. table.concat(p))
          end
        end
        io.stdout:write(("status: %s\n"):format(require("plan_complete").statusline()))
        io.stdout:write(("ghost (%d ms, mode %s): %s\n"):format(vim.uv.now() - started, vim.api.nvim_get_mode().mode, table.concat(parts)))
        vim.lsp.inline_completion.get()
        vim.defer_fn(function()
          finish(0, "after accept: " .. vim.api.nvim_buf_get_lines(args.buf, line - 1, line, false)[1])
        end, 50)
      elseif vim.uv.now() - started > (vim.env.PC_EXPECT == "off" and 4000 or 10000) then
        timer:stop()
        finish(vim.env.PC_EXPECT == "off" and 0 or 1, "no ghost text; status: " .. require("plan_complete").statusline())
      end
    end))
  end,
})

vim.defer_fn(function() finish(1, "FAIL: client did not attach") end, 15000)
