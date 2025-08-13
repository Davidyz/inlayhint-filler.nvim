M = {}

local api = vim.api

---@class InlayHintFillerOpts
---@field bufnr integer?
---@field client_id integer?
---@field blacklisted_servers string[]?

---@type InlayHintFillerOpts
local DEFAULT_OPTS = { bufnr = 0, client_id = nil, blacklisted_servers = {} }
---@type InlayHintFillerOpts
local options = vim.tbl_deep_extend("keep", {}, DEFAULT_OPTS)

local blacklisted_client_id = {}

---@param hint_item lsp.InlayHint
---@return string
local function get_inserted_text(hint_item)
  local hint_text
  if type(hint_item.label) == "string" then
    hint_text = hint_item.label
  else
    hint_text = hint_item.label[1].value ---@cast hint_text string
  end
  if hint_item.paddingLeft then
    hint_text = " " .. hint_text
  end
  if hint_item.paddingRight then
    hint_text = hint_text .. " "
  end
  return hint_text
end

---@param hints lsp.InlayHint[]
---@param opts InlayHintFillerOpts
local function process_hints(hints, opts)
  table.sort(hints, function(item1, item2)
    local pos1 = item1.position
    local pos2 = item2.position
    return pos1.line < pos2.line
      or (pos1.line == pos2.line and pos1.character < pos2.character)
  end)

  local current_line = -1
  local line_content = ""
  local offsets = {}

  for i = 1, #hints do
    local hint_item = hints[i]
    local pos = hint_item.position
    if pos.line ~= current_line then
      if current_line >= 0 and #line_content > 0 then
        offsets[current_line] = offsets[current_line] or 0
        vim.schedule(function()
          api.nvim_buf_set_lines(
            opts.bufnr,
            current_line,
            current_line + 1,
            false,
            { line_content }
          )
        end)
      end
      local fresh_lines =
        api.nvim_buf_get_lines(opts.bufnr, pos.line, pos.line + 1, false)
      line_content = fresh_lines[1] or ""
      current_line = pos.line
      offsets[current_line] = offsets[current_line] or 0
    end

    local inserted_text = get_inserted_text(hint_item)
    local insert_pos = pos.character + offsets[current_line]
    line_content = line_content:sub(1, insert_pos)
      .. inserted_text
      .. line_content:sub(insert_pos + 1)
    offsets[current_line] = offsets[current_line] + #inserted_text
  end

  if current_line >= 0 and #line_content > 0 then
    vim.schedule(function()
      api.nvim_buf_set_lines(
        opts.bufnr,
        current_line,
        current_line + 1,
        false,
        { line_content }
      )
    end)
  end
end

local function refresh_clients()
  blacklisted_client_id = {}
  for _, server_name in pairs(options.blacklisted_servers) do
    local clients = vim.lsp.get_clients({ name = server_name })
    for _, client in pairs(clients) do
      vim.list_extend(blacklisted_client_id, { client.id })
    end
  end
end

--- Get the InlayHints the hard way.
--- Avoids incompatibility in case another plugin overrides the inlayhint handler.
---@param bufnr integer
---@param range lsp.Range
---@return lsp.InlayHint[]
local function get_hints(bufnr, range)
  local hints = {} ---@type lsp.InlayHint[]

  ---@type vim.lsp.Client
  local clients
  if DEFAULT_OPTS.client_id ~= nil then
    clients = vim.lsp.get_clients({ client_id = DEFAULT_OPTS.client_id })
  else
    clients = vim.lsp.get_clients({ bufnr = bufnr })
  end

  for _, client in pairs(clients) do
    if
      not vim.list_contains(blacklisted_client_id, client.id)
      and client.server_capabilities.inlayHintProvider
    then
      -- not blacklisted
      local range_params = vim.lsp.util.make_range_params(bufnr, client.offset_encoding)
      range_params.range = range
      local ret, _ = client:request_sync(
        vim.lsp.protocol.Methods.textDocument_inlayHint,
        range_params,
        2 ^ 32 - 1,
        bufnr
      )
      if ret ~= nil then
        local result = ret.result
        if result == {} or result == nil then
          goto continue
        end
        for _, inlay_hint in pairs(result) do
          if
            not vim.list_contains(
              vim.tbl_map(function(v)
                return vim.deep_equal(v.position, inlay_hint.position)
              end, hints),
              true
            )
          then
            table.insert(hints, inlay_hint)
          end
        end
      end
    end
    ::continue::
  end
  return hints
end

---@param opts InlayHintFillerOpts?
M.fill = function(opts)
  refresh_clients()
  ---@type InlayHintFillerOpts
  opts = vim.tbl_deep_extend("keep", {} or opts, options, DEFAULT_OPTS)
  local mode = vim.fn.mode()
  if mode == "n" then
    local cursor_pos = api.nvim_win_get_cursor(0)
    local row = cursor_pos[1] - 1
    local col = cursor_pos[2]
    local hints = get_hints(opts.bufnr, {
      start = { line = row, character = col },
      ["end"] = { line = row, character = col + 1 },
    })
    if hints and #hints > 0 then
      process_hints(hints, opts)
    end
  elseif string.lower(mode):find("^.?v%a?") then
    local start_pos = vim.fn.getpos("v")
    local end_pos = vim.fn.getpos(".")
    if
      start_pos[1] > end_pos[1]
      or (start_pos[1] == end_pos[1] and start_pos[2] > end_pos[2])
    then
      start_pos, end_pos = end_pos, start_pos
    end

    ---@type lsp.Range
    local lsp_range = {
      start = { line = start_pos[2] - 1, character = start_pos[3] - 1 },
      ["end"] = { line = end_pos[2] - 1, character = end_pos[3] - 1 },
    }
    if mode == "V" or mode == "Vs" then
      lsp_range.start.character = 0
      lsp_range["end"].line = lsp_range["end"].line + 1
      lsp_range["end"].character = 0
    end
    local hints = get_hints(opts.bufnr, lsp_range)
    if hints and #hints > 0 then
      process_hints(hints, opts)
    end
  end
  api.nvim_input("<esc>")
end

---@param opts InlayHintFillerOpts
M.setup = function(opts)
  options = vim.tbl_deep_extend("keep", opts or {}, DEFAULT_OPTS)
  refresh_clients()
  api.nvim_create_autocmd("LspAttach", {
    desc = "Refresh in case of LspRestart.",
    callback = refresh_clients,
  })
end

return M
