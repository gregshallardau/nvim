#!/usr/bin/env bash
#
# filament-slice.sh — deterministic context distillation on the STRUCTURAL axis.
#
# A Filament feature is a Resource + its satellites, not a call graph. A
# `PostResource` depends structurally on its Pages (List/Create/Edit),
# RelationManagers, custom Form fields, Table columns and Actions — all CLASS
# references (use statements, ::class, typed properties), not method calls.
#
# This slicer takes a Resource (or any class), resolves every first-party class
# it references to a file via PSR-4, and pulls each referenced class body in
# full. Framework/vendor references (Filament\..., Illuminate\...) fall through
# to the External manifest — exactly the ones you would not expand anyway.
#
# Usage:
#   filament-slice.sh TARGET [options]
#     TARGET            a class name (PostResource) or a path to a .php file
#   Options:
#     --root DIR        project root (default: walk up for composer.json/artisan/.git)
#     --reindex         rebuild the symbol index before slicing
#     --depth N         how many hops of first-party refs to follow (default 1)
#     -h, --help        this help
#
# Exit codes: 0 ok · 2 usage · 3 missing dependency · 4 target not found
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die()  { printf 'filament-slice: %s\n' "$*" >&2; exit "${2:-1}"; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1 ($2)" 3; }

# ---- args -------------------------------------------------------------------
TARGET=""; ROOT=""; REINDEX=0; DEPTH=1
while [ $# -gt 0 ]; do
  case "$1" in
    --root)    ROOT="${2:?}"; shift 2;;
    --reindex) REINDEX=1; shift;;
    --depth)   DEPTH="${2:?}"; shift 2;;
    -h|--help) sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    -*)        die "unknown option: $1" 2;;
    *)         if [ -z "$TARGET" ]; then TARGET="$1"; else die "unexpected argument: $1" 2; fi; shift;;
  esac
done
[ -n "$TARGET" ] || die "usage: filament-slice.sh TARGET [--root DIR]" 2

need rg  "ripgrep"
need php "PHP CLI"
need jq  "jq"

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

# ---- PSR-4 prefix map -------------------------------------------------------
# Read composer.json autoload.psr-4 (+ autoload-dev) into "Prefix<TAB>dir" lines.
# Falls back to the Laravel default App\ -> app/.
psr4_map() {
  local cj="$ROOT/composer.json"
  if [ -f "$cj" ]; then
    jq -r '
      [ (.autoload."psr-4" // {}), (."autoload-dev"."psr-4" // {}) ]
      | add // {}
      | to_entries[] | "\(.key)\t\(.value)"
    ' "$cj" 2>/dev/null
  fi
  # Always ensure a sane default is present.
  printf 'App\\\t%s\n' "app/"
}

# Resolve a fully-qualified class name to an existing file path, or print nothing.
# Longest-prefix wins so App\ and App\Domain\ both map correctly.
resolve_fqcn() {
  local fqcn="${1#\\}"          # drop any leading backslash
  local best_prefix="" best_dir="" best_len=-1
  while IFS=$'\t' read -r prefix dir; do
    [ -n "$prefix" ] || continue
    if [[ "$fqcn" == "$prefix"* ]] && [ "${#prefix}" -gt "$best_len" ]; then
      best_prefix="$prefix"; best_dir="$dir"; best_len="${#prefix}"
    fi
  done < <(psr4_map)
  [ "$best_len" -ge 0 ] || return 0
  local rest="${fqcn#$best_prefix}"
  rest="${rest//\\//}"           # namespace sep -> path sep
  local path="$ROOT/${best_dir%/}/$rest.php"
  [ -f "$path" ] && printf '%s\n' "$path"
}

# ---- index (for class body ranges) -----------------------------------------
IDX_DIR="$ROOT/.nvim"
IDX="$IDX_DIR/ctxslice-index.jsonl"
build_index() {
  mkdir -p "$IDX_DIR"
  local files
  files="$(rg --files -tphp --glob '!vendor/**' --glob '!node_modules/**' \
            --glob '!storage/**' "$ROOT" 2>/dev/null || true)"
  [ -n "$files" ] || die "no PHP files found under $ROOT" 4
  printf '%s\n' "$files" | xargs -d '\n' php "$SELF_DIR/phpindex.php" > "$IDX" 2>/dev/null || true
  [ -s "$IDX" ] || die "index build produced no symbols" 4
}
if [ "$REINDEX" = 1 ] || [ ! -s "$IDX" ]; then build_index; fi

# Class body range for the first class defined in a file: "start end name".
class_range() {
  jq -rs --arg p "$1" '
    [ .[] | select(.path == $p and .kind == "class") ]
    | sort_by(.line) | .[0] // empty
    | "\(.line) \(.end) \(.name)"' "$IDX"
}

# ---- resolve target file ----------------------------------------------------
if [ -f "$TARGET" ]; then
  TARGET_FILE="$(cd "$(dirname "$TARGET")" && pwd)/$(basename "$TARGET")"
else
  # class name -> path via index, else rg for "class NAME"
  TARGET_FILE="$(jq -rs --arg n "$TARGET" '
    [ .[] | select(.name == $n and .kind == "class") ] | .[0].path // empty' "$IDX")"
  if [ -z "$TARGET_FILE" ]; then
    TARGET_FILE="$(rg -l --glob '!vendor/**' -e "\\bclass\\s+${TARGET}\\b" "$ROOT" 2>/dev/null | head -1 || true)"
  fi
  [ -n "$TARGET_FILE" ] || die "target class not found: $TARGET (try --reindex)" 4
fi

# ---- collect references from a file -----------------------------------------
# Prints unresolved-but-imported FQCNs (one per line) drawn from `use` statements
# plus inline `\App\...` references and `SomeClass::class` (resolved via `use`).
collect_uses() {   # collect_uses FILE
  rg -N --no-filename -e '^\s*use\s+([^;]+);' -o -r '$1' "$1" 2>/dev/null \
    | sed -E 's/\s+as\s+.*$//; s/^\s+//; s/\s+$//' \
    | grep -vE '^(function|const)\s' || true
}

# ---- walk -------------------------------------------------------------------
declare -A EMITTED=()        # path -> 1 (bodies already printed)
declare -A LOCAL_SEEN=()     # path -> 1 (queued/visited)
declare -A EXTERNAL=()       # fqcn -> group label

emit_body() {   # emit_body FILE  (prints the class body, or whole file fallback)
  local f="$1" rel="${1#$ROOT/}"
  local range name start end
  range="$(class_range "$f")"
  if [ -n "$range" ]; then
    start="${range%% *}"; end="$(printf '%s' "$range" | cut -d' ' -f2)"; name="${range#* * }"
    printf '### `%s` — `%s:%s-%s`\n\n```php\n%s\n```\n\n' \
      "$name" "$rel" "$start" "$end" "$(sed -n "${start},${end}p" "$f")"
  else
    printf '### `%s`\n\n```php\n%s\n```\n\n' "$rel" "$(cat "$f")"
  fi
}

# Group an external (non-first-party) FQCN by its vendor root for the manifest.
ext_group() {
  case "$1" in
    Filament\\*)   echo "Filament";;
    Illuminate\\*) echo "Laravel (Illuminate)";;
    Spatie\\*)     echo "Spatie";;
    *)             echo "other vendor";;
  esac
}

