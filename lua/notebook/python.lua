---@mod notebook.python Python Interpreter Discovery
---@brief [[
--- Discovers and presents Python interpreters for kernel selection.
---
--- Search locations (in priority order):
--- 1. Workspace venvs: ./venv, ./env, ./*venv*
--- 2. Conda environments
--- 3. Pyenv: ~/.pyenv/versions/*
--- 4. UV: ~/.local/share/uv/python/*
--- 5. System: PATH
---
--- Environment types: conda, pyenv, uv, venv, system
--- Each has an icon for the picker display.
---@brief ]]

local M = {}

local function is_venv(env_type)
    local venv_types = { "conda", "pyenv", "uv", "venv" }
    return vim.tbl_contains(venv_types, env_type)
end

local function get_python_version(python_path)
    local result = vim.fn.system({ python_path, "--version" })
    if vim.v.shell_error == 0 and result then
        return result:match("Python%s+([%d%.]+)") or "unknown"
    end
    return "unknown"
end

local function get_venv_name(python_path)
    local venv_path = vim.fn.fnamemodify(python_path, ":h:h")
    return vim.fn.fnamemodify(venv_path, ":t")
end

local function parse_pyvenv_cfg(python_path)
    local venv_path = vim.fn.fnamemodify(python_path, ":h:h")
    local cfg_path = venv_path .. "/pyvenv.cfg"

    if vim.fn.filereadable(cfg_path) ~= 1 then return nil end

    local cfg = {}
    local file = io.open(cfg_path, "r")
    if not file then return nil end

    for line in file:lines() do
        local key, value = line:match("^([^=]+)%s*=%s*(.+)$")
        if key and value then cfg[key:gsub("%s+$", "")] = value:gsub("^%s+", "") end
    end
    file:close()

    return cfg
end

local function detect_env_type(python_path)
    local path_lower = python_path:lower()

    if path_lower:match("conda") or path_lower:match("anaconda") or path_lower:match("miniconda") then
        return "conda"
    end

    local venv_path = vim.fn.fnamemodify(python_path, ":h:h")
    if vim.fn.isdirectory(venv_path .. "/conda-meta") == 1 then return "conda" end

    local cfg = parse_pyvenv_cfg(python_path)
    if cfg and cfg.uv then return "uv" end
    if cfg then return "venv" end

    if path_lower:match("pyenv") then return "pyenv" end

    if
        path_lower:match("/usr/bin")
        or path_lower:match("/usr/local")
    then
        return "system"
    end

    return "unknown"
end

local function get_env_icon(env_type)
    local icons = {
        conda = "🐍",
        pyenv = "📦",
        uv = "⚡",
        venv = "🔵",
        system = "🖥️",
        unknown = "❓",
    }
    return icons[env_type] or icons.unknown
end

--- Find all available Python interpreters
--- @return table[] pythons Array of {path, display, source, env_type, version, is_venv, venv_name, icon}
function M.find_python_interpreters()
    local pythons = {}
    local seen = {}

    local function add_python(path, source, extra_info)
        if path and vim.fn.executable(path) == 1 then
            local real_path = vim.fn.resolve(path)
            if not seen[real_path] then
                seen[real_path] = true
                local version = get_python_version(path)
                local env_type = detect_env_type(path)
                local is_virtual = is_venv(env_type)
                local venv_name = ""

                if is_virtual then
                    if env_type == "conda" and path:match("envs") then
                        local env_match = path:match("envs/([^/]+)/bin")
                        venv_name = env_match and (" [" .. env_match .. "]") or ""
                    else
                        venv_name = " [" .. get_venv_name(path) .. "]"
                    end
                end

                local icon = get_env_icon(env_type)
                local display =
                    string.format("%s %s%s (v%s, %s)%s", icon, path, venv_name, version, env_type, extra_info or "")

                table.insert(pythons, {
                    path = path,
                    display = display,
                    source = source,
                    env_type = env_type,
                    version = version,
                    is_venv = is_virtual,
                    venv_name = is_virtual and (venv_name:match("%[(.+)%]") or get_venv_name(path)) or nil,
                    icon = icon,
                })
            end
        end
    end

    local workspace = vim.fn.getcwd()

    -- Workspace virtual environments
    local workspace_patterns = {
        workspace .. "/venv/bin/python*",
        workspace .. "/env/bin/python*",
        workspace .. "/*venv*/bin/python*",
        workspace .. "/.*/bin/python*",
    }

    for _, pattern in ipairs(workspace_patterns) do
        local matches = vim.fn.glob(pattern, false, true)
        for _, match in ipairs(matches) do
            if match:match("python3") or not match:match("python%d") then
                local env_type = detect_env_type(match)
                add_python(match, env_type == "uv" and "uv" or "workspace")
            end
        end
    end

    -- Conda environments
    if vim.fn.executable("conda") == 1 then
        local result = vim.fn.system({ "conda", "info", "--base" })
        if vim.v.shell_error == 0 and result then
            local conda_base = vim.trim(result)
            if conda_base ~= "" and vim.fn.isdirectory(conda_base) == 1 then
                local conda_envs = conda_base .. "/envs/*/bin/python*"
                local matches = vim.fn.glob(conda_envs, false, true)
                for _, match in ipairs(matches) do
                    if match:match("python3") or not match:match("python%d") then add_python(match, "conda") end
                end
                local conda_python = conda_base .. "/bin/python3"
                add_python(conda_python, "conda", " (base)")
            end
        end
    end

    -- pyenv environments
    local pyenv_root = os.getenv("PYENV_ROOT") or vim.fn.expand("~/.pyenv")
    if vim.fn.isdirectory(pyenv_root) == 1 then
        local pyenv_versions = pyenv_root .. "/versions/*/bin/python*"
        local matches = vim.fn.glob(pyenv_versions, false, true)
        for _, match in ipairs(matches) do
            if match:match("python3") or not match:match("python%d") then add_python(match, "pyenv") end
        end
    end

    -- UV environments (global)
    local uv_cache = vim.fn.expand("~/.local/share/uv/python/*/bin/python*")
    local uv_matches = vim.fn.glob(uv_cache, false, true)
    for _, match in ipairs(uv_matches) do
        if match:match("python3") or not match:match("python%d") then add_python(match, "uv") end
    end

    -- System PATH
    local path_pythons = {
        vim.fn.exepath("python3"),
        vim.fn.exepath("python"),
    }

    for _, python in ipairs(path_pythons) do
        if python ~= "" then add_python(python, "system") end
    end

    table.sort(pythons, function(a, b)
        local priority = {
            workspace = 1,
            uv = 2,
            conda = 3,
            pyenv = 4,
            venv = 5,
            system = 6,
            unknown = 7,
        }
        local a_priority = priority[a.source] or 999
        local b_priority = priority[b.source] or 999

        if a_priority == b_priority then
            local a_version = a.version or "0"
            local b_version = b.version or "0"
            return a_version > b_version
        end

        return a_priority < b_priority
    end)

    return pythons
end

--- Show picker to select Python interpreter
--- @param callback function(path: string) Called with selected Python path
function M.pick_python(callback)
    local pythons = M.find_python_interpreters()

    if #pythons == 0 then
        vim.notify("No Python interpreters found", vim.log.levels.WARN)
        return
    end

    local displays = {}
    local interpreter_map = {}

    for _, python in ipairs(pythons) do
        table.insert(displays, python.display)
        interpreter_map[python.display] = { path = python.path, env_type = python.env_type }
    end

    table.insert(displays, "[ Manual input ... ]")

    vim.ui.select(displays, {
        prompt = "Select Python Interpreter:",
    }, function(choice)
        if not choice then return end

        if choice == "[ Manual input ... ]" then
            vim.ui.input({
                prompt = "Enter Python path:",
                default = vim.fn.exepath("python3"),
            }, function(manual_path)
                if manual_path and manual_path ~= "" then
                    if vim.fn.executable(manual_path) == 1 then
                        callback(manual_path)
                    else
                        vim.notify("Invalid Python path: " .. manual_path, vim.log.levels.ERROR)
                    end
                end
            end)
        elseif interpreter_map[choice] and callback then
            callback(interpreter_map[choice])
        end
    end)
end

return M
