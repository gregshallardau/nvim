#!/usr/bin/env bash
#
# ctxslice.sh — deterministic context distillation on the CALL-GRAPH axis.
#
# Given a PHP symbol, emit one tight markdown slice a non-agentic model can
# review without any further tool calls:
#
#   Target   -> full body                     (what you're reviewing)
#   Callees  -> full bodies, resolved locally  (downstream behaviour you need)
#   Callers  -> signature + call-site line only (upstream contract, not impl)
#   External -> manifest of unexpanded symbols  (facades, vendor, built-ins)
#
# The asymmetry (callees full, callers signature-only) roughly halves the slice
# while keeping everything needed to reason about the target.
#
# Retrieval is 100% CPU here; the model only reasons. See bin/README.md.
#
# Usage:
#   ctxslice.sh SYMBOL [options]
#     SYMBOL            method name, Class::method, or Class
#   Options:
#     --root DIR        project root (default: walk up for composer.json/artisan/.git)
#     --class NAME      disambiguate a bare method name to one class
#     --reindex         rebuild the symbol index before slicing
#     -h, --help        this help
#
# Exit codes: 0 ok · 2 usage · 3 missing dependency · 4 symbol not found
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bt='`'   # a literal backtick, to keep it out of double-quoted strings
die()  { printf 'ctxslice: %s\n' "$*" >&2; exit "${2:-1}"; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1 ($2)" 3; }

# ---- args -------------------------------------------------------------------
SYMBOL=""; ROOT=""; WANT_CLASS=""; REINDEX=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root)    ROOT="${2:?}"; shift 2;;
    --class)   WANT_CLASS="${2:?}"; shift 2;;
    --reindex) REINDEX=1; shift;;
    -h|--help) sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    -*)        die "unknown option: $1" 2;;
    *)         if [ -z "$SYMBOL" ]; then SYMBOL="$1"; else die "unexpected argument: $1" 2; fi; shift;;
  esac
done
[ -n "$SYMBOL" ] || die "usage: ctxslice.sh SYMBOL [--root DIR] [--class NAME] [--reindex]" 2

need rg  "ripgrep — https://github.com/BurntSushi/ripgrep"
need php "PHP CLI"
need jq  "jq — https://jqlang.github.io/jq"

# Class::method form
if [[ "$SYMBOL" == *"::"* ]]; then
  WANT_CLASS="${SYMBOL%%::*}"
  SYMBOL="${SYMBOL##*::}"
fi

# ---- root -------------------------------------------------------------------
find_root() {
  local d; d="$(pwd)"
  while [ "$d" != "/" ]; do
    if [ -f "$d/composer.json" ] || [ -f "$d/artisan" ] || [ -d "$d/.git" ]; then
      printf '%s\n' "$d"; return 0
    fi
    d="$(dirname "$d")"
  done
  pwd
}
[ -n "$ROOT" ] || ROOT="$(find_root)"
[ -d "$ROOT" ] || die "root is not a directory: $ROOT" 2

# ---- index ------------------------------------------------------------------
# Cached JSON-Lines symbol index (ctags-shaped: name,path,line,end,kind,scope).
IDX_DIR="$ROOT/.nvim"
IDX="$IDX_DIR/ctxslice-index.jsonl"

build_index() {
  mkdir -p "$IDX_DIR"
  # rg honours .gitignore (so vendor/ is skipped); belt-and-braces globs too.
  local files
  files="$(rg --files -tphp \
            --glob '!vendor/**' --glob '!node_modules/**' --glob '!storage/**' \
            "$ROOT" 2>/dev/null || true)"
  [ -n "$files" ] || die "no PHP files found under $ROOT" 4
  printf '%s\n' "$files" | xargs -d '\n' php "$SELF_DIR/phpindex.php" > "$IDX" 2>/dev/null || true
  [ -s "$IDX" ] || die "index build produced no symbols" 4
}

if [ "$REINDEX" = 1 ] || [ ! -s "$IDX" ]; then
  build_index
fi

# ---- locate target ----------------------------------------------------------
# Emits candidate objects; we take the best. Class scope in the index is the
# bare class name (phpindex) or FQCN (ctags) — match on its trailing segment.
class_match='($want == "") or (($t.scope // "") | split("\\\\") | last) == $want'

mapfile -t CANDS < <(
  jq -c --arg name "$SYMBOL" --arg want "$WANT_CLASS" '
    select(.name == $name)
    | . as $t
    | select('"$class_match"')
  ' "$IDX"
)

