---@mod notebook.output Output Display
---@brief [[
--- Handles display of cell execution outputs.
---
--- Output data stored in vim.b[buf].cell_outputs[cell_id]:
---   { outputs, execution_count, elapsed }
---@brief ]]

local M = {}

local utils = require("notebook.utils")

--- Format outputs as virtual line specs for extmark display
--- @param outputs table[] Jupyter output messages
--- @param execution_count number? Kernel execution counter for header
--- @param elapsed number? Execution time in seconds
--- @return table[] virt_lines Array of formatted output text
function M.format_outputs(outputs, execution_count, elapsed)
    local virt_lines = {}
    local max_lines = 20
    local text_line_count = 0

    local count_str = execution_count and tostring(execution_count) or " "
    local time_str = utils.format_elapsed(elapsed)
    table.insert(virt_lines, {
        { "  ┌─ Out [" .. count_str .. "]" .. time_str .. " " },
    })

    for _, output in ipairs(outputs) do
        -- TODO: Display image with image.nvim
        local lines, img = M.extract_output(output)

        for _, line in ipairs(lines) do
            text_line_count = text_line_count + 1
            if text_line_count > max_lines then
                table.insert(virt_lines, { { "  │ ... (truncated)" } })
                goto finish
            end

            table.insert(virt_lines, { { "  │ " }, { line } })
        end
    end

    ::finish::
    table.insert(virt_lines, {
        {
            "  └─────────────────────────────────────",
        },
    })

    return virt_lines
end

--- Extract text lines and image data from a single output
--- @param output table Jupyter output message
--- @return string[] lines Text lines to display
--- @return string? image_data Base64 PNG data if present
function M.extract_output(output)
    local lines = {}
    local image_data = nil

    if output.output_type == "stream" then
        local text = output.text
        if type(text) == "table" then text = table.concat(text, "") end
        for line in text:gmatch("[^\n]*") do
            if line ~= "" then table.insert(lines, line) end
        end
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
    end

    return lines, image_data
end

return M
