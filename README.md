# Clean LazyVim PHP/Laravel setup

This config is intentionally minimal and avoids the legacy pieces that were causing:
- missing modules
- nil keymap callbacks
- conform format_on_save warnings
- external Pint buffer reloads
- Neovim 0.12 LSP sync crashes

## Main workflow
- `gd` definitions preview/list
- `gr` references preview/list
- `K` hover docs
- `<leader>e` line diagnostics
- `[d` / `]d` previous / next diagnostic
- `<leader>qf` apply preferred quick-fix
- `<leader>ca` code actions
- `:w` save (LazyVim/conform handles formatting automatically)
- `<leader>lp` safe manual Pint dirty run in a split terminal
