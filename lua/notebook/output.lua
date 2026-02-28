---@mod notebook.output Output Display
---@brief [[
--- Handles display of cell execution outputs.
---
--- Output data stored in vim.b[buf].cell_outputs[cell_id]:
---   { outputs, execution_count, elapsed }
---@brief ]]

local M = {}

local cells = require("notebook.cells")
local utils = require("notebook.utils")

local output_ns = vim.api.nvim_create_namespace("jupyter_notebook_output")
local float_wins = {}

--- Format outputs as virtual line specs for extmark display
--- @param outputs table[] Jupyter output messages
--- @param execution_count number? Kernel execution counter for header
--- @param elapsed number? Execution time in seconds
--- @return table[] virt_lines Array of {text, hl_group} tuples
function M.format_outputs(outputs, execution_count, elapsed)
    local virt_lines = {}
    local max_lines = 20
    local text_line_count = 0

    local count_str = execution_count and tostring(execution_count) or " "
    local time_str = utils.format_elapsed(elapsed)
    table.insert(virt_lines, {
        { "  ┌─ Out [" .. count_str .. "]" .. time_str .. " ", "JupyterNotebookOutputBorder" },
    })

    for _, output in ipairs(outputs) do
        -- TODO: Display image with image.nvim
        local lines, hl, img = M.extract_output(output)

        for _, line in ipairs(lines) do
            text_line_count = text_line_count + 1
            if text_line_count > max_lines then
                table.insert(virt_lines, { { "  │ ... (truncated)", "JupyterNotebookOutputBorder" } })
                goto finish
            end

            table.insert(virt_lines, { { "  │ ", "JupyterNotebookOutputBorder" }, { line, hl } })
        end
    end

    ::finish::
    table.insert(virt_lines, {
        {
            "  └─────────────────────────────────────",
            "JupyterNotebookOutputBorder",
        },
    })

    return virt_lines
end

--- Extract text lines and image data from a single output
--- @param output table Jupyter output message
--- @return string[] lines Text lines to display
--- @return string hl Highlight group name
--- @return string? image_data Base64 PNG data if present
function M.extract_output(output)
    local lines = {}
    local hl = "JupyterNotebookOutput"
    local image_data = nil

    if output.output_type == "stream" then
        local text = output.text
        if type(text) == "table" then text = table.concat(text, "") end
        for line in text:gmatch("[^\n]*") do
            if line ~= "" then table.insert(lines, line) end
        end
        hl = output.name == "stderr" and "JupyterNotebookOutputError" or "JupyterNotebookOutput"
    elseif output.output_type == "execute_result" or output.output_type == "display_data" then
        local data = output.data
        if data then
            if data["text/plain"] then
                local text = data["text/plain"]
                if type(text) == "table" then text = table.concat(text, "") end
                for line in text:gmatch("[^\n]*") do
                    if line ~= "" then table.insert(lines, line) end
                end
            end
            if data["image/png"] then
                local png = data["image/png"]
                if type(png) == "table" then png = table.concat(png, "") end
                png = png:gsub("%s+", "")
                image_data = png
                -- TODO: Display image with image.nvim
                table.insert(lines, "[Image: PNG]")
            end
        end
        hl = "JupyterNotebookOutputResult"
    elseif output.output_type == "error" then
        if output.traceback then
            for _, line in ipairs(output.traceback) do
                line = line:gsub("\27%[[%d;]*m", "")
                for subline in line:gmatch("[^\n]*") do
                    if subline ~= "" then table.insert(lines, subline) end
                end
            end
        elseif output.ename and output.evalue then
            table.insert(lines, output.ename .. ": " .. output.evalue)
        end
        hl = "JupyterNotebookOutputError"
    end

    return lines, hl, image_data
end


--- Toggle floating output window for current cell
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.toggle(buf, ns)
    local cell_info = cells.get_current(buf, ns)
    if not cell_info then return end

    local cell_outputs = vim.b[buf].cell_outputs or {}
    local output_data = cell_info.cell_id and cell_outputs[cell_info.cell_id]

    if not output_data or not output_data.outputs or #output_data.outputs == 0 then
        vim.notify("No output to display", vim.log.levels.INFO)
        return
    end

    if float_wins[buf] and vim.api.nvim_win_is_valid(float_wins[buf]) then
        vim.api.nvim_win_close(float_wins[buf], true)
        float_wins[buf] = nil
        return
    end

    M.show_float(buf, output_data.outputs)
end

--- Show full output in floating window
--- @param buf number Buffer handle
--- @param outputs table[] Jupyter output messages
function M.show_float(buf, outputs)
    local lines = {}

    local width = math.min(80, vim.o.columns - 4)
    local max_height = vim.o.lines - 4

    for _, output in ipairs(outputs) do
        local out_lines, _, img = M.extract_output(output)
        for _, line in ipairs(out_lines) do
            table.insert(lines, line)
        end
        -- TODO: Handle images
    end

    if #lines == 0 then return end

    local height = math.min(math.max(#lines + 2, 1), max_height)

    local float_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, lines)

    local win = vim.api.nvim_open_win(float_buf, true, {
        relative = "editorq",
        row = math.floor((vim.o.lines - height) / 2),
        col = math.floor((vim.o.columns - width) / 2),
        width = width,
        height = height,
        style = "minimal",
        border = "rounded",
        title = " Output ",
        title_pos = "center",
        footer = " q: close ",
        footer_pos = "center",
    })
    vim.bo[float_buf].modifiable = false
    vim.wo[win].cursorline = vim.go.cursorline
    vim.wo[win].number = vim.go.number
    vim.wo[win].relativenumber = vim.go.relativenumber

    float_wins[buf] = win

    vim.keymap.set("n", "q", function()
        if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
        float_wins[buf] = nil
    end, { buffer = float_buf })
end

--- Clear output for current cell
--- @param buf number Buffer handle
--- @param ns number Namespace for extmarks
function M.clear_cell(buf, ns)
    local cell_info = cells.get_current(buf, ns)
    if not cell_info then return end

    if cell_info.cell_id then
        local cell_outputs = vim.b[buf].cell_outputs or {}
        cell_outputs[cell_info.cell_id] = nil
        vim.b[buf].cell_outputs = cell_outputs
    end

    local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    for _, mark in ipairs(extmarks) do
        local id, _, _, details = mark[1], mark[2], mark[3], mark[4]
        local cell_data = vim.b[buf].notebook_cells and vim.b[buf].notebook_cells[id]

        if cell_data and cell_data.cell_id == cell_info.cell_id then
            local end_row = details.end_row or 0
            vim.api.nvim_buf_clear_namespace(buf, output_ns, end_row, end_row + 1)
            break
        end
    end
end

--- Clear all outputs in buffer
--- @param buf number Buffer handle
function M.clear_all(buf)
    vim.b[buf].cell_outputs = {}
    vim.api.nvim_buf_clear_namespace(buf, output_ns, 0, -1)
end

return M
