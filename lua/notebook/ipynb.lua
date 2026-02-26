---@mod notebook.ipynb .ipynb File I/O
---@brief [[
--- Handles loading and saving Jupyter notebook JSON format.
---
--- .ipynb structure:
---   { cells: [...], metadata: {...}, nbformat: 4, nbformat_minor: 5 }
---
--- Cell structure:
---   { cell_type, metadata, source, outputs?, execution_count? }
---
--- Source handling:
--- - In .ipynb: array of strings with "\n" suffix per line
--- - In buffer: plain lines without "\n"
--- - source_to_lines() / lines_to_source() convert between formats
---@brief ]]

local M = {}

local DEFAULT_NOTEBOOK = {
    cells = {},
    metadata = {
        kernelspec = {
            display_name = "Python 3",
            language = "python",
            name = "python3",
        },
        language_info = {
            name = "python",
            version = "3.11",
        },
    },
    nbformat = 4,
    nbformat_minor = 5,
}

--- Load and parse an .ipynb file
--- @param filename string Path to .ipynb file
--- @return table? notebook Parsed notebook or nil on error
function M.load(filename)
    local file = io.open(filename, "r")
    if not file then return vim.deepcopy(DEFAULT_NOTEBOOK) end

    local content = file:read("*all")
    file:close()

    if content == "" or content == nil then return vim.deepcopy(DEFAULT_NOTEBOOK) end

    local ok, notebook = pcall(vim.json.decode, content)
    if not ok then
        vim.notify("Failed to parse notebook JSON", vim.log.levels.ERROR)
        return nil
    end

    notebook.cells = notebook.cells or {}
    notebook.metadata = notebook.metadata or vim.deepcopy(DEFAULT_NOTEBOOK.metadata)
    notebook.nbformat = notebook.nbformat or DEFAULT_NOTEBOOK.nbformat
    notebook.nbformat_minor = notebook.nbformat_minor or DEFAULT_NOTEBOOK.nbformat_minor

    return notebook
end

--- @param json_str string Minified JSON
--- @return string indented_json_str Indented JSON with trailing newline
local function indent_json(json_str)
    local parts = {}
    local depth = 0
    local in_string = false
    local i = 1
    local len = #json_str

    while i <= len do
        local c = json_str:sub(i, i)

        if in_string then
            if c == "\\" then
                table.insert(parts, json_str:sub(i, i + 1))
                i = i + 2
            elseif c == '"' then
                in_string = false
                table.insert(parts, c)
                i = i + 1
            else
                table.insert(parts, c)
                i = i + 1
            end
        elseif c == '"' then
            in_string = true
            table.insert(parts, c)
            i = i + 1
        elseif c == "{" or c == "[" then
            depth = depth + 1
            table.insert(parts, c)
            table.insert(parts, "\n" .. string.rep(" ", depth))
            i = i + 1
        elseif c == "}" or c == "]" then
            depth = depth - 1
            table.insert(parts, "\n" .. string.rep(" ", depth))
            table.insert(parts, c)
            i = i + 1
        elseif c == "," then
            table.insert(parts, c)
            table.insert(parts, "\n" .. string.rep(" ", depth))
            i = i + 1
        elseif c == ":" then
            table.insert(parts, ": ")
            i = i + 1
        elseif c == " " or c == "\t" or c == "\n" or c == "\r" then
            i = i + 1
        else
            table.insert(parts, c)
            i = i + 1
        end
    end

    return table.concat(parts) .. "\n"
end

--- Save notebook data to .ipynb file
--- @param filename string Path to write
--- @param notebook table Notebook data structure
--- @return boolean success
function M.save(filename, notebook)
    local ok, json = pcall(vim.json.encode, notebook)
    if not ok then return false end

    local file = io.open(filename, "w")
    if not file then return false end

    file:write(indent_json(json))
    file:close()
    return true
end

--- Convert .ipynb source format to buffer lines
--- @param source string|string[] Cell source (string or array with \n suffixes)
--- @return string[] lines Plain lines without \n
function M.source_to_lines(source)
    if type(source) == "string" then
        return vim.split(source, "\n", { plain = true })
    elseif type(source) == "table" then
        local result = {}
        for _, line in ipairs(source) do
            line = line:gsub("\n$", "")
            table.insert(result, line)
        end
        return result
    end
    return {}
end

--- Convert buffer lines to .ipynb source format
--- @param lines string[] Plain buffer lines
--- @return string[] source Lines with \n suffix except last line
function M.lines_to_source(lines)
    local source = {}
    for i, line in ipairs(lines) do
        if i < #lines then
            table.insert(source, line .. "\n")
        else
            table.insert(source, line)
        end
    end
    return source
end

return M
