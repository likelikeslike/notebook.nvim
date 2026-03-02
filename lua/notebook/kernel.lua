---@mod notebook.kernel Jupyter Kernel Communication
---@brief [[
--- Manages communication with Jupyter kernels via a Python subprocess.
---
--- Message Protocol (JSON over stdin/stdout):
--- Neovim → Python:
---   {"action": "start", "kernel": "python3"}
---   {"action": "execute", "code": "print(1)"}
---   {"action": "interrupt"}
---   {"action": "restart"}
---   {"action": "variables"}
---   {"action": "inspect", "name": "x"}
---
--- Python → Neovim:
---   {"status": "ready", "connection_file": "..."}
---   {"type": "output", "output": {...}}  -- streaming output
---   {"type": "done", "interrupted": false}
---   {"variables": {...}}
---   {"info": "..."}
---@brief ]]

local M = {}

--- Per-buffer kernel state: {python, pending_callback, streaming_callback, connection_file, ready, executing}
--- @type table<number, table>
local kernels = {}

--- Per-buffer job IDs for the Python subprocess
--- @type table<number, number>
local job_ids = {}

--- Send a JSON command to the Python subprocess
--- @param buf number Buffer handle
--- @param cmd table Command object to send
--- @param callback function Called when command completes: callback(success, result)
--- @param streaming_callback function|nil Called for each streaming output (execute only)
local function send_command(buf, cmd, callback, streaming_callback)
    local job_id = job_ids[buf]
    if not job_id then
        callback(false, "Kernel not running")
        return
    end

    local kernel = kernels[buf]
    if kernel.pending_callback then
        callback(false, "Kernel is busy processing a command")
        return
    end

    kernel.pending_callback = callback
    kernel.streaming_callback = streaming_callback
    local json_cmd = vim.json.encode(cmd) .. "\n"
    vim.fn.chansend(job_id, json_cmd)
end

