---@mod notebook.cells Cell Management
---@brief [[
--- Manages notebook cells
---
--- Cell tracking uses extmarks to maintain cell boundaries as buffer changes.
--- Each cell has an extmark spanning from separator line to last content line.
---
--- Cell metadata stored in vim.b[buf].notebook_cells[extmark_id]:
---   { cell_type, cell_index, cell_id }
---@brief ]]

---@class CellInfo
---@field id number Extmark ID
---@field start_row number 0-indexed start row (separator line)
---@field end_row number 0-indexed end row (last content line)
---@field cell_type string "code" or "markdown"
---@field cell_index number 1-indexed position in notebook
---@field cell_id string? Unique cell identifier

local M = {}

local ipynb = require("notebook.ipynb")

--- Get all cells in the buffer
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
--- @return CellInfo[] cells List of cells sorted by start_row
function M.get_all(buf, ns)
    local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    local cells = {}

    for _, mark in ipairs(extmarks) do
        local id, start_row, _, details = mark[1], mark[2], mark[3], mark[4]
        local end_row = details.end_row or start_row

        local cell_data = vim.b[buf].notebook_cells and vim.b[buf].notebook_cells[id]
        if cell_data then
            table.insert(cells, {
                id = id,
                start_row = start_row,
                end_row = end_row,
                cell_type = cell_data.cell_type,
                cell_index = cell_data.cell_index,
                cell_id = cell_data.cell_id,
            })
        end
    end

    table.sort(cells, function(a, b)
        return a.start_row < b.start_row
    end)

    return cells
end

--- Sync buffer text back to notebook.cells for saving
--- Reads current buffer content and reconstructs notebook.cells array.
--- Preserves outputs from vim.b[buf].cell_outputs.
--- @param buf number Buffer handle
--- @param notebook table Notebook data structure
--- @param ns number Namespace for extmarks
--- @return table notebook Updated notebook with synced cells
function M.update_from_buffer(buf, notebook, ns)
    local cells = M.get_all(buf, ns)
    local cell_outputs = vim.b[buf].cell_outputs or {}
    local new_cells = {}

    local orig_by_id = {}
    for _, orig in ipairs(notebook.cells or {}) do
        local id = orig.metadata and orig.metadata.id
        if id then orig_by_id[id] = orig end
    end

    for i, cell in ipairs(cells) do
        local lines = vim.api.nvim_buf_get_lines(buf, cell.start_row + 1, cell.end_row + 1, false)

        -- Match by cell_id first; fall back to positional index for notebooks without IDs
        local orig = (cell.cell_id and orig_by_id[cell.cell_id])
            or (notebook.cells and notebook.cells[i])
        local metadata = orig and orig.metadata or {}

        local new_cell = {
            cell_type = cell.cell_type,
            metadata = metadata,
            source = ipynb.lines_to_source(lines),
        }

        if cell.cell_type == "code" then
            local output_data = cell.cell_id and cell_outputs[cell.cell_id]
            if output_data then
                new_cell.execution_count = output_data.execution_count
                new_cell.outputs = output_data.outputs or {}
            else
                new_cell.outputs = {}
            end
        end

        table.insert(new_cells, new_cell)
    end

    notebook.cells = new_cells
    return notebook
end

return M
