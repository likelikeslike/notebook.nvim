vim.opt.rtp:append(".")
require("notebook").setup()

require("tests.notebook.utils_spec")
require("tests.notebook.ipynb_spec")
require("tests.notebook.output_spec")
require("tests.notebook.cells_spec")

require("tests.test_runner").summary()
