return {
  -- LazyVim uses Mason by default. This explicitly disables it.
  -- Note: Disabling Mason means LSP servers/formatters won't be auto-installed.
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },
}

