local M = {}

local api = vim.api
local lsp = vim.lsp
local fn = vim.fn
local actions = require("inlayhint-filler.actions")

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

---@param motion string?
---@param ctx {bufnr: integer}
---@return {["start"]: [integer, integer], ["end"]: [integer, integer]}?
local function make_range(motion, ctx)
  local mode = fn.mode()

  --- (1, 0) based index
  ---@type {["start"]: [integer, integer], ["end"]: [integer, integer]}?
  local cursor_range

  if mode == "n" then
    local cursor_pos = api.nvim_win_get_cursor(fn.bufwinid(ctx.bufnr))
    local row = cursor_pos[1]
    local col = cursor_pos[2]
    cursor_range = {
      start = { row, col },
      ["end"] = { row, col + 2 },
    }
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

  local eager = require("inlayhint-filler.config").get_config().eager
  if type(eager) == "function" then
    eager = eager({ bufnr = api.nvim_get_current_buf() })
    ---@cast eager -function
  end

  if eager then
    local buf_line_count = api.nvim_buf_line_count(ctx.bufnr)

    cursor_range = {
      start = { 1, 0 },
      ["end"] = { buf_line_count, 0 },
    }
  end
  if cursor_range == nil then
    return
  end
  return cursor_range
end

---@param motion? string operatorfunc argument. Reserved for future use.
---@param opts? InlayHintFiller.Opts
M._fill = function(motion, opts)
  local bufnr = api.nvim_get_current_buf()
  ---@type InlayHintFiller.Opts
  opts = vim.tbl_deep_extend(
    "force",
    require("inlayhint-filler.config").get_config(),
    {} or opts
  )

  local cursor_range = make_range(motion, { bufnr = bufnr })

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

  ---@param idx? integer
  ---@param cli vim.lsp.Client
  local function do_action(idx, cli)
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
    ---@type InlayHintFiller.Callback.Context
    local action_ctx = { client = cli, bufnr = bufnr }

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
          return do_action(next(clients, idx))
        end
        if not support_resolve then
          if actions.textEdits(result, action_ctx) == 0 then
            return do_action(next(clients, idx))
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
                  if actions.textEdits(result, action_ctx) == 0 then
                    return do_action(next(clients, idx))
                  end
                else
                  return
                end
              end, bufnr)
            else
              finished_count = finished_count + 1
              if finished_count == #result then
                if actions.textEdits(result, action_ctx) == 0 then
                  return do_action(next(clients, idx))
                else
                  return
                end
              end
            end
          end
        end

        return do_action(next(clients, idx))
      end
    )
  end
  return do_action(next(clients))
end

---@param opts InlayHintFiller.Opts?
M.fill = function(opts)
  vim.o.operatorfunc = "v:lua.require'inlayhint-filler'._fill"
  if fn.mode() == "n" then
    -- normal mode
    return api.nvim_input("g@ ")
  end
  return M._fill(nil, opts)
end

---@param action InlayHintFiller.Action|InlayHintFiller.Callback
M.do_action = function(action) end

---@param opts InlayHintFiller.Opts?
M.setup = function(opts)
  require("inlayhint-filler.config").setup(opts or {})
end

return M
