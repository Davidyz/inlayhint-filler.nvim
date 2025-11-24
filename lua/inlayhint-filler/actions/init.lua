---@type table<InlayHintFiller.Action, InlayHintFiller.Callback>
local actions = setmetatable({}, {
  __index = function(_, action_name)
    local ok, ret = pcall(require, "inlayhint-filler.actions." .. action_name)
    if ok then
      return ret
    else
      error("Unsupported action: " .. action_name)
    end
  end,
})

return actions