if [ "${#CANDS[@]}" -eq 0 ]; then
  die "symbol not found in index: ${WANT_CLASS:+$WANT_CLASS::}$SYMBOL  (try --reindex)" 4
fi

# Prefer a function/method over a same-named class for the target body.
TARGET=""
for c in "${CANDS[@]}"; do
  k="$(jq -r '.kind' <<<"$c")"
  if [ "$k" = "function" ]; then TARGET="$c"; break; fi
done
[ -n "$TARGET" ] || TARGET="${CANDS[0]}"

T_PATH="$(jq -r '.path' <<<"$TARGET")"
T_START="$(jq -r '.line' <<<"$TARGET")"
T_END="$(jq -r '.end'  <<<"$TARGET")"
T_KIND="$(jq -r '.kind' <<<"$TARGET")"
T_SCOPE="$(jq -r '.scope // ""' <<<"$TARGET")"
T_REL="${T_PATH#$ROOT/}"

# ---- helpers ----------------------------------------------------------------
body() { sed -n "${2},${3}p" "$1"; }              # body FILE START END
sig()  { sed -n "${2}p" "$1" | sed 's/^[[:space:]]*//'; }  # first (signature) line

# Resolve a callee name to a local symbol (prefer method/function). Prints the
# matching index object or nothing.
resolve_local() {
  local name="$1"
  jq -c --arg name "$name" 'select(.name == $name and .kind == "function")' "$IDX" | head -1
}

# True if a first-party class by this (short) name exists in the index.
class_is_local() {
  local name="$1"
  [ -n "$(jq -c --arg n "$name" 'select(.name == $n and .kind == "class")' "$IDX" | head -1)" ]
}

# ---- callees ----------------------------------------------------------------
CALLEES_JSON="$(php "$SELF_DIR/callees.php" --file "$T_PATH" --start "$T_START" --end "$T_END")"

declare -a CALLEE_LOCAL=()   # "name\tpath\tstart\tend"
declare -a EXTERNAL=()       # human-readable manifest lines
declare -A SEEN_LOCAL=()

# NB: a non-whitespace field separator (US, \x1f) is required — with @tsv the
# empty `class` middle field collapses under a whitespace IFS and shifts `name`.
while IFS=$'\x1f' read -r kind class name; do
  [ -n "$name" ] || continue
  # Never chase self-recursion into an infinite manifest entry.
  local_obj="$(resolve_local "$name")"
  if [ -n "$local_obj" ]; then
    lp="$(jq -r '.path' <<<"$local_obj")"
    ls="$(jq -r '.line' <<<"$local_obj")"
    le="$(jq -r '.end'  <<<"$local_obj")"
    # Skip the target itself (recursion) and dedupe.
    if [ "$lp" = "$T_PATH" ] && [ "$ls" = "$T_START" ]; then continue; fi
    key="$lp:$ls"
    if [ -z "${SEEN_LOCAL[$key]:-}" ]; then
      SEEN_LOCAL[$key]=1
      CALLEE_LOCAL+=("$name"$'\t'"$lp"$'\t'"$ls"$'\t'"$le")
    fi
  else
    case "$kind" in
      static)
        if [ -n "$class" ] && class_is_local "$class"; then
          EXTERNAL+=("${bt}${class}::${name}()${bt}  — first-party class, static method not expanded on this axis")
        else
          EXTERNAL+=("${bt}${class:-?}::${name}()${bt}  — static call (external)")
        fi;;
      new)
        if [ -n "$class" ] && class_is_local "$class"; then
          EXTERNAL+=("${bt}new ${class}()${bt}  — first-party class, constructor not expanded (try filament-slice for structure)")
        else
          EXTERNAL+=("${bt}new ${class:-$name}()${bt}  — instantiation (external)")
        fi;;
      method) EXTERNAL+=("${bt}->${name}()${bt}  — method (unresolved: dynamic dispatch or vendor)");;
      *)      EXTERNAL+=("${bt}${name}()${bt}  — function (vendor/built-in)");;
    esac
  fi
done < <(jq -r '.[] | [.kind, (.class // ""), .name] | join("\u001f")' <<<"$CALLEES_JSON")

# Dedup + sort external manifest.
if [ "${#EXTERNAL[@]}" -gt 0 ]; then
  mapfile -t EXTERNAL < <(printf '%s\n' "${EXTERNAL[@]}" | sort -u)
