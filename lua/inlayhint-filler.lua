M = {}

---@class InlayHintFillerOpts
---@field bufnr integer
---@field client_id integer|nil

---@type InlayHintFillerOpts
local DEFAULT_OPTS = { bufnr = 0, client_id = nil }

---@param hint_item lsp.InlayHint
---@return string
local function get_inserted_text(hint_item)
  local hint_text
  if type(hint_item.label) == "string" then
    hint_text = hint_item.label
  else
    hint_text = hint_item.label[1].value
  end
  if hint_item.paddingLeft then
    hint_text = " " .. hint_text
  end
  if hint_item.paddingRight then
    hint_text = hint_text .. " "
  end
  return hint_text
end

---@param hint_item lsp.InlayHint
---@param original_line string
---@return string
local function make_new_line(hint_item, original_line)
  local hint_text = get_inserted_text(hint_item)
  local hint_col = hint_item.position.character
  return original_line:sub(1, hint_col) .. hint_text .. original_line:sub(hint_col + 1)
end

---@param hint_item lsp.InlayHint
---@param opts InlayHintFillerOpts
---@param row integer?
---@param col integer?
local function insert_hint_item(hint_item, opts, row, col)
  local hint_col = hint_item.position.character
  local hint_row = hint_item.position.line
  if
    (row == nil and col == nil) or (hint_row == row and math.abs(hint_col - col) <= 1)
  then
    if #hint_item.label > 1 then
      vim.notify(
        "More than one labels are collected. Defaulting to the first one.",
        vim.log.levels.WARN,
        { title = "InlayHint-Filler" }
      )
    end
    local new_line = make_new_line(
      hint_item,
      vim.api.nvim_buf_get_lines(opts.bufnr, hint_row, hint_row + 1, false)[1]
    )
    vim.api.nvim_buf_set_lines(opts.bufnr, hint_row, hint_row + 1, false, {
      new_line,
    })
  end
end

---@param opts InlayHintFillerOpts?
M.fill = function(opts)
  opts = vim.tbl_deep_extend("keep", opts or {}, DEFAULT_OPTS)
  if vim.fn.mode() == "n" then
    local hints = vim.lsp.inlay_hint.get({ bufnr = opts.bufnr })
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local row = cursor_pos[1] - 1
    local col = cursor_pos[2]
    if hints ~= nil and #hints >= 1 then
      for _, hint_item in pairs(hints) do
        if opts.client_id == nil or opts.client_id == hint_item.client_id then
          insert_hint_item(hint_item.inlay_hint, opts, row, col)
        end
      end
    end
  elseif vim.fn.mode() == "v" then
    local start_pos = vim.fn.getpos("v")
    local end_pos = vim.fn.getpos(".")
    ---@type lsp.Range
    local lsp_range = {
      start = { line = start_pos[2] - 1, character = start_pos[3] - 1 },
      ["end"] = { line = end_pos[2] - 1, character = end_pos[3] - 1 },
    }
    local hints = vim.lsp.inlay_hint.get({ bufnr = opts.bufnr, range = lsp_range })
    if hints ~= nil and #hints >= 1 then
      ---@type table<integer, integer>
      local str_offset = {}
      table.sort(hints, function(item1, item2)
        local pos1 = item1.inlay_hint.position
        local pos2 = item2.inlay_hint.position

        return pos1.line <= pos2.line and pos1.character < pos2.character
      end)
      for _, hint_item in pairs(hints) do
        if opts.client_id == nil or opts.client_id == hint_item.client_id then
          local original_pos = hint_item.inlay_hint.position
          hint_item.inlay_hint.position.character = original_pos.character
            + (str_offset[original_pos.line] or 0)
          insert_hint_item(hint_item.inlay_hint, opts)
          local inserted_size = get_inserted_text(hint_item.inlay_hint):len()
          str_offset[original_pos.line] = (str_offset[original_pos.line] or 0)
            + inserted_size
        end
      end
    end
  end
end

return M
