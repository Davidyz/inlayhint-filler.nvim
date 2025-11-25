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

---@class (private) InlayHintFiller.CursorRange
---@field start [integer, integer]
---@field end [integer, integer]

---@param motion string?
---@param ctx {bufnr: integer}
---@return InlayHintFiller.CursorRange?
local function make_range(motion, ctx)
  local mode = fn.mode()

  --- (1, 0) based index
  ---@type InlayHintFiller.CursorRange?
  local cursor_range

  if mode == "n" then
    local cursor_pos
    if motion == nil or motion == "char" then
      cursor_pos = api.nvim_win_get_cursor(fn.bufwinid(ctx.bufnr))
      local row = cursor_pos[1]
      local col = cursor_pos[2]
      cursor_range = {
        start = { row, col },
        ["end"] = { row, col + 2 },
      }
    else
      error("Unsupported motion: " .. motion)
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
  return cursor_range
end

---@class (private) InlayHintFiller.DoAction.Opts: InlayHintFiller.Opts

---@param action_cb InlayHintFiller.Action.Callback
---@param range_or_motion? InlayHintFiller.CursorRange|string
local _do_action = function(action_cb, range_or_motion)
  vim.validate("action_cb", action_cb, "function", "action_cb should be a function")
  local bufnr = api.nvim_get_current_buf()
  local setup_opts = require("inlayhint-filler.config").get_config()

  local eager = setup_opts.eager
  if type(eager) == "function" then
    eager = eager({ bufnr = bufnr })
    ---@cast eager -function
  end

  ---The range used when filtering the results.
  ---@type InlayHintFiller.CursorRange?
  local strict_range
  if range_or_motion == nil or type(range_or_motion) == "string" then
    strict_range = make_range(range_or_motion, { bufnr = bufnr })
  else
    strict_range = range_or_motion
  end

  if strict_range == nil then
    return
  end

  ---The range used when fetching inlay hints from the server.
  ---@type InlayHintFiller.CursorRange
  local fetch_range
  if eager then
    fetch_range = { start = { 1, 0 }, ["end"] = { api.nvim_buf_line_count(bufnr), 0 } }
  else
    fetch_range = strict_range
  end

  local clients = vim
    .iter(lsp.get_clients({
      bufnr = bufnr,
      method = "textDocument/inlayHint",
    }))
    :filter(function(cli)
      -- exclude blacklisted servers.
      return not vim.list_contains(setup_opts.blacklisted_servers, cli.name)
    end)
    :totable()

  ---@param idx? integer
  ---@param cli vim.lsp.Client
  local function do_action(idx, cli)
    if cli == nil or idx == nil then
      return
    end

    local params = lsp.util.make_given_range_params(
      fetch_range.start,
      fetch_range["end"],
      bufnr,
      cli.offset_encoding
    )

    local checked_range = lsp.util.make_given_range_params(
      strict_range.start,
      strict_range["end"],
      bufnr,
      cli.offset_encoding
    ).range

    local support_resolve = cli:supports_method("inlayHint/resolve", bufnr)
    ---@type InlayHintFiller.Action.Callback.Context
    local action_ctx = { client = cli, bufnr = bufnr }

    cli:request(
      "textDocument/inlayHint",
      params,
      ---@param result lsp.InlayHint[]?
      function(_, result, _, _)
        if result == nil then
          return do_action(next(clients, idx))
        end
        result = vim
          .iter(result)
          :filter(
            ---@param hint lsp.InlayHint
            function(hint)
              return is_lsp_position_in_range(hint.position, checked_range)
            end
          )
          :totable()

        if result == nil or vim.tbl_isempty(result) then
          return do_action(next(clients, idx))
        end
        if support_resolve then
          local finished_count = 0
          for i, hint in pairs(result) do
            cli:request("inlayHint/resolve", hint, function(_, _result, _, _)
              result[i] = vim.tbl_deep_extend("force", hint, _result)
              finished_count = finished_count + 1
              if finished_count == #result then
                if action_cb(result, action_ctx) == 0 then
                  return do_action(next(clients, idx))
                end
              else
                return
              end
            end, bufnr)
          end
        else
          if action_cb(result, action_ctx) == 0 then
            return do_action(next(clients, idx))
          else
            return
          end
        end

        return do_action(next(clients, idx))
      end
    )
  end
  return do_action(next(clients))
end

M.fill = function()
  vim.deprecate(
    "require('inlayhint-filler').fill",
    "require('inlayhint-filler').do_action.textEdits",
    ---@diagnostic disable-next-line: param-type-mismatch
    nil,
    "inlayhint-filler.nvim",
    true
  )
  vim.o.operatorfunc = "v:lua.require'inlayhint-filler'.do_action.textEdits"
  if fn.mode() == "n" then
    -- normal mode
    return api.nvim_input("g@ ")
  end
  return M.do_action["textEdits"]()
end

---@alias InlayHintFiller.DoAction fun(motion: string|InlayHintFiller.CursorRange|nil):any

---@class (private) InlayHintFiller.DoAction.Meta
---@field [InlayHintFiller.Action.Name] InlayHintFiller.DoAction
---@field __call fun(action: InlayHintFiller.Action.Name, motion: string|InlayHintFillter.CursorRange|nil)

local _do_actions = {}

---@type table<InlayHintFiller.Action.Name, InlayHintFiller.DoAction>|fun(action: InlayHintFiller.Action.Name, motion: string|InlayHintFiller.CursorRange|nil)
M.do_action = setmetatable(_do_actions, {
  __index = function(_, action_name)
    local action_cb = actions[action_name]
    assert(type(action_cb) == "function", "unsupported action: " .. action_name)

    ---@type InlayHintFiller.DoAction
    local action = function(motion)
      -- TODO: dot-repeat/textobject support
      return _do_action(action_cb, motion)
    end

    _do_actions[action_name] = action
    return action
  end,
  ---@param action InlayHintFiller.Action.Name|InlayHintFiller.Action.Callback
  __call = function(_, action)
    local action_cb = action
    if type(action) == "string" then
      action_cb = actions[action]
    end

    assert(type(action_cb) == "function", "unsupported action: " .. vim.inspect(action))

    return _do_action(action_cb)
  end,
})

---@param opts InlayHintFiller.Opts?
M.setup = function(opts)
  require("inlayhint-filler.config").setup(opts or {})
end

return M
