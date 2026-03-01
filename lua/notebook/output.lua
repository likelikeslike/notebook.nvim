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
local _image
local function image()
    if not _image then _image = require("notebook.image") end
    return _image
end

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
    local image_count = 0

    local count_str = execution_count and tostring(execution_count) or " "
    local time_str = utils.format_elapsed(elapsed)
    table.insert(virt_lines, {
        { "  ┌─ Out [" .. count_str .. "]" .. time_str .. " ", "JupyterNotebookOutputBorder" },
    })

    for _, output in ipairs(outputs) do
        local lines, hl, img = M.extract_output(output)

        for _, line in ipairs(lines) do
            text_line_count = text_line_count + 1
            if text_line_count > max_lines then
                table.insert(virt_lines, { { "  │ ... (truncated)", "JupyterNotebookOutputBorder" } })
                goto finish
            end

            table.insert(virt_lines, { { "  │ ", "JupyterNotebookOutputBorder" }, { line, hl } })
        end

        if img then
            image_count = image_count + 1
            table.insert(virt_lines, {
                { "  │ ", "JupyterNotebookOutputBorder" },
                { "[Image " .. image_count .. ": Use toggle_output action to view]", "JupyterNotebookOutputResult" },
            })
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
                if not image().is_available() then table.insert(lines, "[Image: PNG - image.nvim not available]") end
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
        if cell_info.cell_id then image().clear_cell_prefix(cell_info.cell_id .. "_float_") end
        vim.api.nvim_win_close(float_wins[buf], true)
        float_wins[buf] = nil
        return
    end

    M.show_float(buf, output_data.outputs, cell_info.cell_id)
end

--- Show full output in floating window with image support
--- @param buf number Buffer handle
--- @param outputs table[] Jupyter output messages
--- @param cell_id string? Cell identifier for image tracking
function M.show_float(buf, outputs, cell_id)
    local lines = {}
    local image_data = nil
    local images = {}

    local width = math.min(80, vim.o.columns - 4)
    local max_height = vim.o.lines - 4

    for _, output in ipairs(outputs) do
        local out_lines, _, img = M.extract_output(output)
        for _, line in ipairs(out_lines) do
            table.insert(lines, line)
        end
        if img then
            local entry = { data = img, line = #lines }
            if image().is_available() then
                local iw, ih = image().get_image_dimensions_from_base64(img, width, max_height)
                entry.width = iw
                entry.height = ih
                for _ = 1, ih do
                    table.insert(lines, "")
                end
            end
            table.insert(images, entry)
        end
    end

    if #lines == 0 and not image_data then return end

    local height = math.min(#lines + 2, max_height)

    local float_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, lines)

    local win = vim.api.nvim_open_win(float_buf, true, {
        relative = "editor",
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

    if #images > 0 and cell_id and image().is_available() then
        vim.schedule(function()
            for i, entry in ipairs(images) do
                -- FIXME: If multiple images are present and exceed the max_height, the images will overflow the float window and display incorrectly.
                image().render(float_buf, cell_id .. "_float_" .. i, entry.data, entry.line, entry.width, entry.height)
            end
        end)
    end

    vim.keymap.set("n", "q", function()
        if cell_id then image().clear_cell_prefix(cell_id .. "_float_") end
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
        image().clear_cell_prefix(cell_info.cell_id .. "_float_")
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

--- Show kernel variables in floating window
--- @param variables table<string, {type: string, value: string}> Variable info from kernel
function M.show_variables(variables)
    local lines = { "Variables:", "" }

    for name, info in pairs(variables) do
        table.insert(lines, string.format("  %s: %s = %s", name, info.type, info.value))
    end

    if #lines == 2 then table.insert(lines, "  (no variables)") end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    local width = math.min(80, vim.o.columns - 4)
    local height = math.min(#lines + 2, 20)

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        row = math.floor((vim.o.lines - height) / 2),
        col = math.floor((vim.o.columns - width) / 2),
        width = width,
        height = height,
        style = "minimal",
        border = "rounded",
        title = " Variables ",
        title_pos = "center",
        footer = " q: close ",
        footer_pos = "center",
    })

    vim.bo[buf].modifiable = false
    vim.wo[win].cursorline = vim.go.cursorline
    vim.wo[win].number = vim.go.number
    vim.wo[win].relativenumber = vim.go.relativenumber

    vim.keymap.set("n", "q", function()
        vim.api.nvim_win_close(win, true)
    end, { buffer = buf })
end

--- Show variable inspection in hover float
--- @param info {info: string} Inspection result from kernel
function M.show_hover(info)
    local lines = vim.split(info.info or "No info available", "\n")

    vim.lsp.util.open_floating_preview(lines, "python", {
        border = "rounded",
        focusable = true,
    })
end

return M