# Process one file: record its first-party refs as satellites, others external.
process_file() {   # process_file FILE
  local f="$1" fqcn resolved
  while IFS= read -r fqcn; do
    [ -n "$fqcn" ] || continue
    resolved="$(resolve_fqcn "$fqcn")"
    if [ -n "$resolved" ]; then
      if [ -z "${LOCAL_SEEN[$resolved]:-}" ]; then
        LOCAL_SEEN[$resolved]=1
        QUEUE+=("$resolved")
      fi
    else
      EXTERNAL["$fqcn"]="$(ext_group "$fqcn")"
    fi
  done < <(collect_uses "$f")
}

# BFS over first-party references up to --depth hops from the target.
declare -a QUEUE=("$TARGET_FILE")
LOCAL_SEEN["$TARGET_FILE"]=1
declare -a SATELLITES=()
hop=0
while [ "${#QUEUE[@]}" -gt 0 ] && [ "$hop" -le "$DEPTH" ]; do
  for f in "${QUEUE[@]}"; do
    process_file "$f"
    if [ "$f" != "$TARGET_FILE" ] && [ -z "${EMITTED[$f]:-}" ]; then
      SATELLITES+=("$f"); EMITTED[$f]=1
    fi
  done
  # QUEUE was appended to inside process_file; separate the newly-added ones.
  # Rebuild QUEUE from any LOCAL_SEEN files not yet emitted and not the target.
  QUEUE=()
  for p in "${!LOCAL_SEEN[@]}"; do
    if [ "$p" != "$TARGET_FILE" ] && [ -z "${EMITTED[$p]:-}" ]; then
      QUEUE+=("$p")
    fi
  done
  hop=$((hop + 1))
done

# ---- emit -------------------------------------------------------------------
N_SYM="$(wc -l < "$IDX" | tr -d ' ')"
T_REL="${TARGET_FILE#$ROOT/}"
T_NAME="$(basename "$TARGET_FILE" .php)"

printf '# Filament slice for `%s` (structural — Resource and satellites)\n\n' "$T_NAME"
printf '> filament-slice · root `%s` · %s symbols indexed · first-party refs expanded, vendor listed\n\n' "$ROOT" "$N_SYM"

printf '## Target — full body\n\n`%s`\n\n' "$T_REL"
range="$(class_range "$TARGET_FILE")"
if [ -n "$range" ]; then
  ts="${range%% *}"; te="$(printf '%s' "$range" | cut -d' ' -f2)"
  printf '```php\n%s\n```\n\n' "$(sed -n "${ts},${te}p" "$TARGET_FILE")"
else
  printf '```php\n%s\n```\n\n' "$(cat "$TARGET_FILE")"
fi

printf '## Satellites — first-party classes referenced (full bodies)\n\n'
if [ "${#SATELLITES[@]}" -eq 0 ]; then
  printf '_No first-party class references resolved (self-contained Resource)._\n\n'
else
  # stable, path-sorted output
  mapfile -t SATELLITES < <(printf '%s\n' "${SATELLITES[@]}" | sort -u)
  for f in "${SATELLITES[@]}"; do emit_body "$f"; done
fi

printf '## External — vendor / framework references (not expanded)\n\n'
if [ "${#EXTERNAL[@]}" -eq 0 ]; then
  printf '_No vendor references._\n\n'
else
  # group -> list
  mapfile -t EXT_GROUPS < <(printf '%s\n' "${EXTERNAL[@]}" | sort -u)
  for g in "${EXT_GROUPS[@]}"; do
    printf '**%s**\n\n' "$g"
    for fqcn in "${!EXTERNAL[@]}"; do
      if [ "${EXTERNAL[$fqcn]}" = "$g" ]; then printf -- '- `%s`\n' "$fqcn"; fi
    done | sort
    printf '\n'
  done
fi

printf -- '---\n_Out of view: External references are NOT shown — do not assume their API or behaviour._\n'
