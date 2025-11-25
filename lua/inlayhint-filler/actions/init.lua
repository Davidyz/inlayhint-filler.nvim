---@type table<InlayHintFiller.Action.Name, InlayHintFiller.Action.Callback>
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
