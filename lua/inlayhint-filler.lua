local M = {}

local notify = vim.schedule_wrap(vim.notify)
local api = vim.api

---@class InlayHintFillerOpts
---@field blacklisted_servers string[]

---@type InlayHintFillerOpts
local DEFAULT_OPTS = { blacklisted_servers = {} }

---@type InlayHintFillerOpts
local options = vim.deepcopy(DEFAULT_OPTS)

---@param hint lsp.InlayHint
---@return lsp.TextEdit[]
local function get_text_edits(hint)
  if hint.textEdits then
    return hint.textEdits
  end

  notify(
    "Failed to extract text edits from LSP.",
    vim.log.levels.WARN,
    { title = "Inlayhint-Filler" }
  )

  local label = hint.label
  if type(label) == "table" and not vim.tbl_isempty(label) then
    label = label[1].value
  end
  return {
    ---@type lsp.TextEdit
    {
      range = { start = hint.position, ["end"] = hint.position },
      newText = string.format(
        "%s%s%s",
        hint.paddingLeft and " " or "",
        label,
        hint.paddingRight and " " or ""
      ),
    },
  }
end

---@param pos lsp.Position
---@param range lsp.Range
---@return boolean
local function is_lsp_position_in_range(pos, range)
  if pos.line < range.start.line or pos.line > range["end"].line then
    return false
  elseif pos.line == range.start.line and pos.character < range.start.character then
    return false
  elseif
    pos.line == range["end"].line
    and (pos.character >= range["end"].character or pos.character == -1)
  then
    -- `end` is exclusive
    return false
  else
    return true
  end
end

---@param action? string operatorfunc argument. Reserved for future use.
---@param opts? InlayHintFillerOpts
M._fill = function(action, opts)
  local bufnr = vim.api.nvim_get_current_buf()
  ---@type InlayHintFillerOpts
  opts = vim.tbl_deep_extend("force", options, {} or opts)
  local mode = vim.fn.mode()
  ---@type lsp.Range?
  local lsp_range

  if mode == "n" then
    local cursor_pos = api.nvim_win_get_cursor(0)
    local row = cursor_pos[1] - 1
    local col = cursor_pos[2]
    lsp_range = {
      start = { line = row, character = col },
      ["end"] = { line = row, character = col + 2 },
    }
  elseif string.lower(mode):find("^.?v%a?") then
    local start_pos = vim.fn.getpos("v")
    local end_pos = vim.fn.getpos(".")
    if
      start_pos[1] > end_pos[1]
      or (start_pos[1] == end_pos[1] and start_pos[2] > end_pos[2])
    then
      start_pos, end_pos = end_pos, start_pos
    end

    lsp_range = {
      start = { line = start_pos[2] - 1, character = start_pos[3] - 1 },
      ["end"] = { line = end_pos[2] - 1, character = end_pos[3] - 1 },
    }
    if mode == "V" or mode == "Vs" then
      lsp_range.start.character = 0
      lsp_range["end"].line = lsp_range["end"].line + 1
      lsp_range["end"].character = 0
    end
  end

  if lsp_range == nil then
    return
  end

  local clients = vim
    .iter(vim.lsp.get_clients({
      bufnr = bufnr,
      method = vim.lsp.protocol.Methods.textDocument_inlayHint,
    }))
    :filter(function(cli)
      -- exclude blacklisted servers.
      return not vim.list_contains(opts.blacklisted_servers, cli.name)
    end)
    :totable()

  ---@param idx? integer
  ---@param cli vim.lsp.Client
  local function do_insert(idx, cli)
    if cli == nil or idx == nil then
      return
    end
    local params = vim.lsp.util.make_range_params(0, cli.offset_encoding)
    params.range = lsp_range
    cli:request(
      vim.lsp.protocol.Methods.textDocument_inlayHint,
      params,
      function(_, result, context, _)
        ---@type lsp.InlayHint[]
        result = vim
          .iter(result or {})
          :filter(
            ---@param hint lsp.InlayHint
            function(hint)
              return is_lsp_position_in_range(hint.position, lsp_range)
            end
          )
          :totable()
        if result == nil or vim.tbl_isempty(result) then
          return do_insert(next(clients, idx))
        end

        vim.schedule_wrap(vim.lsp.util.apply_text_edits)(
          vim.iter(result):map(get_text_edits):flatten(1):totable(),
          context.bufnr,
          cli.offset_encoding
        )
        return do_insert(next(clients, idx))
      end
    )
  end
  return do_insert(next(clients))
end

---@param opts InlayHintFillerOpts?
M.fill = function(opts)
  vim.o.operatorfunc = "v:lua.require'inlayhint-filler'._fill"
  if vim.fn.mode() == "n" then
    -- normal mode
    return api.nvim_input("g@ ")
  end
  return M._fill(nil, opts)
end

---@param opts InlayHintFillerOpts
M.setup = function(opts)
  options = vim.tbl_deep_extend("keep", opts or {}, DEFAULT_OPTS)
end

return M
