local t = require("tests.test_runner")
local cells = require("notebook.cells")

t.describe("cells module", function()
    t.it("exports expected functions", function()
        t.is_function(cells.get_all)
        t.is_function(cells.get_current)
        t.is_function(cells.goto_next)
        t.is_function(cells.goto_prev)
        t.is_function(cells.refresh_cells)
        t.is_function(cells.add_below)
        t.is_function(cells.add_above)
        t.is_function(cells.delete_current)
        t.is_function(cells.toggle_type)
        t.is_function(cells.merge_below)
        t.is_function(cells.merge_above)
        t.is_function(cells.update_from_buffer)
        t.is_function(cells.get_markdown_ranges)
        t.is_function(cells.is_in_markdown)
        t.is_function(cells.filter_markdown_diagnostics)
    end)
end)

t.describe("cells.is_in_markdown", function()
    t.it("returns true for line inside markdown range", function()
        local ranges = { { 0, 3 }, { 10, 15 } }
        t.is_true(cells.is_in_markdown(2, ranges))
    end)

    t.it("returns true at range boundary", function()
        local ranges = { { 5, 10 } }
        t.is_true(cells.is_in_markdown(5, ranges))
        t.is_true(cells.is_in_markdown(10, ranges))
    end)

    t.it("returns false for line outside ranges", function()
        local ranges = { { 0, 3 }, { 10, 15 } }
        t.is_true(not cells.is_in_markdown(5, ranges))
    end)

    t.it("returns false for empty ranges", function()
        t.is_true(not cells.is_in_markdown(0, {}))
    end)
end)

t.describe("cells.filter_markdown_diagnostics", function()
    t.it("returns all diagnostics when no markdown ranges", function()
        local diags = { { lnum = 0 }, { lnum = 5 }, { lnum = 10 } }
        local buf = vim.api.nvim_create_buf(false, true)
        local ns = vim.api.nvim_create_namespace("test_filter_diag")
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "# %% id:test1",
            "print('hello')",
        })
        vim.b[buf].notebook_cells = {}
        local result = cells.filter_markdown_diagnostics(diags, buf, ns)
        t.eq(3, #result)
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    t.it("filters diagnostics in markdown cells", function()
        local diags = { { lnum = 1 }, { lnum = 5 }, { lnum = 8 } }
        local buf = vim.api.nvim_create_buf(false, true)
        local ns = vim.api.nvim_create_namespace("test_filter_md")

        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "# %% [markdown] id:md1",
            "# Heading",
            "Some text",
            "",
            "# %% id:code1",
            "x = 1",
            "",
            "# %% [markdown] id:md2",
            "# Another heading",
        })

        cells.refresh_cells(buf, ns)

        local result = cells.filter_markdown_diagnostics(diags, buf, ns)
        t.eq(1, #result)
        t.eq(5, result[1].lnum)

        vim.api.nvim_buf_delete(buf, { force = true })
    end)
end)

t.describe("diagnostic filter at vim.diagnostic.set", function()
    t.it("filters markdown diagnostics from count and get", function()
        local buf = vim.api.nvim_create_buf(false, true)
        local ns = vim.api.nvim_create_namespace("test_diag_set_filter")
        local diag_ns = vim.api.nvim_create_namespace("test_diag_source")

        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "# %% [markdown] id:md1",
            "# Heading",
            "Some text",
            "# %% id:code1",
            "x = 1",
        })

        cells.refresh_cells(buf, ns)
        require("notebook.notebook").setup_diagnostic_filter(buf, ns)

        vim.diagnostic.set(diag_ns, buf, {
            { lnum = 1, col = 0, message = "md warning", severity = vim.diagnostic.severity.WARN },
            { lnum = 4, col = 0, message = "code warning", severity = vim.diagnostic.severity.WARN },
        })

        local stored = vim.diagnostic.get(buf)
        t.eq(1, #stored, "only code cell diagnostic should be stored")
        t.eq("code warning", stored[1].message)

        local counts = vim.diagnostic.count(buf)
        local total = 0
        for _, v in pairs(counts) do
            total = total + v
        end
        t.eq(1, total, "diagnostic count should exclude markdown cells")

        vim.diagnostic.reset(diag_ns, buf)
        vim.api.nvim_buf_delete(buf, { force = true })
    end)
end)