fi

# ---- callers ----------------------------------------------------------------
# Text search for call-sites; map each to its enclosing function signature.
declare -a CALLER_LINES=()
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  hpath="${hit%%:*}"; rest="${hit#*:}"
  hline="${rest%%:*}"; htext="${rest#*:}"
  # Skip the definition line itself.
  if [ "$hpath" = "$T_PATH" ] && [ "$hline" -ge "$T_START" ] && [ "$hline" -le "$T_END" ]; then
    continue
  fi
  # Find the (smallest) enclosing function for a call-site line.
  encl="$(jq -sc --arg p "$hpath" --argjson l "$hline" '[.[] | select(.path == $p and .kind == "function" and .line <= $l and .end >= $l)] | sort_by(.end - .line) | (.[0] // empty)' "$IDX")"
  hrel="${hpath#$ROOT/}"
  htext_trim="$(printf '%s' "$htext" | sed 's/^[[:space:]]*//')"
  if [ -n "$encl" ]; then
    ep="$(jq -r '.path' <<<"$encl")"; el="$(jq -r '.line' <<<"$encl")"
    en="$(jq -r '.name' <<<"$encl")"
    esig="$(sig "$ep" "$el")"
    CALLER_LINES+=("- ${bt}$hrel:$el${bt} **$en** — ${bt}$esig${bt}"$'\n'"    - called at ${bt}$hrel:$hline${bt}: ${bt}$htext_trim${bt}")
  else
    CALLER_LINES+=("- ${bt}$hrel:$hline${bt} (top-level): ${bt}$htext_trim${bt}")
  fi
done < <(rg --no-heading --line-number --with-filename \
            --glob '!vendor/**' --glob '!node_modules/**' \
            -e "(->|::)\\s*${SYMBOL}\\s*\\(" -e "\\b${SYMBOL}\\s*\\(" \
            "$ROOT" 2>/dev/null | head -n 200 || true)

# ---- emit -------------------------------------------------------------------
N_SYM="$(wc -l < "$IDX" | tr -d ' ')"
disp="${WANT_CLASS:+$WANT_CLASS::}$SYMBOL"

printf '# Context slice for `%s` (partial — callers shown as sites only)\n\n' "$disp"
printf '> ctxslice · root `%s` · %s symbols indexed · retrieval is deterministic, reasoning is yours\n\n' "$ROOT" "$N_SYM"

if [ "${#CANDS[@]}" -gt 1 ]; then
  printf '> ⚠ %s symbols named `%s` — sliced the %s in `%s`. Pass `--class NAME` to pick another.\n\n' \
    "${#CANDS[@]}" "$SYMBOL" "$T_KIND" "$T_SCOPE"
fi

printf '## Target — full body\n\n`%s:%s-%s`' "$T_REL" "$T_START" "$T_END"
[ -n "$T_SCOPE" ] && printf ' · scope `%s`' "$T_SCOPE"
printf '\n\n```php\n%s\n```\n\n' "$(body "$T_PATH" "$T_START" "$T_END")"

printf '## Callees — resolved local bodies (full)\n\n'
if [ "${#CALLEE_LOCAL[@]}" -eq 0 ]; then
  printf '_None resolved to first-party code._\n\n'
else
  for entry in "${CALLEE_LOCAL[@]}"; do
    IFS=$'\t' read -r cname cpath cstart cend <<<"$entry"
    crel="${cpath#$ROOT/}"
    printf '### `%s` — `%s:%s-%s`\n\n```php\n%s\n```\n\n' \
      "$cname" "$crel" "$cstart" "$cend" "$(body "$cpath" "$cstart" "$cend")"
  done
fi

printf '## Callers — signature + call-site only\n\n'
if [ "${#CALLER_LINES[@]}" -eq 0 ]; then
  printf '_No first-party call-sites found (entry point, interface impl, or dynamic dispatch)._\n\n'
else
  printf '%s\n' "${CALLER_LINES[@]}"
  printf '\n'
fi

printf '## External — unexpanded (facades, vendor, events, built-ins)\n\n'
if [ "${#EXTERNAL[@]}" -eq 0 ]; then
  printf '_Nothing called outside the local index._\n\n'
else
  for line in "${EXTERNAL[@]}"; do printf -- '- %s\n' "$line"; done
  printf '\n'
fi

printf -- '---\n_Out of view: symbols in the External manifest are NOT shown — do not assume their behaviour._\n'
