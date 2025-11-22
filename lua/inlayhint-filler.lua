local M = {}

local notify = vim.schedule_wrap(vim.notify)
local notify_opts = { title = "Inlayhint-Filler" }
local api = vim.api
local lsp = vim.lsp
local fn = vim.fn
local lsp_apply_text_edits = vim.schedule_wrap(lsp.util.apply_text_edits)

---@class InlayHintFillerOpts
---@field blacklisted_servers? string[]
---Whether to build the `textEdits` from the label when the LSP reply doesn't contain textEdits.
---
---Can be a function that returns a boolean.
---@field force? boolean|fun(ctx:{bufnr: integer, hint:lsp.InlayHint}):boolean
---Whether to request for all inlay hints from LSP.
---@field eager? boolean|fun(ctx:{bufnr:integer}):boolean
---@field verbose? boolean

---@type InlayHintFillerOpts
local DEFAULT_OPTS =
  { blacklisted_servers = {}, force = false, eager = false, verbose = false }

---@type InlayHintFillerOpts
local options = vim.deepcopy(DEFAULT_OPTS)

---@param hint lsp.InlayHint
---@param bufnr integer
---@return lsp.TextEdit[]
local function get_text_edits(hint, bufnr)
  if hint.textEdits then
    return hint.textEdits
  end

  local force = options.force
  if type(force) == "function" then
    force = force({ bufnr = bufnr, hint = hint })
  end

  local log_level = vim.log.levels.ERROR
  if force then
    log_level = vim.log.levels.WARN
  end

  notify(
    "Failed to extract text edits from the provided inlayhint"
      .. (
        options.verbose and string.format(":\n```lua\n%s```", vim.inspect(hint))
        or "."
      ),
    log_level,
    notify_opts
  )

  if force then
    local label = hint.label
    if type(label) == "table" and not vim.tbl_isempty(label) then
      label = table.concat(
        vim
          .iter(label)
          :map(function(item)
            return item.value or ""
          end)
          :totable(),
        ""
      )
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
  else
    return {}
  end
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
  local bufnr = api.nvim_get_current_buf()
  ---@type InlayHintFillerOpts
  opts = vim.tbl_deep_extend("force", options, {} or opts)
  local mode = fn.mode()

  --- (1, 0) based index
  ---@type {["start"]: [integer, integer], ["end"]: [integer, integer]}?
  local cursor_range

  if mode == "n" then
    if action == "line" then
      cursor_range = {
        start = api.nvim_buf_get_mark(bufnr, "["),
        ["end"] = api.nvim_buf_get_mark(bufnr, "]"),
      }
    else
      local cursor_pos = api.nvim_win_get_cursor(fn.bufwinid(bufnr))
      local row = cursor_pos[1]
      local col = cursor_pos[2]
      cursor_range = {
        start = { row, col },
        ["end"] = { row, col + 2 },
      }
    end
  elseif string.lower(mode):find("^.?v%a?") then
    local start_pos = fn.getpos("v")
    local end_pos = fn.getpos(".")
    if
      start_pos[1] > end_pos[1]
      or (start_pos[1] == end_pos[1] and start_pos[2] > end_pos[2])
    then
      start_pos, end_pos = end_pos, start_pos
    end

    cursor_range = {
      start = { start_pos[2], start_pos[3] - 1 },
      ["end"] = { end_pos[2], end_pos[3] - 1 },
    }
    if mode == "V" or mode == "Vs" then
      cursor_range.start[2] = 0
      cursor_range["end"][1] = cursor_range["end"][1] + 1
      cursor_range["end"][2] = 0
    end
  end

  if cursor_range == nil then
    return
  end

  local clients = vim
    .iter(lsp.get_clients({
      bufnr = bufnr,
      method = "textDocument/inlayHint",
    }))
    :filter(function(cli)
      -- exclude blacklisted servers.
      return not vim.list_contains(opts.blacklisted_servers, cli.name)
    end)
    :totable()

  local eager = options.eager
  if type(eager) == "function" then
    eager = eager({ bufnr = api.nvim_get_current_buf() })
    ---@cast eager -function
  end

  if eager then
    local buf_line_count = api.nvim_buf_line_count(bufnr)

    cursor_range = {
      start = { 1, 0 },
      ["end"] = { buf_line_count, 0 },
    }
  end

  ---@param client vim.lsp.Client
  ---@param hints lsp.InlayHint[]
  ---@return integer
  local function apply_edits(client, hints)
    local edits = vim
      .iter(hints)
      :map(function(item)
        return get_text_edits(item, bufnr)
      end)
      :flatten(1)
      :totable()

    lsp_apply_text_edits(edits, bufnr, client.offset_encoding)
    return #edits
  end

  ---@param idx? integer
  ---@param cli vim.lsp.Client
  local function do_insert(idx, cli)
    if cli == nil or idx == nil then
      return
    end

    local params = lsp.util.make_given_range_params(
      cursor_range.start,
      cursor_range["end"],
      bufnr,
      cli.offset_encoding or "utf-16"
    )

    local support_resolve = cli:supports_method("inlayHint/resolve", bufnr)

    cli:request(
      "textDocument/inlayHint",
      params,
      ---@param result lsp.InlayHint[]?
      function(_, result, _, _)
        result = vim
          .iter(result or {})
          :filter(
            ---@param hint lsp.InlayHint
            function(hint)
              return is_lsp_position_in_range(hint.position, params.range)
            end
          )
          :totable()

        if result == nil or vim.tbl_isempty(result) then
          return do_insert(next(clients, idx))
        end
        if not support_resolve then
          if apply_edits(cli, result) == 0 then
            return do_insert(next(clients, idx))
          else
            return
          end
        else
          local finished_count = 0
          for i, hint in pairs(result) do
            if hint.textEdits == nil or vim.tbl_isempty(hint.textEdits) then
              cli:request("inlayHint/resolve", hint, function(_, _result, _, _)
                result[i] = vim.tbl_deep_extend("force", hint, _result)
                finished_count = finished_count + 1
                if finished_count == #result then
                  if apply_edits(cli, result) == 0 then
                    return do_insert(next(clients, idx))
                  end
                else
                  return
                end
              end, bufnr)
            else
              finished_count = finished_count + 1
              if finished_count == #result then
                if apply_edits(cli, result) == 0 then
                  return do_insert(next(clients, idx))
                else
                  return
                end
              end
            end
          end
        end

        return do_insert(next(clients, idx))
      end
    )
  end
  return do_insert(next(clients))
end

---@class InlayHintFillerFillOpts: InlayHintFillerOpts
---@field textobject? boolean

---@param opts InlayHintFillerFillOpts?
M.fill = function(opts)
  vim.o.operatorfunc = "v:lua.require'inlayhint-filler'._fill"
  if fn.mode() == "n" then
    -- normal mode
    return api.nvim_input("g@" .. ((opts or {}).textobject and "" or " "))
  end
  return M._fill(nil, opts)
end

---@param opts InlayHintFillerOpts
M.setup = function(opts)
  options = vim.tbl_deep_extend("keep", opts or {}, DEFAULT_OPTS)
end

return M
