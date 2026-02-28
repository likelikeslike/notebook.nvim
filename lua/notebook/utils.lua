---@mod notebook.utils Utility Functions
---@brief [[
--- Utilities for cell ID generation and separator line parsing.
---
--- Cell separator format: "# %% [markdown] id:xxx"
--- - "# %%" is the cell marker (VS Code / Jupyter notebook style)
--- - "[markdown]" or "[md]" indicates markdown cell (optional)
--- - "id:xxx" is the unique cell identifier (optional, auto-generated)
---@brief ]]

local M = {}

local id_counter = 0

--- Generate a unique cell identifier
--- Format: "cell_{timestamp_ns}_{counter}"
--- @return string cell_id
function M.generate_cell_id()
    id_counter = id_counter + 1
    return string.format("cell_%d_%d", vim.uv.hrtime(), id_counter)
end

--- Parse a cell separator line to extract type and ID
--- @param line string Separator line (e.g. "# %% [markdown] id:abc123")
--- @return string cell_type "code" or "markdown"
--- @return string? cell_id Cell identifier if present
function M.parse_separator(line)
    local cell_type = "code"
    local cell_id = nil

    if line:match("%[markdown%]") or line:match("%[md%]") then cell_type = "markdown" end

    local id_match = line:match("id:([%w_]+)")
    if id_match then cell_id = id_match end

    return cell_type, cell_id
end

--- Build a cell separator line from type and ID
--- @param cell_type string "code" or "markdown"
--- @param cell_id string? Optional cell identifier
--- @return string separator The formatted separator line
function M.build_separator(cell_type, cell_id)
    local sep = "# %%"
    if cell_type == "markdown" then sep = sep .. " [markdown]" end
    if cell_id then sep = sep .. " id:" .. cell_id end
    return sep
end

--- Format elapsed time for display in output headers
--- @param elapsed number? Execution time in seconds
--- @return string formatted Human-readable time string or ""
function M.format_elapsed(elapsed)
    if not elapsed then return "" end
    if elapsed < 1 then
        return string.format(" (%.0fms)", elapsed * 1000)
    elseif elapsed < 60 then
        return string.format(" (%.2fs)", elapsed)
    else
        local mins = math.floor(elapsed / 60)
        local secs = elapsed % 60
        return string.format(" (%dm %.1fs)", mins, secs)
    end
end

return M
