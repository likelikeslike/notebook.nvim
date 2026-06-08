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

local notebook_mod = require("notebook.notebook")

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
        notebook_mod.setup_diagnostic_filter(buf, ns)

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

t.describe("cells.refresh_cells cell_id stability", function()
    t.it("preserves cell_id across edits when separator line is not deleted", function()
        local buf = vim.api.nvim_create_buf(false, true)
        local ns = vim.api.nvim_create_namespace("test_id_stability_1")

        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "# %%",
            "x = 1",
            "# %%",
            "y = 2",
        })
        cells.refresh_cells(buf, ns)

        local before = cells.get_all(buf, ns)
        t.eq(2, #before)
        local id0, id1 = before[1].cell_id, before[2].cell_id
        t.is_true(id0 ~= nil and id0 ~= "")
        t.is_true(id1 ~= nil and id1 ~= "")
        t.neq(id0, id1)

        vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "x = 1", "x = x + 1" })
        cells.refresh_cells(buf, ns)

        local after = cells.get_all(buf, ns)
        t.eq(2, #after)
        t.eq(id0, after[1].cell_id)
        t.eq(id1, after[2].cell_id)

        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    t.it("assigns fresh cell_id when a new separator is inserted", function()
        local buf = vim.api.nvim_create_buf(false, true)
        local ns = vim.api.nvim_create_namespace("test_id_stability_2")

        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# %%", "a = 1" })
        cells.refresh_cells(buf, ns)
        local one = cells.get_all(buf, ns)
        t.eq(1, #one)
        local original_id = one[1].cell_id

        vim.api.nvim_buf_set_lines(buf, 2, 2, false, { "# %%", "b = 2" })
        cells.refresh_cells(buf, ns)

        local two = cells.get_all(buf, ns)
        t.eq(2, #two)
        t.eq(original_id, two[1].cell_id)
        t.is_true(two[2].cell_id ~= nil and two[2].cell_id ~= "")
        t.neq(original_id, two[2].cell_id)

        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    t.it("buffer text never contains 'id:' after add_below (Copilot safety)", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_option(buf, "buflisted", true)
        local ns = vim.api.nvim_create_namespace("test_no_id_in_text")

        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# %%", "" })
        cells.refresh_cells(buf, ns)

        vim.api.nvim_set_current_buf(buf)
        cells.add_below(buf, ns)
        cells.add_below(buf, ns)

        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        for _, line in ipairs(lines) do
            t.eq(nil, line:match("id:"), "separator must not contain 'id:' — got: " .. line)
        end

        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    t.it("scrubs legacy '# %% id:xxx' lines on refresh (self-healing)", function()
        local buf = vim.api.nvim_create_buf(false, true)
        local ns = vim.api.nvim_create_namespace("test_self_heal")

        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "# %% id:legacy_abc",
            "x = 1",
            "# %% [markdown] id:legacy_md",
            "# heading",
        })
        cells.refresh_cells(buf, ns)

        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        t.eq("# %%", lines[1])
        t.eq("# %% [markdown]", lines[3])
        for _, line in ipairs(lines) do
            t.eq(nil, line:match("id:"))
        end

        local cs = cells.get_all(buf, ns)
        t.eq(2, #cs)
        t.eq("code", cs[1].cell_type)
        t.eq("markdown", cs[2].cell_type)

        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    t.it("does NOT treat '# %' or '# %%bar' as separators (tight regex)", function()
        local buf = vim.api.nvim_create_buf(false, true)
        local ns = vim.api.nvim_create_namespace("test_regex_tight")

        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "# %%",
            "x = 1",
            "# %",
            "y = 2",
            "# %%bar",
            "z = 3",
        })
        cells.refresh_cells(buf, ns)

        local cs = cells.get_all(buf, ns)
        t.eq(1, #cs, "only line 1 ('# %%') should be a separator")
        t.eq(0, cs[1].start_row)
        t.eq(5, cs[1].end_row)

        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    t.it("appends empty content row when separator is the last buffer line", function()
        local buf = vim.api.nvim_create_buf(false, true)
        local ns = vim.api.nvim_create_namespace("test_typed_cell_shape_eob")

        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "# %%",
            "x = 1",
            "# %%",
        })
        cells.refresh_cells(buf, ns)

        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        t.eq(4, #lines)
        t.eq("# %%", lines[1])
        t.eq("x = 1", lines[2])
        t.eq("# %%", lines[3])
        t.eq("", lines[4])

        local cs = cells.get_all(buf, ns)
        t.eq(2, #cs)
        t.eq(2, cs[2].start_row)
        t.eq(3, cs[2].end_row)

        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    t.it("inserts empty row between two adjacent separators", function()
        local buf = vim.api.nvim_create_buf(false, true)
        local ns = vim.api.nvim_create_namespace("test_typed_cell_shape_adj")

        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "# %%",
            "# %%",
            "y = 2",
        })
        cells.refresh_cells(buf, ns)

        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        t.eq(4, #lines)
        t.eq("# %%", lines[1])
        t.eq("", lines[2])
        t.eq("# %%", lines[3])
        t.eq("y = 2", lines[4])

        local cs = cells.get_all(buf, ns)
        t.eq(2, #cs)
        t.eq(0, cs[1].start_row)
        t.eq(1, cs[1].end_row)
        t.eq(2, cs[2].start_row)
        t.eq(3, cs[2].end_row)

        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    t.it("does NOT add a phantom row when cell already has content", function()
        local buf = vim.api.nvim_create_buf(false, true)
        local ns = vim.api.nvim_create_namespace("test_typed_cell_no_phantom")

        local before = { "# %%", "x = 1", "# %%", "y = 2" }
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, before)
        cells.refresh_cells(buf, ns)

        local after = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        t.eq(#before, #after)
        for k, v in ipairs(before) do
            t.eq(v, after[k])
        end

        vim.api.nvim_buf_delete(buf, { force = true })
    end)
end)

t.describe("cells.maybe_follow_typed_separator", function()
    t.it("moves cursor down by 1 when one new separator is on the cursor row in insert mode", function()
        local buf = vim.api.nvim_create_buf(false, true)
        local win = vim.api.nvim_open_win(buf, true, {
            relative = "editor",
            row = 0,
            col = 0,
            width = 20,
            height = 5,
        })
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x = 1", "# %%", "" })
        vim.api.nvim_win_set_cursor(win, { 2, 4 })

        local orig_mode = vim.api.nvim_get_mode
        vim.api.nvim_get_mode = function()
            return { mode = "i", blocking = false }
        end
        local ok, err = pcall(function()
            cells.maybe_follow_typed_separator(buf, { 1 })
        end)
        vim.api.nvim_get_mode = orig_mode
        t.is_true(ok, tostring(err))

        local pos = vim.api.nvim_win_get_cursor(win)
        t.eq(3, pos[1])
        t.eq(0, pos[2])

        vim.api.nvim_win_close(win, true)
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    t.it("does NOT move cursor when not in insert mode", function()
        local buf = vim.api.nvim_create_buf(false, true)
        local win = vim.api.nvim_open_win(buf, true, {
            relative = "editor",
            row = 0,
            col = 0,
            width = 20,
            height = 5,
        })
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x = 1", "# %%", "" })
        vim.api.nvim_win_set_cursor(win, { 2, 0 })

        cells.maybe_follow_typed_separator(buf, { 1 })

        local pos = vim.api.nvim_win_get_cursor(win)
        t.eq(2, pos[1])

        vim.api.nvim_win_close(win, true)
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    t.it("does NOT move cursor when more than one new separator (paste case)", function()
        local buf = vim.api.nvim_create_buf(false, true)
        local win = vim.api.nvim_open_win(buf, true, {
            relative = "editor",
            row = 0,
            col = 0,
            width = 20,
            height = 5,
        })
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# %%", "", "# %%", "" })
        vim.api.nvim_win_set_cursor(win, { 1, 4 })

        local orig_mode = vim.api.nvim_get_mode
        vim.api.nvim_get_mode = function()
            return { mode = "i", blocking = false }
        end
        cells.maybe_follow_typed_separator(buf, { 0, 2 })
        vim.api.nvim_get_mode = orig_mode

        local pos = vim.api.nvim_win_get_cursor(win)
        t.eq(1, pos[1])

        vim.api.nvim_win_close(win, true)
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    t.it("does NOT move cursor when cursor is on a different row", function()
        local buf = vim.api.nvim_create_buf(false, true)
        local win = vim.api.nvim_open_win(buf, true, {
            relative = "editor",
            row = 0,
            col = 0,
            width = 20,
            height = 5,
        })
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x = 1", "# %%", "" })
        vim.api.nvim_win_set_cursor(win, { 1, 0 })

        local orig_mode = vim.api.nvim_get_mode
        vim.api.nvim_get_mode = function()
            return { mode = "i", blocking = false }
        end
        cells.maybe_follow_typed_separator(buf, { 1 })
        vim.api.nvim_get_mode = orig_mode

        local pos = vim.api.nvim_win_get_cursor(win)
        t.eq(1, pos[1])

        vim.api.nvim_win_close(win, true)
        vim.api.nvim_buf_delete(buf, { force = true })
    end)
end)

t.describe("cells.update_from_buffer metadata.id", function()
    t.it("populates metadata.id with extmark cell_id for new cells", function()
        local buf = vim.api.nvim_create_buf(false, true)
        local ns = vim.api.nvim_create_namespace("test_metaid_new")

        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "# %%",
            "x = 1",
            "# %%",
            "y = 2",
        })
        cells.refresh_cells(buf, ns)

        local nb = { cells = {}, metadata = {}, nbformat = 4, nbformat_minor = 5 }
        local out = cells.update_from_buffer(buf, nb, ns)

        t.eq(2, #out.cells)
        local cs = cells.get_all(buf, ns)
        t.eq(cs[1].cell_id, out.cells[1].metadata.id)
        t.eq(cs[2].cell_id, out.cells[2].metadata.id)
        t.is_true(out.cells[1].metadata.id ~= nil and out.cells[1].metadata.id ~= "")

        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    t.it("preserves existing metadata.id from original notebook", function()
        local buf = vim.api.nvim_create_buf(false, true)
        local ns = vim.api.nvim_create_namespace("test_metaid_preserve")

        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# %%", "x = 1" })
        cells.refresh_cells(buf, ns)
        local cs = cells.get_all(buf, ns)
        local extmark_id = cs[1].cell_id

        local nb = {
            cells = { { cell_type = "code", metadata = { id = extmark_id, foo = "bar" }, source = { "x = 1" } } },
            metadata = {},
            nbformat = 4,
            nbformat_minor = 5,
        }
        local out = cells.update_from_buffer(buf, nb, ns)

        t.eq(extmark_id, out.cells[1].metadata.id)
        t.eq("bar", out.cells[1].metadata.foo)

        vim.api.nvim_buf_delete(buf, { force = true })
    end)
end)
