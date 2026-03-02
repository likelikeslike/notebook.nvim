---@mod notebook.image Image Rendering via image.nvim
---@brief [[
--- Handles rendering of PNG images from cell outputs using image.nvim.
---
--- Image caching by cell_id to avoid re-rendering unchanged images.
--- FFI used to query terminal cell pixel dimensions for accurate sizing.
---@brief ]]

local M = {}

local image_api = nil
local image_cache = {}
local setup_attempted = false
local term_size_cache = nil

local DEFAULT_IMAGE_HEIGHT = 15

--- Check if image.nvim is available and properly configured
--- @return boolean available
function M.is_available()
    if image_api then return true end

    if setup_attempted then return false end
    setup_attempted = true

    local ok, api = pcall(require, "image")
    if not ok then return false end

    local test_ok = pcall(function()
        api.get_images()
    end)

    if not test_ok then
        vim.notify("image.nvim is installed but not properly set up.", vim.log.levels.WARN)
        return false
    end

    image_api = api
    return true
end

-- Query terminal cell dimensions in pixels using ioctl TIOCGWINSZ
-- This allows accurate image scaling to terminal cells
-- Falls back to 8x16 pixels per cell if FFI unavailable or ioctl fails
-- TIOCGWINSZ constants: Linux=0x5413, macOS/BSD=0x40087468
local function get_term_size()
    if term_size_cache then return term_size_cache end

    local ffi_ok, ffi = pcall(require, "ffi")
    if ffi_ok then
        pcall(function()
            ffi.cdef([[
                typedef struct {
                    unsigned short row;
                    unsigned short col;
                    unsigned short xpixel;
                    unsigned short ypixel;
                } winsize_t;
                int ioctl(int, int, ...);
            ]])
        end)

        local TIOCGWINSZ = 0x5413
        if vim.fn.has("mac") == 1 or vim.fn.has("bsd") == 1 then TIOCGWINSZ = 0x40087468 end

        local sz = ffi.new("winsize_t")
        if ffi.C.ioctl(1, TIOCGWINSZ, sz) == 0 and sz.xpixel > 0 and sz.ypixel > 0 then
            term_size_cache = {
                cell_width = sz.xpixel / sz.col,
                cell_height = sz.ypixel / sz.row,
            }
            return term_size_cache
        end
    end

    term_size_cache = { cell_width = 8, cell_height = 16 }
    return term_size_cache
end

--- Calculate display dimensions for a base64 PNG image
--- Uses ImageMagick identify to get actual image size, then scales to fit
--- @param base64_png string Base64-encoded PNG data
--- @param max_width number? Maximum width in terminal cells
--- @param max_height number? Maximum height in terminal cells
--- @return number width Display width in cells
--- @return number height Display height in cells
function M.get_image_dimensions_from_base64(base64_png, max_width, max_height)
    if not M.is_available() then return DEFAULT_IMAGE_HEIGHT, DEFAULT_IMAGE_HEIGHT end

    local tmp_path = vim.fn.tempname() .. ".png"
    local decoded = vim.base64.decode(base64_png)

    local file = io.open(tmp_path, "wb")
    if not file then return DEFAULT_IMAGE_HEIGHT, DEFAULT_IMAGE_HEIGHT end
    file:write(decoded)
    file:close()

    local final_width, final_height = DEFAULT_IMAGE_HEIGHT, DEFAULT_IMAGE_HEIGHT
    local ok, result = pcall(function()
        local handle = io.popen(string.format("identify -format '%%wx%%h' %q 2>/dev/null", tmp_path))
        if handle then
            local output = handle:read("*a")
            handle:close()
            local img_width, img_height = output:match("(%d+)x(%d+)")
            img_width = tonumber(img_width)
            img_height = tonumber(img_height)

            if img_width and img_height then
                local term_size = get_term_size()

                if not max_width then max_width = vim.api.nvim_win_get_width(0) - 6 end
                if not max_height then max_height = vim.api.nvim_win_get_height(0) end

                -- Convert image pixels to terminal cell units
                local width = math.floor(img_width / term_size.cell_width)
                local h = math.floor(img_height / term_size.cell_height)

                width = math.min(width, max_width)
                h = math.min(h, max_height)

                -- Scale to fit while preserving aspect ratio
                local aspect_ratio = img_width / img_height
                local pixel_width = width * term_size.cell_width
                local pixel_height = h * term_size.cell_height
                local percent_orig_width = pixel_width / img_width
                local percent_orig_height = pixel_height / img_height

                local result_width, result_height
                if percent_orig_height > percent_orig_width then
                    result_width = width
                    result_height = math.ceil(pixel_width / aspect_ratio / term_size.cell_height)
                else
                    result_width = math.ceil(pixel_height * aspect_ratio / term_size.cell_width)
                    result_height = h
                end

                return { math.max(1, result_width), math.max(1, result_height) }
            end
        end
        return { DEFAULT_IMAGE_HEIGHT, DEFAULT_IMAGE_HEIGHT }
    end)

    vim.fn.delete(tmp_path)

    if ok and result then
        final_width, final_height = result[1], result[2]
    end

    return final_width, final_height
