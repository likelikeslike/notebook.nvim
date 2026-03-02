---@mod notebook.cells Cell Management
---@brief [[
--- Manages notebook cells: tracking, navigation, creation, deletion, merging.
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
---@field source string? Cell content (only accessible via M.get_current)

local M = {}

local ipynb = require("notebook.ipynb")
local utils = require("notebook.utils")

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

--- Get the cell at cursor position, with source content populated
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
--- @return CellInfo? cell Cell at cursor, or nil if cursor not in a cell
--- @return number? 1-indexed position in the cells array (only when with_index is true)
function M.get_current(buf, ns)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1

    local cells = M.get_all(buf, ns)
    for i, cell in ipairs(cells) do
        if row >= cell.start_row and row <= cell.end_row then
            local lines = vim.api.nvim_buf_get_lines(buf, cell.start_row + 1, cell.end_row + 1, false)
            cell.source = table.concat(lines, "\n")
            return cell, i
        end
    end

    return nil, nil
end


--- Move cursor to next cell (first content line)
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.goto_next(buf, ns)
    local current, idx = M.get_current(buf, ns)
    if not current then return end

    local all_cells = M.get_all(buf, ns)
    local next_cell = all_cells[idx + 1]
    if next_cell then
        local target_row = math.min(next_cell.start_row + 1, next_cell.end_row)
        vim.api.nvim_win_set_cursor(0, { target_row + 1, 0 })
    end
end

--- Move cursor to previous cell (first content line)
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.goto_prev(buf, ns)
    local current, idx = M.get_current(buf, ns)
    if not current or idx <= 1 then return end

    local all_cells = M.get_all(buf, ns)
    local prev_cell = all_cells[idx - 1]
    local target_row = math.min(prev_cell.start_row + 1, prev_cell.end_row)
    vim.api.nvim_win_set_cursor(0, { target_row + 1, 0 })
end

--- Rebuild cell extmarks from buffer text
--- Called on TextChanged/TextChangedI to keep extmarks in sync with edits.
--- Clears all namespaces and re-scans for "# %%" separators.
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.refresh_cells(buf, ns)
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    local decor_ns = vim.api.nvim_create_namespace("jupyter_notebook_decor")
    vim.api.nvim_buf_clear_namespace(buf, decor_ns, 0, -1)
    local output_ns = vim.api.nvim_create_namespace("jupyter_notebook_output")
    vim.api.nvim_buf_clear_namespace(buf, output_ns, 0, -1)

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local cell_ranges = {}
    local current_start = nil
    local current_type = "code"
    local current_id = nil

    for i, line in ipairs(lines) do
        local row = i - 1
        if line:match("^# %%") then
            if current_start ~= nil then
                table.insert(cell_ranges, {
                    start_row = current_start,
                    end_row = row - 1,
                    cell_type = current_type,
                    cell_index = #cell_ranges + 1,
                    cell_id = current_id,
                })
            end
            current_start = row
            current_type, current_id = utils.parse_separator(line)
        end
    end

    if current_start ~= nil then
        table.insert(cell_ranges, {
            start_row = current_start,
            end_row = #lines - 1,
            cell_type = current_type,
            cell_index = #cell_ranges + 1,
            cell_id = current_id,
        })
    end

    local cell_data = {}
    for _, range in ipairs(cell_ranges) do
        -- end_col=0 makes the extmark span through end_row (inclusive)
        local mark_id = vim.api.nvim_buf_set_extmark(buf, ns, range.start_row, 0, {
            end_row = range.end_row,
            end_col = 0,
        })
        cell_data[mark_id] = {
            cell_type = range.cell_type,
            cell_index = range.cell_index,
            cell_id = range.cell_id,
        }
    end

    vim.b[buf].notebook_cells = cell_data

    local render = require("notebook.render")
    render.apply_decorations(buf, decor_ns, cell_ranges)

    render.render_outputs(buf, ns)
end

--- Insert a new code cell below current cell
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.add_below(buf, ns)
    local current = M.get_current(buf, ns)
    local insert_row

    if current then
        insert_row = current.end_row + 1
    else
        insert_row = vim.api.nvim_buf_line_count(buf)
    end

    local cell_id = utils.generate_cell_id()
    local separator = utils.build_separator("code", cell_id)
    local new_lines = { separator, "" }
    vim.api.nvim_buf_set_lines(buf, insert_row, insert_row, false, new_lines)

    M.refresh_cells(buf, ns)
    vim.api.nvim_win_set_cursor(0, { insert_row + 2, 0 })

    vim.bo[buf].modified = true
end

--- Insert a new code cell above current cell
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.add_above(buf, ns)
    local current = M.get_current(buf, ns)
    local insert_row

    if current then
        insert_row = current.start_row
    else
        insert_row = 0
    end

    local cell_id = utils.generate_cell_id()
    local separator = utils.build_separator("code", cell_id)
    local new_lines = { separator, "" }
    vim.api.nvim_buf_set_lines(buf, insert_row, insert_row, false, new_lines)

    M.refresh_cells(buf, ns)
    vim.api.nvim_win_set_cursor(0, { insert_row + 2, 0 })

    vim.bo[buf].modified = true
end

--- Delete the cell at cursor
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.delete_current(buf, ns)
    local current = M.get_current(buf, ns)
    if not current then
        vim.notify("No cell at cursor", vim.log.levels.WARN)
        return
    end

    local all_cells = M.get_all(buf, ns)
    if #all_cells <= 1 then
        vim.notify("Cannot delete the last cell", vim.log.levels.WARN)
        return
    end

    local start_row = current.start_row
    local end_row = current.end_row

    vim.api.nvim_buf_set_lines(buf, start_row, end_row + 1, false, {})

    M.refresh_cells(buf, ns)
    vim.bo[buf].modified = true
end

--- Toggle cell type between code and markdown
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.toggle_type(buf, ns)
    local current = M.get_current(buf, ns)
    if not current then
        vim.notify("No cell at cursor", vim.log.levels.WARN)
        return
    end

    local new_type = current.cell_type == "code" and "markdown" or "code"
    local new_line = utils.build_separator(new_type, current.cell_id)

    vim.api.nvim_buf_set_lines(buf, current.start_row, current.start_row + 1, false, { new_line })
    M.refresh_cells(buf, ns)
    vim.bo[buf].modified = true
end

--- Merge current cell with the cell below (remove separator between them)
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.merge_below(buf, ns)
    local current, idx = M.get_current(buf, ns)
    if not current then return end

    local all_cells = M.get_all(buf, ns)
    local next_cell = all_cells[idx + 1]
    if not next_cell then
        vim.notify("No cell below to merge", vim.log.levels.WARN)
        return
    end

    vim.api.nvim_buf_set_lines(buf, next_cell.start_row, next_cell.start_row + 1, false, {})

    M.refresh_cells(buf, ns)
    vim.bo[buf].modified = true
end

--- Merge current cell with the cell above (remove current cell's separator)
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.merge_above(buf, ns)
    local current, idx = M.get_current(buf, ns)
    if not current then return end

    if idx <= 1 then
        vim.notify("No cell above to merge", vim.log.levels.WARN)
        return
    end

    vim.api.nvim_buf_set_lines(buf, current.start_row, current.start_row + 1, false, {})

    M.refresh_cells(buf, ns)
    vim.bo[buf].modified = true
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

--- Get line ranges for all markdown cells in the buffer
--- Used by diagnostic handlers to filter out diagnostics in markdown regions
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
--- @return table[] ranges Array of {start_row, end_row} pairs
function M.get_markdown_ranges(buf, ns)
    local all_cells = M.get_all(buf, ns)
    local ranges = {}
    for _, cell in ipairs(all_cells) do
        if cell.cell_type == "markdown" then
            table.insert(ranges, { cell.start_row, cell.end_row })
        end
    end
    return ranges
end

--- Check if a line number falls within any markdown cell
--- @param lnum number 0-indexed line number
--- @param markdown_ranges table[] Ranges from get_markdown_ranges()
--- @return boolean
function M.is_in_markdown(lnum, markdown_ranges)
    for _, range in ipairs(markdown_ranges) do
        if lnum >= range[1] and lnum <= range[2] then
            return true
        end
    end
    return false
end

--- Filter diagnostics to exclude those in markdown cells
--- @param diagnostics vim.Diagnostic[] Raw diagnostics
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
--- @return vim.Diagnostic[] filtered Filtered diagnostics
function M.filter_markdown_diagnostics(diagnostics, buf, ns)
    local markdown_ranges = M.get_markdown_ranges(buf, ns)
    if #markdown_ranges == 0 then return diagnostics end

    local filtered = {}
    for _, diag in ipairs(diagnostics) do
        if not M.is_in_markdown(diag.lnum, markdown_ranges) then
            table.insert(filtered, diag)
        end
    end
    return filtered
end

return M
