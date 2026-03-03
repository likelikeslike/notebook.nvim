local t = require("tests.test_runner")
local render = require("notebook.render")

t.describe("render module", function()
    t.it("exports expected functions", function()
        t.is_function(render.notebook)
        t.is_function(render.apply_decorations)
        t.is_function(render.render_outputs)
        t.is_function(render.setup_markdown_highlight)
    end)
end)

t.describe("render.notebook", function()
    t.it("returns cell_ranges table", function()
        local buf = vim.api.nvim_create_buf(false, true)
        local ns = vim.api.nvim_create_namespace("test_render_basic")
        local notebook = {
            cells = {
                {
                    cell_type = "code",
                    source = "x = 1",
                    outputs = {},
                },
            },
            metadata = {
                kernelspec = { name = "python3", display_name = "Python 3" },
            },
        }
        local cell_ranges = render.notebook(buf, notebook, ns)
        t.is_not_nil(cell_ranges)
        t.eq("table", type(cell_ranges))
        t.eq(1, #cell_ranges)
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    t.it("cell_range has required fields", function()
        local buf = vim.api.nvim_create_buf(false, true)
        local ns = vim.api.nvim_create_namespace("test_render_fields")
        local notebook = {
            cells = {
                {
                    cell_type = "code",
                    source = "print('hi')",
                    outputs = {},
                },
            },
            metadata = {
                kernelspec = { name = "python3", display_name = "Python 3" },
            },
        }
        local cell_ranges = render.notebook(buf, notebook, ns)
        local r = cell_ranges[1]
        t.is_not_nil(r.start_row, "start_row")
        t.is_not_nil(r.end_row, "end_row")
        t.is_not_nil(r.cell_type, "cell_type")
        t.is_not_nil(r.cell_index, "cell_index")
        t.is_not_nil(r.cell_id, "cell_id")
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    t.it("handles code and markdown cells with correct types", function()
        local buf = vim.api.nvim_create_buf(false, true)
        local ns = vim.api.nvim_create_namespace("test_render_types")
        local notebook = {
            cells = {
                {
                    cell_type = "code",
                    source = "x = 1",
                    outputs = {},
                },
                {
                    cell_type = "markdown",
                    source = "# Hello",
                    outputs = {},
                },
            },
            metadata = {
                kernelspec = { name = "python3", display_name = "Python 3" },
            },
        }
        local cell_ranges = render.notebook(buf, notebook, ns)
        t.eq(2, #cell_ranges)
        t.eq("code", cell_ranges[1].cell_type)
        t.eq("markdown", cell_ranges[2].cell_type)
        t.eq(1, cell_ranges[1].cell_index)
        t.eq(2, cell_ranges[2].cell_index)
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    t.it("sets buffer lines from notebook source", function()
        local buf = vim.api.nvim_create_buf(false, true)
        local ns = vim.api.nvim_create_namespace("test_render_lines")
        local notebook = {
            cells = {
                {
                    cell_type = "code",
                    source = "x = 42",
                    outputs = {},
                },
            },
            metadata = {
                kernelspec = { name = "python3", display_name = "Python 3" },
            },
        }
        render.notebook(buf, notebook, ns)
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        t.is_true(#lines >= 2, "buffer should have separator + source")
        t.eq("x = 42", lines[2])
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    t.it("creates empty notebook with one code cell when cells empty", function()
        local buf = vim.api.nvim_create_buf(false, true)
        local ns = vim.api.nvim_create_namespace("test_render_empty")
        local notebook = {
            cells = {},
            metadata = {
                kernelspec = { name = "python3", display_name = "Python 3" },
            },
        }
        local cell_ranges = render.notebook(buf, notebook, ns)
        t.eq(1, #cell_ranges)
        t.eq("code", cell_ranges[1].cell_type)
        vim.api.nvim_buf_delete(buf, { force = true })
    end)
end)

t.describe("render.setup_markdown_highlight", function()
    t.it("does not error on code-only cells", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "# %% id:code1",
            "x = 1",
        })
        local cell_ranges = {
            { start_row = 0, end_row = 1, cell_type = "code", cell_index = 1, cell_id = "code1" },
        }
        local ok = pcall(render.setup_markdown_highlight, buf, cell_ranges)
        t.is_true(ok, "should not error on code-only cells")
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    t.it("does not error on invalid buffer", function()
        local cell_ranges = {
            { start_row = 0, end_row = 1, cell_type = "markdown", cell_index = 1, cell_id = "md1" },
        }
        local ok = pcall(render.setup_markdown_highlight, 99999, cell_ranges)
        t.is_true(ok, "should not error on invalid buffer")
    end)

    t.it("sets _notebook_md_regions on parser when markdown cells present", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.bo[buf].filetype = "python"
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "# %% id:code1",
            "x = 1",
            "# %% [markdown] id:md1",
            "# Hello world",
        })

        local parser_ok, parser = pcall(vim.treesitter.get_parser, buf, "python")
        if not parser_ok then
            vim.api.nvim_buf_delete(buf, { force = true })
            return
        end

        local cell_ranges = {
            { start_row = 0, end_row = 1, cell_type = "code", cell_index = 1, cell_id = "code1" },
            { start_row = 2, end_row = 3, cell_type = "markdown", cell_index = 2, cell_id = "md1" },
        }
        render.setup_markdown_highlight(buf, cell_ranges)

        local p = vim.treesitter.get_parser(buf)
        t.is_not_nil(p._notebook_md_regions, "parser should have _notebook_md_regions set")
        t.eq(1, #p._notebook_md_regions, "should have one markdown region")
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    t.it("clears _notebook_md_regions when no markdown cells", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.bo[buf].filetype = "python"
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "# %% id:code1",
            "x = 1",
        })

        local parser_ok, _ = pcall(vim.treesitter.get_parser, buf, "python")
        if not parser_ok then
            vim.api.nvim_buf_delete(buf, { force = true })
            return
        end

        local cell_ranges = {
            { start_row = 0, end_row = 1, cell_type = "code", cell_index = 1, cell_id = "code1" },
        }
        render.setup_markdown_highlight(buf, cell_ranges)

        local p = vim.treesitter.get_parser(buf)
        t.is_nil(p._notebook_md_regions, "parser should not have _notebook_md_regions")
        vim.api.nvim_buf_delete(buf, { force = true })
    end)
end)

local function setup_highlight_buf()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "# %% id:code1",
        "x = 1",
        "# %% [markdown] id:md1",
        "# Hello world",
        "some **bold** text",
        "# %% id:code2",
        "for i in range(10):",
        "    print(i)",
    })
    vim.bo[buf].filetype = "python"
    local ts_ok = pcall(vim.treesitter.start, buf, "python")
    if not ts_ok then return nil end
    local cell_ranges = {
        { start_row = 0, end_row = 1, cell_type = "code", cell_index = 1, cell_id = "code1" },
        { start_row = 2, end_row = 4, cell_type = "markdown", cell_index = 2, cell_id = "md1" },
        { start_row = 5, end_row = 7, cell_type = "code", cell_index = 3, cell_id = "code2" },
    }
    render.setup_markdown_highlight(buf, cell_ranges)
    return buf, cell_ranges
end

local function has_capture(captures, name)
    for _, c in ipairs(captures) do
        if c.capture == name or c.capture:find(name, 1, true) == 1 then return true end
    end
    return false
end

local function has_lang(captures, lang)
    for _, c in ipairs(captures) do
        if c.lang == lang then return true end
    end
    return false
end

t.describe("markdown highlight integration", function()
    t.it("parser has markdown child tree after injection", function()
        local buf = setup_highlight_buf()
        if not buf then return end
        local parser = vim.treesitter.get_parser(buf)
        t.is_not_nil(parser:children()["markdown"], "parser should have markdown child")
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    t.it("markdown heading gets markup.heading capture", function()
        local buf = setup_highlight_buf()
        if not buf then return end
        local captures = vim.treesitter.get_captures_at_pos(buf, 3, 2)
        t.is_true(has_capture(captures, "markup.heading.1"), "should have markup.heading.1")
        t.is_true(has_lang(captures, "markdown"), "heading should come from markdown lang")
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    t.it("markdown cell does not get python captures", function()
        local buf = setup_highlight_buf()
        if not buf then return end
        local captures = vim.treesitter.get_captures_at_pos(buf, 3, 2)
        t.is_true(not has_lang(captures, "python"), "markdown line should not have python captures")
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    t.it("code cell gets python captures", function()
        local buf = setup_highlight_buf()
        if not buf then return end
        local captures = vim.treesitter.get_captures_at_pos(buf, 1, 0)
        t.is_true(has_lang(captures, "python"), "code cell should have python captures")
        t.is_true(has_capture(captures, "variable"), "x should be a variable capture")
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    t.it("code cell after markdown still gets python captures", function()
        local buf = setup_highlight_buf()
        if not buf then return end
        local captures = vim.treesitter.get_captures_at_pos(buf, 6, 0)
        t.is_true(has_lang(captures, "python"), "second code cell should have python captures")
        t.is_true(has_capture(captures, "keyword"), "for should be a keyword capture")
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    t.it("bold text in markdown gets markup capture", function()
        local buf = setup_highlight_buf()
        if not buf then return end
        local captures = vim.treesitter.get_captures_at_pos(buf, 4, 7)
        t.is_true(
            has_lang(captures, "markdown_inline") or has_lang(captures, "markdown"),
            "bold text should come from markdown or markdown_inline"
        )
        vim.api.nvim_buf_delete(buf, { force = true })
    end)
end)
