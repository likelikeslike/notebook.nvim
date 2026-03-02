local t = require("tests.test_runner")
local output = require("notebook.output")

t.describe("output.extract_output", function()
    t.it("extracts stream output", function()
        local out = {
            output_type = "stream",
            name = "stdout",
            text = "hello\nworld",
        }
        local lines, hl, img = output.extract_output(out)
        t.eq(2, #lines)
        t.eq("hello", lines[1])
        t.eq("world", lines[2])
        t.eq("JupyterNotebookOutput", hl)
        t.is_nil(img)
    end)

    t.it("extracts stderr with error highlight", function()
        local out = {
            output_type = "stream",
            name = "stderr",
            text = "error message",
        }
        local lines, hl, _ = output.extract_output(out)
        t.eq(1, #lines)
        t.eq("JupyterNotebookOutputError", hl)
    end)

    t.it("extracts execute_result", function()
        local out = {
            output_type = "execute_result",
            data = {
                ["text/plain"] = "42",
            },
        }
        local lines, hl, _ = output.extract_output(out)
        t.eq(1, #lines)
        t.eq("42", lines[1])
        t.eq("JupyterNotebookOutputResult", hl)
    end)

    t.it("extracts error output", function()
        local out = {
            output_type = "error",
            ename = "ValueError",
            evalue = "invalid value",
            traceback = { "Traceback:", "  File ...", "ValueError: invalid value" },
        }
        local lines, hl, _ = output.extract_output(out)
        t.is_true(#lines > 0)
        t.eq("JupyterNotebookOutputError", hl)
    end)

    t.it("extracts image data from display_data", function()
        local out = {
            output_type = "display_data",
            data = {
                ["text/plain"] = "<Figure>",
                ["image/png"] = "iVBORw0KGgo=",
            },
        }
        local lines, _, img = output.extract_output(out)
        t.is_not_nil(img)
        t.eq("iVBORw0KGgo=", img)
    end)
end)

t.describe("output.format_outputs", function()
    t.it("formats outputs with header and footer", function()
        local outputs = {
            { output_type = "stream", name = "stdout", text = "hello" },
        }
        local virt_lines = output.format_outputs(outputs, 20, 1, 0.5, false)
        t.is_true(#virt_lines >= 3)
    end)

    t.it("shows interrupted indicator when interrupted", function()
        local outputs = {
            { output_type = "stream", name = "stdout", text = "partial" },
        }
        local virt_lines = output.format_outputs(outputs, 20, 1, 0.5, true)
        local header = virt_lines[1]
        local has_interrupted = false
        for _, segment in ipairs(header) do
            if segment[1]:match("%[Interrupted%]") then
                has_interrupted = true
                break
            end
        end
        t.is_true(has_interrupted)
    end)

    t.it("truncates long output", function()
        local long_text = {}
        for i = 1, 50 do
            table.insert(long_text, "line " .. i)
        end
        local outputs = {
            { output_type = "stream", name = "stdout", text = table.concat(long_text, "\n") },
        }
        local virt_lines = output.format_outputs(outputs, 10, 1, 0.5, false)
        local has_truncated = false
        for _, line in ipairs(virt_lines) do
            for _, segment in ipairs(line) do
                if segment[1]:match("truncated") then
                    has_truncated = true
                    break
                end
            end
        end
        t.is_true(has_truncated)
    end)
end)
