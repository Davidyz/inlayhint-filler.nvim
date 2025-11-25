---@meta

---@class InlayHintFiller.Opts
---@field blacklisted_servers? string[]
---Whether to build the `textEdits` from the label when the LSP reply doesn't contain textEdits.
---
---Can be a function that returns a boolean.
---@field force? boolean|fun(ctx:{bufnr: integer, hint:lsp.InlayHint}):boolean
---Whether to request for all inlay hints from LSP.
---@field eager? boolean|fun(ctx:{bufnr:integer}):boolean
---@field verbose? boolean

---@alias InlayHintFiller.Action.Name
--- | "textEdits"
--- | "tooltip"
--- | "location"
--- | "command"

---@class (private) InlayHintFiller.Action.Callback.Context
---@field bufnr integer
---@field client vim.lsp.Client

---@alias InlayHintFiller.Action.Callback fun(hints: lsp.InlayHint[], ctx: InlayHintFiller.Action.Callback.Context):integer
