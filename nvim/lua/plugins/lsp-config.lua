local lspconfig = require("lspconfig")
local configs = require("lspconfig.configs")
local nvim_cmp = require("cmp_nvim_lsp")
local null_ls = require("null-ls")
local ts_utils = require("nvim-lsp-ts-utils")
local b = null_ls.builtins

local border_opts = {
	border = "rounded",
	focusable = false,
	scope = "line",
}

vim.diagnostic.config({ virtual_text = false, float = border_opts })

vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.with(vim.lsp.handlers.signature_help, border_opts)
vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, border_opts)

-- remap helper
local bufmap = function(bufnr, mode, lhs, rhs, opts)
	vim.api.nvim_buf_set_keymap(bufnr, mode, lhs, rhs, opts or {
		silent = true,
	})
end

local preferred_formatting_clients = { "eslint_d", "tsserver" }
local fallback_formatting_client = "null-ls"
local formatting = function()
	local bufnr = vim.api.nvim_get_current_buf()
	local selected_client
	for _, client in ipairs(vim.lsp.get_active_clients()) do
		if vim.tbl_contains(preferred_formatting_clients, client.name) then
			selected_client = client
			break
		end
		if client.name == fallback_formatting_client then
			selected_client = client
		end
	end
	if not selected_client then
		return
	end
	local params = vim.lsp.util.make_formatting_params()
	local result, err = selected_client.request_sync("textDocument/formatting", params, 5000, bufnr)
	if result and result.result then
		vim.lsp.util.apply_text_edits(result.result, bufnr)
	elseif err then
		vim.notify("global.lsp.formatting: " .. err, vim.log.levels.WARN)
	end
end

global.lsp = {
	border_opts = border_opts,
	formatting = formatting,
}

-- capabilities
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = nvim_cmp.update_capabilities(capabilities)
capabilities.textDocument.completion.completionItem.snippetSupport = true

-- custom on_attach (mappings)
local on_attach = function(client, bufnr)
	local opts = { noremap = true, silent = true }
	bufmap(bufnr, "n", "gd", "<cmd>lua vim.lsp.buf.definition()<CR>", opts)
	bufmap(bufnr, "n", "K", "<cmd>lua vim.lsp.buf.hover()<CR>", opts)
	bufmap(bufnr, "n", "<Leader>f", "<cmd>lua vim.lsp.buf.formatting()<CR>", opts)
	bufmap(bufnr, "i", "<C-x>", "<cmd>lua vim.lsp.buf.signature_help()<CR>", opts)
	bufmap(bufnr, "n", "<Leader>a", "<cmd>lua vim.diagnostic.open_float(nil,global.lsp.border_opts)<CR>", opts)
	-- bufmap('n', '<Leader>e', '<cmd>lua vim.lsp.diagnostic.show_line_diagnostics()<CR>', opts)
	-- bufmap('n', '[d', '<cmd>lua vim.lsp.diagnostic.goto_prev()<CR>', opts)
	-- bufmap('n', ']d', '<cmd>lua vim.lsp.diagnostic.goto_next()<CR>', opts)
	-- bufmap('n', '<Leader>q', '<cmd>lua vim.lsp.diagnostic.set_loclist()<CR>', opts)
	if client.resolved_capabilities.document_formatting then
		vim.cmd("autocmd BufWritePre <buffer> lua global.lsp.formatting()")
	end

	require("illuminate").on_attach(client)
end

configs.tailwindcss = {
	default_config = {
		cmd = { "tailwindcss-language-server", "--stdio" },
		filetypes = { "html", "javascript", "javascriptreact", "typescript", "typescriptreact", "vue", "svelte" },
		init_options = {},
		on_new_config = function(new_config)
			if not new_config.settings then
				new_config.settings = {}
			end
			if not new_config.settings.editor then
				new_config.settings.editor = {}
			end
			if not new_config.settings.editor.tabSize then
				-- set tab size for hover
				new_config.settings.editor.tabSize = vim.lsp.util.get_effective_tabstop()
			end
		end,
		root_dir = lspconfig.util.root_pattern(
			"tailwind.config.js",
			"tailwind.config.ts",
			"postcss.config.js",
			"postcss.config.ts",
			"package.json",
			"node_modules",
			".git"
		),
		settings = {
			tailwindCSS = {
				classAttributes = { "class", "className", "classList", "ngClass" },
				lint = {
					cssConflict = "warning",
					invalidApply = "error",
					invalidConfigPath = "error",
					invalidScreen = "error",
					invalidTailwindDirective = "error",
					invalidVariant = "error",
					recommendedVariantOrder = "warning",
				},
				validate = true,
			},
		},
	},
}

-- json server setup
lspconfig.jsonls.setup({
	on_attach = on_attach,
	capabilities = capabilities,
	settings = {
		json = {
			schemas = require("schemastore").json.schemas({
				select = {
					".eslintrc",
					"package.json",
					"tsconfig.json",
					"tslint.json",
				},
			}),
		},
	},
})

-- typescript server setup
lspconfig.tsserver.setup({
	root_dir = lspconfig.util.root_pattern("package.json"),
	init_options = ts_utils.init_options,
	on_attach = function(client, bufnr)
		on_attach(client, bufnr)
		ts_utils.setup({
			update_imports_on_move = true,
			filter_out_diagnostics_by_code = { 80001 },
		})
		ts_utils.setup_client(client)
		bufmap(bufnr, "n", "gs", ":TSLspOrganize<CR>")
		bufmap(bufnr, "n", "gI", ":TSLspRenameFile<CR>")
		bufmap(bufnr, "n", "go", ":TSLspImportAll<CR>")
	end,
	capabilities = capabilities,
	flags = {
		debounce_text_changes = 150,
	},
})

-- null-ls setup
local sources = {
	b.formatting.prettier.with({
		disabled_filetypes = {
			"typescript",
			"typescriptreact",
			"javascript",
			"javascriptreact",
		},
	}),
	b.formatting.goimports,
	b.formatting.sqlformat.with({
		extra_args = { "-a" },
	}),
	b.formatting.stylua,
}

null_ls.setup({
	sources = sources,
	on_attach = on_attach,
})

for _, lsp in ipairs({
	"gopls",
	"html",
	"cssls",
	"rust_analyzer",
	"tailwindcss",
	"pyright",
}) do
	lspconfig[lsp].setup({
		on_attach = on_attach,
		capabilities = capabilities,
		flags = {
			debounce_text_changes = 150,
		},
	})
end

-- suppress lspconfig messages
local notify = vim.notify
vim.notify = function(msg, ...)
	if msg:match("%[lspconfig%]") then
		return
	end

	notify(msg, ...)
end