--- Connect to a Jupyter kernel for the given buffer
--- Reads kernel name from notebook metadata, spawns Python subprocess,
--- starts kernel, and establishes communication channel
--- @param buf number Buffer handle
--- @param python table? Python interpreter info (path and env_type)
--- @param callback? function Called on success (no args)
function M.connect(buf, python, callback)
    if job_ids[buf] then
        if callback then callback() end
        return
    end

    local notebook = vim.b[buf].notebook
    local kernel_name = notebook and notebook.metadata.kernelspec and notebook.metadata.kernelspec.name or "python3"
    if not python then
        vim.notify("Python interpreter not configured, using system default `python3`.", vim.log.levels.WARN)
        python = { path = "python3", env_type = "system" }
    end

    local runtime_files = vim.api.nvim_get_runtime_file("scripts/jupyter_kernel_server.py", false)
    if #runtime_files == 0 then
        vim.notify("jupyter_kernel_server.py not found in runtime path", vim.log.levels.ERROR)
        return
    end
    local script_path = runtime_files[1]

    local stdout_buffer = ""
    local stderr_buffer = {}

    local function handle_json_message(result)
        local kernel = kernels[buf]
        if not kernel then return end

        if result.type == "execute_count" then
            kernel.execution_count = result.execution_count
            if kernel.on_execute_count then
                local cb = kernel.on_execute_count
                local count = result.execution_count
                vim.schedule(function()
                    cb(count)
                end)
            end
        elseif result.type == "output" then
            if kernel.streaming_callback then
                local cb = kernel.streaming_callback
                local out = result.output
                vim.schedule(function()
                    cb(out)
                end)
            end
        elseif result.type == "done" then
            local pending = kernel.pending_callback
            kernel.pending_callback = nil
            kernel.streaming_callback = nil
            if pending then vim.schedule(function()
                pending(true, result)
            end) end
        elseif kernel.pending_callback then
            local pending = kernel.pending_callback
            kernel.pending_callback = nil
            kernel.streaming_callback = nil
            vim.schedule(function()
                pending(true, result)
            end)
        end
    end

    -- Neovim job stdout delivers data as newline-split fragments.
    -- Empty string at boundary means a complete line was received.
    -- Accumulate fragments until a complete line parses as JSON,
    -- and reset the buffer when a complete line fails to parse
    -- (prevents garbage accumulation from stray subprocess output).
    local job_id = vim.fn.jobstart({ python.path, "-u", script_path }, {
        on_stdout = function(_, data)
            if not data then return end

            for i, chunk in ipairs(data) do
                stdout_buffer = stdout_buffer .. chunk
                local is_line_boundary = (i < #data)

                if is_line_boundary and stdout_buffer ~= "" then
                    local ok, result = pcall(vim.json.decode, stdout_buffer)
                    if ok then handle_json_message(result) end
                    stdout_buffer = ""
                end
            end
        end,
        on_stderr = function(_, data)
            if data then
                for _, line in ipairs(data) do
                    if line ~= "" then table.insert(stderr_buffer, line) end
                end
            end
        end,
        on_exit = function(_, code)
            local pending = kernels[buf] and kernels[buf].pending_callback
            job_ids[buf] = nil
            kernels[buf] = nil
            vim.schedule(function()
                if code ~= 0 then
                    local stderr_text = table.concat(stderr_buffer, "\n")
                    if stderr_text:match("ModuleNotFoundError.*jupyter_client") then
                        vim.notify(
                            "jupyter_client not installed. Use :JupyterSelectKernel to select a Python interpreter with Jupyter.",
                            vim.log.levels.ERROR
                        )
                    elseif stderr_text:match("ModuleNotFoundError") then
                        local module = stderr_text:match("ModuleNotFoundError: No module named '([^']+)'")
                        vim.notify(
                            "Missing Python module: " .. (module or "unknown") .. ". Check your Python environment.",
                            vim.log.levels.ERROR
                        )
                    else
                        vim.notify("Kernel process failed (code " .. code .. ")", vim.log.levels.ERROR)
                    end
                    if pending then pending(false, "Kernel process failed") end
                end
            end)
        end,
    })

    if job_id <= 0 then
        vim.notify("Failed to start kernel process", vim.log.levels.ERROR)
        return
    end

    job_ids[buf] = job_id
    kernels[buf] = { python = python, pending_callback = nil, ready = false, executing = false }

    send_command(buf, { action = "start", kernel = kernel_name }, function(success, result)
        if success and result.status == "ready" then
            kernels[buf].connection_file = result.connection_file
            kernels[buf].ready = true
            vim.notify("Connected to kernel: " .. kernel_name, vim.log.levels.INFO)
            if callback then callback() end
        else
            vim.notify(
                "Failed to connect to kernel: " .. (result and result.error or "unknown error"),
                vim.log.levels.ERROR
            )
        end
    end)
end

--- Disconnect kernel and cleanup resources for buffer
--- @param buf number Buffer handle
function M.disconnect(buf)
    local job_id = job_ids[buf]
    if not job_id then return end

    local ok = pcall(vim.fn.chansend, job_id, vim.json.encode({ action = "shutdown" }) .. "\n")
    if ok then
        vim.defer_fn(function()
            pcall(vim.fn.jobstop, job_id)
        end, 500)
    else
        pcall(vim.fn.jobstop, job_id)
    end

    job_ids[buf] = nil
    kernels[buf] = nil
end

--- Check if buffer has an active kernel connection
--- @param buf number Buffer handle
--- @return boolean
function M.is_connected(buf)
    return job_ids[buf] ~= nil
end

--- Check if kernel is ready to execute code
--- @param buf number Buffer handle
--- @return boolean
function M.is_ready(buf)
    local kernel = kernels[buf]
    return job_ids[buf] ~= nil and kernel ~= nil and kernel.ready == true and not kernel.executing
end

--- Execute code in the kernel with streaming output support
--- @param buf number Buffer handle
--- @param cell_info table Cell info containing source code
--- @param on_done function Called when execution completes: on_done(outputs, was_interrupted, execution_count)
--- @param on_output function|nil Called for each output chunk: on_output(outputs_so_far)
--- @param on_execute_count function|nil Called when execution starts: on_execute_count(execution_count)
--- @return boolean success Whether execution was initiated
function M.execute(buf, cell_info, on_done, on_output, on_execute_count)
    if not M.is_connected(buf) then
        on_done({ { output_type = "error", ename = "Error", evalue = "Kernel not connected" } }, false)
        return false
    end

    local kernel = kernels[buf]
    if not kernel or not kernel.ready then
        vim.notify("Kernel is starting, please wait...", vim.log.levels.INFO)
        return false
    end

    if kernel.executing then
        vim.notify("Kernel is busy executing, please wait...", vim.log.levels.INFO)
        return false
    end

    kernel.executing = true
    kernel.on_execute_count = on_execute_count
    local outputs = {}

    send_command(buf, { action = "execute", code = cell_info.source }, function(success, result)
        if kernels[buf] then
            kernels[buf].executing = false
            kernels[buf].on_execute_count = nil
        end
        local was_interrupted = result and result.interrupted
        local execution_count = result and result.execution_count
        if success then
            on_done(outputs, was_interrupted, execution_count)
        else
            table.insert(
                outputs,
                { output_type = "error", ename = "Error", evalue = result and result.error or "Execution failed" }
            )
            on_done(outputs, was_interrupted, execution_count)
        end
    end, function(output)
        table.insert(outputs, output)
        if on_output then on_output(outputs) end
    end)
    return true
end

--- Interrupt currently running execution
--- Sends interrupt directly (not via send_command) to avoid overwriting pending callback
--- @param buf number Buffer handle
function M.interrupt(buf)
    if not M.is_connected(buf) then return end
    local job_id = job_ids[buf]
    if job_id then
        local json_cmd = vim.json.encode({ action = "interrupt" }) .. "\n"
        vim.fn.chansend(job_id, json_cmd)
    end
end

--- Restart the kernel (clears all variables)
--- @param buf number Buffer handle
--- @param callback function Called when restart completes: callback(success)
function M.restart(buf, callback)
    if not M.is_connected(buf) then
        callback(false)
        return
    end

    if kernels[buf] then kernels[buf].executing = false end

    send_command(buf, { action = "restart" }, function(success, result)
        callback(success and result and result.status == "restarted")
    end)
end

--- Get all variables defined in the kernel
--- @param buf number Buffer handle
--- @param callback function Called with variables: callback({name: {type, value}})
function M.get_variables(buf, callback)
    if not M.is_connected(buf) then
        callback({})
        return
    end

    if not M.is_ready(buf) then
        vim.notify("Kernel is busy, please wait...", vim.log.levels.INFO)
        callback({})
        return
    end

    send_command(buf, { action = "variables" }, function(success, result)
        if success and result.variables then
            callback(result.variables)
        else
            callback({})
        end
    end)
end

--- Inspect a variable (get type and repr)
--- @param buf number Buffer handle
--- @param name string Variable name to inspect
--- @param callback function Called with info: callback({info: string})
function M.inspect(buf, name, callback)
    if not M.is_connected(buf) then
        callback({ info = "Kernel not connected" })
        return
    end

    if not M.is_ready(buf) then
        vim.notify("Kernel is busy, please wait...", vim.log.levels.INFO)
        callback({ info = "Kernel is busy" })
        return
    end

    send_command(buf, { action = "inspect", name = name }, function(success, result)
        if success and result.info then
            callback(result)
        else
            callback({ info = "Failed to inspect" })
        end
    end)
end

return M
