# ctxslice — Design Spec
_2026-07-03_

## Goal

Deterministic **context distillation** for LLM code review. Compute the
dependency slice of a symbol on the CPU (free) and hand a non-agentic model
(plain ChatGPT / Copilot / Claude) one tight file — ~300 lines ≈ 4–6k tokens —
so it can review or advise without burning 50–150k tokens searching.

Stack it targets: Laravel + Filament (PHP). Editor: this Neovim config.

**Primary use case:** "review this method / is this Resource wired up correctly"
against a cheap model, with all the retrieval already done.

---

## Core principles

1. **Retrieval is deterministic; reasoning is the model's job.** All search runs
   on the CPU, never as model tool-calls.
2. **Asymmetric expansion.** Callees (downstream) get FULL bodies — you need
   their behaviour to review the target. Callers (upstream) get SIGNATURE +
   call-site line only — you need the contract, not the implementation. This
   roughly halves the slice.
3. **Manifest header.** Symbols referenced but not expanded are listed
   ("External / out of view") so the model can't confidently review code it
   can't see.
4. **Expand only what's in the local index.** Vendor/framework symbols fall
   through to the manifest as external — exactly what you want.

### Laravel caveats (designed around, not fought)

Facades (`Cache::get`), container resolution, Eloquent relations
(`$user->posts`), and event dispatch are not statically followable. That's fine:
they resolve to vendor code we would not expand anyway. Treatment: **detect and
list as external, never chase.** The facade problem solves itself because the
callee pass only expands names present in the local index — `Cache::get` has no
first-party match, so it lands in the manifest.

Dynamic-dispatch limits are honest: `$this->foo()` yields the name `foo` but not
the owning class under traits/inheritance; `$var->foo()` is unresolvable without
type inference. The method *name* is usually enough signal for a review slice,
and anything unresolved is surfaced, not dropped.

---

## Architecture: engine vs editor

**Engine — standalone CLIs on PATH** (`bin/`). Must run headless; output feeds
tools outside the editor via the clipboard, so it cannot be welded to Neovim.

```
bin/
  ctxslice.sh        call-graph slicer (target + callees + callers + external)
  filament-slice.sh  structural slicer (Resource + satellites)
  phpindex.php       PHP-tokenizer symbol index (ctags-shaped JSON Lines)
  callees.php        PHP-tokenizer downstream call-target extractor
  README.md
```

**Editor layer — thin Lua, local module** (`lua/greg/`). Extract to a
`ctxslice.nvim` repo only once it earns config-driven-per-project surface;
premature extraction is the mistake, not premature plugin structure.

```
lua/greg/
  ctxslice.lua         async runner, buffer/clipboard fork, keymaps, commands
  ctxslice/health.lua  :checkhealth greg.ctxslice — dependency checks
lua/plugins/ctxslice.lua  local lazy.nvim spec
```

### Why Lua, not a bare `:!` shell-out

- `vim.system` (0.10+) runs async → the index pass never freezes the editor.
- Two output destinations map to the two consumers: scratch **buffer** (review
  in-editor) and the **clipboard** (`setreg('+')`, paste into ChatGPT).
- `<cword>` gives the symbol for free.
- `:checkhealth greg.ctxslice` is the nvim-native answer to "why did my slice
  come back empty".

---

## Two slicers — different axes

### A. Function slicer (`ctxslice.sh`) — call-graph axis

- **Index:** `phpindex.php` (`token_get_all`) → per-symbol start/end lines. Body
  extracted by `sed -n "start,end p"`.
- **Target + callers:** index + ripgrep. rg is a text matcher — great for "who
  calls F", so callers are found by pattern and mapped to their enclosing
  signature via the index.
- **Callees:** `callees.php` walks the target's token range, collects
  MethodCall / StaticCall / FuncCall / `new` identifiers, and the shell
  intersects with the index: hit → expand body, miss → external manifest.

### B. Filament slicer (`filament-slice.sh`) — structural axis

A Filament feature is usually not a call graph — it's a Resource + satellites
(`$model`, `getPages()`, `getRelations()`, custom fields/columns/actions), which
are **class references**, not method calls. Grab the Resource's `use` statements
and inline `\App\...` refs, resolve each first-party FQCN to a file via PSR-4,
pull each referenced class body. This is the common case for Filament review.

---

## Deviation from the original briefing: ctags

The briefing specified `universal-ctags --output-format=json --fields=+ne`, using
the `end:` field for body ranges. **The bundled PHP parser (through 5.9.x) does
not populate `end` for PHP**, so ctags cannot give the ranges the whole tool
depends on. `phpindex.php` produces the *same JSON shape* via the PHP tokenizer
(more correct for PHP, zero brace-text-matching, no extra dependency). The shell
treats the two interchangeably, so a future ctags with PHP end-line support drops
straight in.

Likewise, the briefing specified nikic/php-parser for callees. Because `composer`
is not always available and the JSON contract is what matters, Tier 0 ships a
tokenizer implementation; swapping in a php-parser AST walk (Tier 1) leaves the
shell untouched.

---

## Emitted slice format

```
# Context slice for `SYM` (partial — callers shown as sites only)
## Target    → full body (path:start-end)
## Callees   → resolved local bodies, full
## Callers   → signature + call-site line only
## External  → manifest: unexpanded symbols (facades, vendor, events)
```

---

## Accuracy tiers

- **Tier 0 (shipping):** tokenizer + rg. ~80%; false positives on common names.
- **Tier 1:** phpactor `references:find` (resolved callers) + nikic/php-parser
  (resolved callees). Same JSON contract.
- **Tier 2:** LSP call hierarchy (`incomingCalls` / `outgoingCalls`) — zero false
  positives. Verify phpactor exposes full callHierarchy over RPC before
  committing.

---

## Build order (status)

1. `ctxslice.sh` — target body + callers. ✅
2. `callees.php` + resolved callee expansion + external manifest. ✅
3. `filament-slice.sh` — Resource-and-satellites structural pass. ✅
4. `lua/greg/ctxslice.lua` — async runner, buffer/clipboard fork, keymaps. ✅
5. `lua/greg/ctxslice/health.lua` — dependency checks. ✅
6. (later) visual-selection capture; Tier 1/2 LSP backend; extract to a repo.

---

## Keymaps

| Key | Action |
|-----|--------|
| `<leader>cr` | function slice under cursor → buffer (review here) |
| `<leader>cc` | function slice under cursor → clipboard (copy for ChatGPT) |
| `<leader>cf` | filament slice of current file → buffer |

Commands: `:CtxSlice [sym]`, `:CtxSliceClip [sym]`, `:FilamentSlice [target]`.

---

## Out of scope (v1)

- Visual-selection capture (planned).
- Tier 1/2 resolved-reference backends (planned upgrade path).
- Cross-repo slicing; non-PHP languages.
- Extraction to a standalone `ctxslice.nvim` plugin (only once config-driven
  per-project settings are needed).
