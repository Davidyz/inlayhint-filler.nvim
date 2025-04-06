M = {}

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
local function insert_hint_item(hint_item, opts)
  local hint_row = hint_item.position.line

  if type(hint_item.label) == "table" and #hint_item.label > 1 then
    vim.notify(
      ("More than one labels are collected. Defaulting to the first one.\nDetails: %s"):format(
        vim.inspect(hint_item.label)
      ),
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

---@param opts InlayHintFillerOpts?
M.fill = function(opts)
  ---@type InlayHintFillerOpts
  opts = vim.tbl_deep_extend("keep", {} or opts, options, DEFAULT_OPTS)
  if vim.fn.mode() == "n" then
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local row = cursor_pos[1] - 1
    local col = cursor_pos[2]
    local hints = vim.lsp.inlay_hint.get({
      bufnr = opts.bufnr,
      range = {
        start = { line = row, character = col },
        ["end"] = {
          line = row,
          character = col + 1,
        },
      },
    })
    if hints ~= nil and #hints >= 1 then
      for _, hint_item in pairs(hints) do
        if
          (opts.client_id == nil or opts.client_id == hint_item.client_id)
          and not vim.list_contains(blacklisted_client_id, hint_item.client_id)
        then
          insert_hint_item(hint_item.inlay_hint, opts)
        end
      end
    end
  elseif string.lower(vim.fn.mode()):find("^.?v%a?") then
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
    if vim.fn.mode() == "V" or vim.fn.mode() == "Vs" then
      -- visual line selection
      lsp_range.start.character = 0
      lsp_range["end"].line = lsp_range["end"].line + 1
      lsp_range["end"].character = 0
    end
    local hints = vim.lsp.inlay_hint.get({ bufnr = opts.bufnr, range = lsp_range })
    if hints ~= nil and #hints >= 1 then
      -- Sort hints by position
      table.sort(hints, function(item1, item2)
        local pos1 = item1.inlay_hint.position
        local pos2 = item2.inlay_hint.position
        return pos1.line < pos2.line
          or (pos1.line == pos2.line and pos1.character < pos2.character)
      end)

      -- Process hints line by line
      local current_line = -1
      local line_content = ""
      local offsets = {}

      for i = 1, #hints do
        local hint_item = hints[i]
        if
          (opts.client_id == nil or opts.client_id == hint_item.client_id)
          and not vim.list_contains(blacklisted_client_id, hint_item.client_id)
        then
          local pos = hint_item.inlay_hint.position
          if pos.line ~= current_line then
            -- Apply previous line changes if any
            if current_line >= 0 and #line_content > 0 then
              offsets[current_line] = offsets[current_line] or 0
              vim.api.nvim_buf_set_lines(
                opts.bufnr,
                current_line,
                current_line + 1,
                false,
                { line_content }
              )
            end
            -- Get fresh line content for new line
            local fresh_lines =
              vim.api.nvim_buf_get_lines(opts.bufnr, pos.line, pos.line + 1, false)
            line_content = fresh_lines[1] or ""
            current_line = pos.line
            offsets[current_line] = offsets[current_line] or 0
          end

          local inserted_text = get_inserted_text(hint_item.inlay_hint)
          local insert_pos = pos.character + offsets[current_line]
          line_content = line_content:sub(1, insert_pos)
            .. inserted_text
            .. line_content:sub(insert_pos + 1)
          offsets[current_line] = offsets[current_line] + #inserted_text
        end
      end

      -- Apply final line changes
      if current_line >= 0 and #line_content > 0 then
        vim.api.nvim_buf_set_lines(
          opts.bufnr,
          current_line,
          current_line + 1,
          false,
          { line_content }
        )
      end
    end
  end
end

local function refresh_clients()
  -- collect the client IDs of language servers that should be blacklisted.
  blacklisted_client_id = {}
  for _, server_name in pairs(options.blacklisted_servers) do
    local clients = vim.lsp.get_clients({ name = server_name })
    for _, client in pairs(clients) do
      vim.list_extend(blacklisted_client_id, { client.id })
    end
  end
end

---@param opts  InlayHintFillerOpts
M.setup = function(opts)
  options = vim.tbl_deep_extend("keep", opts or {}, DEFAULT_OPTS)
  refresh_clients()
  vim.api.nvim_create_autocmd("LspAttach", {
    desc = "Refresh in case of LspRestart.",
    callback = refresh_clients,
  })
end
return M
