-- The symbols that enclose the cursor, from the real language server of the buffer.
-- The outline of a buffer is fetched again when the buffer changes, never inside a completion request.
local M = {}

local method = "textDocument/documentSymbol"
local outlines = {}

local function source(buf)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf, method = method })) do
    if client.name ~= "plan_complete" then
      return client
    end
  end
end

function M.refresh(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local known = outlines[buf]
  if known and known.tick == tick then
    return
  end
  local client = source(buf)
  if not client then
    return
  end
  outlines[buf] = { tick = tick, symbols = known and known.symbols or {} }
  client:request(method, { textDocument = vim.lsp.util.make_text_document_params(buf) }, function(err, result)
    if not err and outlines[buf] and outlines[buf].tick == tick then
      outlines[buf].symbols = result or {}
    end
  end, buf)
end

local function contains(range, position)
  local first, last = range.start, range["end"]
  if position.line < first.line or position.line > last.line then
    return false
  end
  if position.line == first.line and position.character < first.character then
    return false
  end
  return position.line < last.line or position.character <= last.character
end

--- The path at an LSP position, outermost first: { { name = "ResponseCache", kind = 5 }, ... }.
function M.at(buf, position)
  local path = {}
  local level = outlines[buf] and outlines[buf].symbols or {}
  while true do
    local inside
    for _, symbol in ipairs(level) do
      if symbol.range and contains(symbol.range, position) then
        inside = symbol
        break
      end
    end
    if not inside then
      return path
    end
    table.insert(path, { name = inside.name, kind = inside.kind })
    level = inside.children or {}
  end
end

function M.watch(group)
  vim.api.nvim_create_autocmd({ "LspAttach", "BufEnter", "InsertEnter", "TextChanged", "TextChangedI" }, {
    group = group,
    callback = function(args)
      M.refresh(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(args)
      outlines[args.buf] = nil
    end,
  })
end

return M
