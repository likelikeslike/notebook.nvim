---@mod notebook.render Initial Notebook Rendering
---@brief [[
--- Converts notebook data structure to buffer text on load.
---@brief ]]

local M = {}

local ipynb = require("notebook.ipynb")
local utils = require("notebook.utils")
local output = require("notebook.output")

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

        if cell.execution_count == vim.NIL then cell.execution_count = nil end

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
    M.render_outputs(buf, ns)
end

--- Apply visual decorations to cells
--- @param buf number Buffer handle
--- @param ns number Namespace for decoration extmarks
--- @param cell_ranges table[] Cell range info from notebook()
function M.apply_decorations(buf, ns, cell_ranges)
    local bg_ns = vim.api.nvim_create_namespace("jupyter_notebook_bg")
    vim.api.nvim_buf_clear_namespace(buf, bg_ns, 0, -1)

    for i, range in ipairs(cell_ranges) do
        local row = range.start_row
        local is_markdown = range.cell_type == "markdown"

        local bg_hl = is_markdown and "JupyterNotebookCellBgMarkdown" or "JupyterNotebookCellBg"
        local label_hl = is_markdown and "JupyterNotebookCellLabelMarkdown" or "JupyterNotebookCellLabel"
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
            virt_text = { { cell_label, label_hl } },
            virt_text_pos = "overlay",
            hl_mode = "combine",
        })

        for line_row = range.start_row, range.end_row do
            vim.api.nvim_buf_set_extmark(buf, bg_ns, line_row, 0, {
                line_hl_group = bg_hl,
                priority = 1,
            })
        end
    end
end

--- Render saved outputs for all cells as virtual text
--- Called on load and after cell refresh to display stored outputs.
--- @param buf number Buffer handle
--- @param ns number Namespace for cell extmarks
function M.render_outputs(buf, ns)
    local output_ns = vim.api.nvim_create_namespace("jupyter_notebook_output")
    vim.api.nvim_buf_clear_namespace(buf, output_ns, 0, -1)

    local cells = vim.b[buf].notebook_cells or {}
    local cell_outputs = vim.b[buf].cell_outputs or {}
    local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })

    for _, mark in ipairs(extmarks) do
        local id, _, _, details = mark[1], mark[2], mark[3], mark[4]
        local cell_info = cells[id]

        if cell_info and cell_info.cell_type == "code" and cell_info.cell_id then
            local output_data = cell_outputs[cell_info.cell_id]
            if output_data and output_data.outputs and #output_data.outputs > 0 then
                local end_row = details.end_row or 0
                local virt_lines =
                    output.format_outputs(output_data.outputs, output_data.execution_count, output_data.elapsed)
                if #virt_lines > 0 then
                    vim.api.nvim_buf_set_extmark(buf, output_ns, end_row, 0, {
                        virt_lines = virt_lines,
                        virt_lines_above = false,
                    })
                end
            end
        end
    end
end

return M
