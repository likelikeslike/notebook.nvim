---@mod notebook.actions User Action Handlers
---@brief [[
--- Handles all user-facing actions for notebook interaction.
---@brief ]]

local cells = require("notebook.cells")

local M = {}

--- Navigate to next cell
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.next_cell(buf, ns)
    cells.goto_next(buf, ns)
end

--- Navigate to previous cell
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.prev_cell(buf, ns)
    cells.goto_prev(buf, ns)
end

--- Add new code cell below current
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.add_cell_below(buf, ns)
    cells.add_below(buf, ns)
end

--- Add new code cell above current
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.add_cell_above(buf, ns)
    cells.add_above(buf, ns)
end

--- Delete current cell
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.delete_cell(buf, ns)
    cells.delete_current(buf, ns)
end

--- Toggle cell type between code and markdown
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.toggle_cell_type(buf, ns)
    cells.toggle_type(buf, ns)
end

--- Merge current cell with cell below
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.merge_cell_below(buf, ns)
    cells.merge_below(buf, ns)
end

--- Merge current cell with cell above
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.merge_cell_above(buf, ns)
    cells.merge_above(buf, ns)
end

return M
