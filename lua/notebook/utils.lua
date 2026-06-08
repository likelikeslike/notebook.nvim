---@mod notebook.utils Utility Functions
---@brief [[
--- Utilities for cell ID generation and separator line parsing.
---
--- Cell separator format: "# %%" (code) or "# %% [markdown]" (markdown).
--- Compatible with Jupytext percent-format and VS Code cell markers. The
--- marker must appear at column 0, followed by end-of-line, whitespace, or
--- "[". Lines like "# %" (one percent) or "# %%bar" are NOT separators.
---
--- Cell identity is tracked via extmarks in vim.b[buf].notebook_cells, NOT
--- via separator-line text. Keeping identity out of the buffer text prevents
--- LSP tools (copilot, codeium, ...) from ingesting synthetic id tokens that
--- the language model would then echo back as completions.
---@brief ]]

local M = {}

local id_counter = 0

local SEPARATOR_PATTERNS = {
    "^# %%%%$",
    "^# %%%%%s",
    "^# %%%%%[",
}

--- Generate a unique cell identifier
--- @return string cell_id
function M.generate_cell_id()
    id_counter = id_counter + 1
    return string.format("cell_%d_%d", vim.uv.hrtime(), id_counter)
end

--- Check whether a line is a cell separator.
--- @param line string
--- @return boolean
function M.is_separator(line)
    for _, pat in ipairs(SEPARATOR_PATTERNS) do
        if line:match(pat) then return true end
    end
    return false
end

--- Parse a cell separator line to extract its type.
--- @param line string Separator line (e.g. "# %% [markdown]")
--- @return string cell_type "code" or "markdown"
function M.parse_separator(line)
    if line:match("%[markdown%]") or line:match("%[md%]") then return "markdown" end
    return "code"
end

--- Build a cell separator line from type.
--- Cell identity is stored via extmarks.
--- @param cell_type string "code" or "markdown"
--- @return string separator
function M.build_separator(cell_type)
    if cell_type == "markdown" then return "# %% [markdown]" end
    return "# %%"
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
