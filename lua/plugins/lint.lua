return {
	{
		"mfussenegger/nvim-lint",
		opts = function(_, opts)
			-- Disable all PHP linters (this removes PHPCS completely)
			opts.linters_by_ft = opts.linters_by_ft or {}
			opts.linters_by_ft.php = {}
		end,
	},
}
