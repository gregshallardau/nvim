# PHP Model Annotator Design

## Goal

A Neovim-integrated tool that statically parses Laravel Eloquent model files and writes `@property` PHPDoc annotations into them, giving intelephense full type resolution for magic attributes without modifying the PHP project or requiring a database connection.

## Architecture

Two components:

1. **`scripts/php-annotate.php`** — A standalone PHP script that reads a model file, extracts property information statically, and writes an annotated docblock back into the file in-place.
2. **`lua/plugins/php-annotate.lua`** — A LazyVim plugin spec that wires up keymaps, calls the script asynchronously via `vim.fn.jobstart()`, and notifies on completion.

The script lives at `~/.config/nvim/scripts/php-annotate.php` and is resolved at runtime via `vim.fn.stdpath("config")`, so it works wherever the config is cloned.

---

## The PHP Script

### Invocation

```
php ~/.config/nvim/scripts/php-annotate.php path/to/Model.php
```

Writes in-place. Exit codes:
- `0` — success
- `1` — not an Eloquent model (no `$fillable`, `$casts`, or relationship methods detected)
- `2` — file read/write error

### Property sources

| Source in model file | Generated annotation |
|---|---|
| Primary key (`$primaryKey`, default `id`) | `@property int $id` (or the declared type) |
| `$fillable` entry with no corresponding cast | `@property mixed $name` |
| `$casts['col' => 'int\|integer']` | `@property int $col` |
| `$casts['col' => 'real\|float\|double\|decimal']` | `@property float $col` |
| `$casts['col' => 'string\|encrypted']` | `@property string $col` |
| `$casts['col' => 'bool\|boolean']` | `@property bool $col` |
| `$casts['col' => 'array\|json\|encrypted:array\|encrypted:json']` | `@property array $col` |
| `$casts['col' => 'object\|encrypted:object']` | `@property object $col` |
| `$casts['col' => 'collection\|encrypted:collection']` | `@property \Illuminate\Support\Collection $col` |
| `$casts['col' => 'date\|datetime\|custom_datetime\|immutable_date\|immutable_datetime\|timestamp']` | `@property \Carbon\Carbon $col` |
| `$timestamps = true` (or absent, default true) | `@property \Carbon\Carbon $created_at` and `$updated_at` |
| `$timestamps = false` | No timestamp properties added |
| `$dates` array entry (legacy) | `@property \Carbon\Carbon $col` |
| `hasMany(Foo::class)` / `belongsToMany` method | `@property-read \Illuminate\Database\Eloquent\Collection<int, Foo> $methodName` |
| `hasOne(Foo::class)` / `belongsTo` / `morphTo` method | `@property-read Foo $methodName` |
| `morphMany(Foo::class)` | `@property-read \Illuminate\Database\Eloquent\Collection<int, Foo> $methodName` |

### Sentinel block

Generated properties are wrapped in sentinel comments so re-runs replace only the auto-generated block, leaving any hand-written docblock content untouched:

```php
/**
 * @php-annotate-start
 * @property int $id
 * @property string $name
 * @property \Carbon\Carbon $created_at
 * @property \Carbon\Carbon $updated_at
 * @property-read \Illuminate\Database\Eloquent\Collection<int, Post> $posts
 * @php-annotate-end
 *
 * @mixin \Eloquent
 */
class User extends Model
```

On re-run the script replaces everything between `@php-annotate-start` and `@php-annotate-end`, preserving all lines outside the sentinels.

If no docblock exists, one is created above the class declaration containing only the sentinel block.

### Parsing approach

Uses PHP tokenizer (`token_get_all()`) or regex for:
- Array literals assigned to `$fillable`, `$casts`, `$dates`
- `$timestamps` boolean assignment
- Public/protected methods whose body contains `return $this->hasMany(`, `hasOne(`, `belongsTo(`, `belongsToMany(`, `morphMany(`, `morphOne(`, `morphTo(` — extracts the first argument (related class name) and the method name becomes the property name

No autoloader, no class instantiation, no DB connection required.

---

## Neovim Plugin

### File

`lua/plugins/php-annotate.lua`

### Lazy loading

`ft = "php"` — only active in PHP buffers.

### Keymaps

Both keymaps sit in the existing `<leader>l` PHP tooling namespace:

| Key | Action |
|---|---|
| `<leader>lm` | Annotate the current buffer's model file |
| `<leader>lM` | Annotate all `*/Models/*.php` files under the project root |

### Behaviour

**`<leader>lm`:**
1. Resolve script path: `vim.fn.stdpath("config") .. "/scripts/php-annotate.php"`
2. Run `php <script> <current_file>` via `vim.fn.jobstart()`
3. On exit code 0: reload buffer (`vim.cmd("edit")`), notify "Annotated: filename.php"
4. On exit code 1: notify "Not an Eloquent model" (info, not error)
5. On exit code 2+: notify the stderr output as an error

**`<leader>lM`:**
1. Find project root via `vim.fs.find({"artisan", "composer.json", ".git"}, { upward = true })`
2. Glob `**/Models/*.php` under root
3. Run one `jobstart()` per file, tracking completion count
4. On all jobs done: notify "Annotated N models" (or "N annotated, M skipped, K errors")

Both operations are non-blocking.

---

## File Layout

```
~/.config/nvim/
  scripts/
    php-annotate.php
  lua/
    plugins/
      php-annotate.lua
```

---

## Out of Scope

- Generating `@method` annotations for query scopes
- Reading actual DB schema (use `ide-helper:models` for that)
- Annotating non-Eloquent classes
- Supporting `$casts` defined in `casts()` method (Laravel 9+ style) — only array property form
