---@mod notebook.render Initial Notebook Rendering
---@brief [[
--- Converts notebook data structure to buffer text on load.
---@brief ]]

local M = {}

local ipynb = require("notebook.ipynb")
local utils = require("notebook.utils")

--- Render notebook data to buffer (called on BufReadCmd)
--- Main entry point for initial display of .ipynb file.
--- @param buf number Buffer handle
--- @param notebook table Parsed notebook data from ipynb.load()
--- @param ns number Namespace for cell extmarks
function M.notebook(buf, notebook, ns)
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    vim.bo[buf].modifiable = true

    local lines = {}
    local cell_ranges = {}
    local cell_outputs = {}

    for i, cell in ipairs(notebook.cells) do
        local cell_id = cell._id or utils.generate_cell_id()
        cell._id = cell_id

        if cell.execution_count == vim.NIL then
            cell.execution_count = nil
        end

        local separator = utils.build_separator(cell.cell_type, cell_id)
        local cell_start = #lines

        table.insert(lines, separator)

        local source_lines = ipynb.source_to_lines(cell.source)
        for _, line in ipairs(source_lines) do
            table.insert(lines, line)
        end

        if cell.outputs and #cell.outputs > 0 then
            cell_outputs[cell_id] = {
                outputs = cell.outputs,
                execution_count = cell.execution_count,
            }
        end

        table.insert(cell_ranges, {
            start_row = cell_start,
            end_row = #lines - 1,
            cell_type = cell.cell_type,
            cell_index = i,
            cell_id = cell_id,
            execution_count = cell.execution_count,
        })
    end

    if #lines == 0 then
        local cell_id = utils.generate_cell_id()
        lines = { utils.build_separator("code", cell_id), "" }
        table.insert(cell_ranges, {
            start_row = 0,
            end_row = 1,
            cell_type = "code",
            cell_index = 1,
            cell_id = cell_id,
        })
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    local cell_data = {}
    for _, range in ipairs(cell_ranges) do
        local mark_id = vim.api.nvim_buf_set_extmark(buf, ns, range.start_row, 0, {
            end_row = range.end_row,
            end_col = 0,
        })

        cell_data[mark_id] = {
            cell_type = range.cell_type,
            cell_index = range.cell_index,
            cell_id = range.cell_id,
            execution_count = range.execution_count,
        }
    end

    vim.b[buf].notebook_cells = cell_data
    vim.b[buf].cell_outputs = cell_outputs

    local decor_ns = vim.api.nvim_create_namespace("jupyter_notebook_decor")
    M.apply_decorations(buf, decor_ns, cell_ranges)
end

--- Apply visual decorations to cells
--- @param buf number Buffer handle
--- @param ns number Namespace for decoration extmarks
--- @param cell_ranges table[] Cell range info from notebook()
function M.apply_decorations(buf, ns, cell_ranges)
    for i, range in ipairs(cell_ranges) do
        local row = range.start_row
        local is_markdown = range.cell_type == "markdown"

        local exec_count = range.execution_count
        local cell_label = is_markdown and " markdown " or " In [" .. (exec_count or " ") .. "] "

        if i > 1 then
            vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
                virt_lines_above = true,
                virt_lines = { { { " ", "Normal" } } },
            })
        end

        local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
        vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
            end_col = #line,
            conceal = "",
        })

        vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
            virt_text = { { cell_label } },
            virt_text_pos = "overlay",
        })
    end
end

return M
