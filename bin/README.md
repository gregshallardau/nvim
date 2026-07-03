# ctxslice engine

Deterministic **context distillation** for LLM code review of Laravel + Filament
(PHP) codebases.

Agentic assistants burn most of their tokens on *search* — read → grep → read →
re-send accumulating context every round-trip. `ctxslice` moves all of that
retrieval onto the CPU (free) and hands the model **one tight slice** (~a few KB)
it can review without any further tool calls. The output is meant to be pasted
into a plain, non-agentic model (ChatGPT / Copilot / Claude) — or reviewed inside
Neovim via the [editor layer](#editor-layer).

> **Retrieval is deterministic; reasoning is the model's job.**

These are standalone CLIs. They run headless and are decoupled from the editor on
purpose (partly PHP; output feeds tools *outside* the editor via the clipboard).

---

## Two slicers, two axes

Pick per task.

### `ctxslice.sh` — call-graph axis

Slice one function/method and everything needed to review it:

```
ctxslice.sh SYMBOL [--root DIR] [--class NAME] [--reindex]
```

| Section     | Expansion                                | Why |
|-------------|------------------------------------------|-----|
| **Target**  | full body                                | what you're reviewing |
| **Callees** | full bodies, resolved to local code      | you need their behaviour to review the target |
| **Callers** | signature + call-site line only          | you need the contract, not the implementation |
| **External**| manifest of unexpanded symbols           | facades, vendor, events — never chased |

The asymmetry (callees full, callers signature-only) roughly halves the slice
while keeping everything needed to reason about the target.

`SYMBOL` may be a bare method name (`total`), a `Class::method` (`OrderService::total`),
or a class name. Disambiguate a common method name with `--class`.

```sh
ctxslice.sh OrderService::total --root ~/platform
ctxslice.sh total --class OrderService
```

### `filament-slice.sh` — structural axis

A Filament feature is a Resource + satellites, not a call graph. This resolves
every first-party class a Resource references (via `use` + PSR-4) and pulls each
class body in full; framework refs fall through to the manifest.

```
filament-slice.sh TARGET [--root DIR] [--depth N] [--reindex]
```

`TARGET` is a class name (`PostResource`) or a path to a `.php` file.

```sh
filament-slice.sh PostResource --root ~/platform
filament-slice.sh app/Filament/Resources/PostResource.php
```

---

## How it resolves things

- **Symbol index** — `phpindex.php` walks each PHP file with the built-in
  tokenizer (`token_get_all`) and emits ctags-shaped JSON Lines with **accurate
  start/end lines** per class/method/function. Cached at
  `<root>/.nvim/ctxslice-index.jsonl`; rebuilt on `--reindex`.
- **Callees** — `callees.php` collects `->method(`, `Class::method(`, `func(`
  and `new Class(` targets inside the target's line range, then the shell
  intersects each name with the index: **hit → expand body, miss → manifest**.
  This is why the Laravel facade problem solves itself — `Cache::get` has no
  first-party match, so it lands in *External* instead of being chased into
  vendor code.
- **Callers** — ripgrep finds call-sites; each is mapped back to its enclosing
  function signature via the index.
- **PSR-4** — `filament-slice.sh` reads `composer.json`'s `autoload.psr-4`
  (default `App\ → app/`) and resolves each imported FQCN to a file,
  longest-prefix wins.

### Why not ctags for the index?

The briefing's original plan used `universal-ctags --fields=+ne` for symbol
end-lines. In practice the bundled PHP parser (through 5.9.x) **does not populate
the `end` field**, so body extraction off ctags is impossible for PHP.
`phpindex.php` emits the *same JSON shape* ctags would, so the shell treats them
interchangeably and a future ctags with PHP end-line support could drop straight
in.

---

## Accuracy tiers (upgrade path)

- **Tier 0 (shipping):** tokenizer + ripgrep. ~80% precision; false positives on
  very common method names, honest about dynamic dispatch. Good enough — the
  *name* is usually enough signal for a review slice, and unresolved names are
  surfaced in the manifest rather than silently dropped.
- **Tier 1:** swap `callees.php` for a [nikic/php-parser](https://github.com/nikic/PHP-Parser)
  AST walk (`composer require nikic/php-parser`) — the JSON contract is
  identical, so the shell is unchanged. Add phpactor `references:find` for
  resolved callers.
- **Tier 2:** LSP call hierarchy (`callHierarchy/incomingCalls` /
  `outgoingCalls`) for zero false positives.

---

## Dependencies

| Tool | Required | Used for |
|------|----------|----------|
| `bash` | yes | engine entry points |
| `php`  | yes | symbol index + callee extraction |
| `rg` ([ripgrep](https://github.com/BurntSushi/ripgrep)) | yes | callers + file discovery |
| `jq`   | yes | index queries |
| `ctags` | no | not used for PHP; `phpindex.php` supersedes it |

Run `:checkhealth greg.ctxslice` inside Neovim to verify these.

---

## Editor layer

`lua/greg/ctxslice.lua` runs the engine async (`vim.system`) and forks the result
to a scratch markdown buffer or the `+` register. Default keymaps:

| Key | Action |
|-----|--------|
| `<leader>cr` | function slice under cursor → buffer (review here) |
| `<leader>cc` | function slice under cursor → clipboard (paste into ChatGPT) |
| `<leader>cf` | filament slice of current file → buffer |

Commands: `:CtxSlice [sym]`, `:CtxSliceClip [sym]`, `:FilamentSlice [target]`.

---

## Tests

```sh
bash tests/ctxslice/run.sh
```

Headless bash suite over `tests/ctxslice/fixtures/` — no Neovim required.

---

## Exit codes

`0` ok · `2` usage error · `3` missing dependency · `4` symbol/target not found.
