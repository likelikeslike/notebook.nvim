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
--- @return table[] cell_ranges Cell range info for each cell
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
    return cell_ranges
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

    M.setup_markdown_highlight(buf, cell_ranges)
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

--- Setup treesitter language injection for markdown cells
--- Hooks into the parser's injection lifecycle so that the markdown child
--- tree survives re-parses. Restricts the Python parser to code cell regions
--- @param buf number Buffer handle
--- @param cell_ranges table[] Cell range info with start_row, end_row, cell_type
function M.setup_markdown_highlight(buf, cell_ranges)
    local ok, parser = pcall(vim.treesitter.get_parser, buf)
    if not ok or not parser then return end

    local line_count = vim.api.nvim_buf_line_count(buf)
    local md_regions = {}
    local python_regions = {}
    local prev_end = 0

    for _, range in ipairs(cell_ranges) do
        if range.cell_type == "markdown" then
            local content_start = range.start_row + 1
            local content_end = range.end_row
            if content_start <= content_end then
                local end_line = math.min(content_end + 1, line_count)
                local start_byte = vim.api.nvim_buf_get_offset(buf, content_start)
                local end_byte = vim.api.nvim_buf_get_offset(buf, end_line)
                if start_byte >= 0 and end_byte >= 0 then
                    table.insert(md_regions, {
                        { content_start, 0, start_byte, end_line, 0, end_byte },
                    })
                end
            end
            if range.start_row > prev_end then
                local sb = vim.api.nvim_buf_get_offset(buf, prev_end)
                local cs = vim.api.nvim_buf_get_offset(buf, range.start_row + 1)
                if sb >= 0 and cs >= 0 then
                    table.insert(python_regions, {
                        { prev_end, 0, sb, range.start_row + 1, 0, cs },
                    })
                end
            end
            prev_end = math.min(content_end + 1, line_count)
        end
    end

    if #md_regions == 0 then
        parser._notebook_md_regions = nil
        if parser:children()["markdown"] then parser:remove_child("markdown") end
        parser:set_included_regions({ {} })
        parser._processed_injection_range = nil
        parser:invalidate(true)
        return
    end

    if prev_end < line_count then
        local sb = vim.api.nvim_buf_get_offset(buf, prev_end)
        local eb = vim.api.nvim_buf_get_offset(buf, line_count)
        if sb >= 0 and eb >= 0 then
            table.insert(python_regions, {
                { prev_end, 0, sb, line_count, 0, eb },
            })
        end
    end

    pcall(vim.treesitter.language.add, "markdown")
    pcall(vim.treesitter.language.add, "markdown_inline")

    parser._notebook_md_regions = md_regions

    if not parser._notebook_injections_hooked then
        local orig = parser._add_injections
        parser._add_injections = function(self, injections_by_lang)
            if self._notebook_md_regions then injections_by_lang["markdown"] = self._notebook_md_regions end
            return orig(self, injections_by_lang)
        end
        parser._notebook_injections_hooked = true
    end

    parser:set_included_regions(python_regions)
    parser._processed_injection_range = nil
    parser:invalidate(true)
    parser:parse(true)
end

return M