end

--- Render a base64 PNG image in the buffer
--- @param buf number Buffer handle
--- @param cell_id string Unique identifier for caching
--- @param base64_png string Base64-encoded PNG data
--- @param line number 0-indexed line number to render at
--- @param img_width number? Display width in cells
--- @param img_height number? Display height in cells
function M.render(buf, cell_id, base64_png, line, img_width, img_height)
    if not M.is_available() then return nil end

    M.clear_cell(cell_id)

    local tmp_path = vim.fn.tempname() .. ".png"
    local decoded = vim.base64.decode(base64_png)

    local file = io.open(tmp_path, "wb")
    if not file then
        vim.notify("Failed to write temp image file", vim.log.levels.ERROR)
        return
    end
    file:write(decoded)
    file:close()

    local win = vim.api.nvim_get_current_win()
    local ok, img = pcall(function()
        return image_api.from_file(tmp_path, {
            id = "jupyter_" .. cell_id,
            window = win,
            buffer = buf,
            with_virtual_padding = false,
            inline = false,
            x = 0,
            y = line,
            width = img_width,
            height = img_height,
        })
    end)

    if not ok then
        vim.notify("[notebook.image] from_file failed: " .. tostring(img), vim.log.levels.WARN)
        vim.fn.delete(tmp_path)
        return
    end

    if img then
        if img_width and img_height then img.ignore_global_max_size = true end
        local render_ok, render_err = pcall(function()
            img:render()
        end)
        if not render_ok then
            vim.notify("[notebook.image] render failed: " .. tostring(render_err), vim.log.levels.WARN)
        end
        image_cache[cell_id] = {
            image = img,
            buf = buf,
            tmp_path = tmp_path,
            base64 = base64_png,
            line = line,
        }
    else
        vim.notify("[notebook.image] from_file returned nil", vim.log.levels.WARN)
        vim.fn.delete(tmp_path)
    end
end

--- Clear cached image for a cell
--- @param cell_id string Cell identifier
function M.clear_cell(cell_id)
    local cached = image_cache[cell_id]
    if cached then
        if cached.image then pcall(function()
            cached.image:clear()
        end) end
        if cached.tmp_path then vim.fn.delete(cached.tmp_path) end
        image_cache[cell_id] = nil
    end
end

--- Clear all cached images whose cell_id starts with prefix
--- @param prefix string Cell ID prefix to match
function M.clear_cell_prefix(prefix)
    for id, _ in pairs(image_cache) do
        if id:sub(1, #prefix) == prefix then M.clear_cell(id) end
    end
end

--- Clear all images in a buffer
--- @param buf number Buffer handle
function M.clear_buffer(buf)
    if not M.is_available() then return end

    local ok, images = pcall(function()
        return image_api.get_images({
            buffer = buf,
            namespace = "jupyter_notebook_output",
        })
    end)

    if ok and images then
        for _, img in ipairs(images) do
            pcall(function()
                img:clear()
            end)
        end
    end

    for id, cached in pairs(image_cache) do
        if cached.buf == buf then
            if cached.tmp_path then vim.fn.delete(cached.tmp_path) end
            image_cache[id] = nil
        end
    end
end

return M
