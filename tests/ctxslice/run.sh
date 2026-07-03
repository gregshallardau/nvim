#!/usr/bin/env bash
#
# ctxslice engine test suite. Exercises the standalone CLIs against the fixture
# project in tests/ctxslice/fixtures/. Runs headless (no nvim required):
#
#   bash tests/ctxslice/run.sh
#
# Exit code 1 on any failure.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$(cd "$HERE/../../bin" && pwd)"
FIX="$HERE/fixtures"

pass=0 fail=0

ok()   { pass=$((pass + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  \033[31m✗\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; }

# assert_contains "label" "haystack" "needle"
assert_contains() {
  if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else bad "$1" "missing: $3"; fi
}
# assert_not_contains "label" "haystack" "needle"
assert_not_contains() {
  if printf '%s' "$2" | grep -qF -- "$3"; then bad "$1" "unexpected: $3"; else ok "$1"; fi
}

# Fresh index for every run.
rm -f "$FIX/.nvim/ctxslice-index.jsonl"

echo
echo "phpindex.php — accurate symbol ranges"
IDX_OUT="$(php "$BIN/phpindex.php" "$FIX/app/Services/OrderService.php")"
assert_contains "indexes method total"        "$IDX_OUT" '"name":"total"'
assert_contains "total spans lines 10-14"     "$IDX_OUT" '"name":"total","path":"'"$FIX"'/app/Services/OrderService.php","line":10,"end":14'
assert_contains "indexes private lineTotals"  "$IDX_OUT" '"name":"lineTotals"'
assert_contains "indexes class OrderService"  "$IDX_OUT" '"name":"OrderService"'

echo
echo "callees.php — downstream call targets"
CALL_OUT="$(php "$BIN/callees.php" --file "$FIX/app/Services/OrderService.php" --start 10 --end 14)"
assert_contains "finds local method lineTotals" "$CALL_OUT" '"name":"lineTotals"'
assert_contains "finds facade Cache::get"       "$CALL_OUT" '"class":"Cache","name":"get"'
assert_contains "finds function array_sum"      "$CALL_OUT" '"name":"array_sum"'

echo
echo "ctxslice.sh — function (call-graph) slice"
SLICE="$(bash "$BIN/ctxslice.sh" 'OrderService::total' --root "$FIX" --reindex)"
assert_contains "has target section"            "$SLICE" '## Target'
assert_contains "target body present"           "$SLICE" 'public function total(Order $order): int'
assert_contains "callee lineTotals expanded"    "$SLICE" 'private function lineTotals(Order $order): array'
assert_contains "caller OrderController listed"  "$SLICE" 'OrderController'
assert_contains "caller shows call-site"        "$SLICE" 'return $service->total($order);'
assert_contains "Cache::get in External"        "$SLICE" 'Cache::get'
assert_not_contains "does not chase into vendor Cache body" "$SLICE" 'namespace Illuminate'

echo
echo "ctxslice.sh — first-party instantiation is not mislabelled external"
NEWSLICE="$(bash "$BIN/ctxslice.sh" 'OrderFactory::make' --root "$FIX" --reindex)"
assert_contains "new Order() flagged first-party"  "$NEWSLICE" 'first-party class'
assert_not_contains "new Order() not called external" "$NEWSLICE" 'new Order()`  — instantiation (external)'

echo
echo "ctxslice.sh — errors + edge cases"
bash "$BIN/ctxslice.sh" 'doesNotExistZZZ' --root "$FIX" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 4 ]; then ok "unknown symbol exits 4"; else bad "unknown symbol exits 4" "got rc=$rc"; fi

echo
echo "filament-slice.sh — structural slice"
FSLICE="$(bash "$BIN/filament-slice.sh" PostResource --root "$FIX" --reindex)"
assert_contains "target PostResource"           "$FSLICE" 'class PostResource extends Resource'
assert_contains "satellite Post (PSR-4)"        "$FSLICE" 'class Post extends Model'
assert_contains "satellite ListPosts (PSR-4)"   "$FSLICE" 'class ListPosts extends ListRecords'
assert_contains "external Filament grouped"     "$FSLICE" 'Filament\Resources\Resource'
assert_contains "external TextInput listed"     "$FSLICE" 'Filament\Forms\Components\TextInput'
assert_not_contains "does not expand vendor Resource body" "$FSLICE" 'abstract class Resource'

rm -f "$FIX/.nvim/ctxslice-index.jsonl"; rmdir "$FIX/.nvim" 2>/dev/null || true

echo
echo "────────────────────────────────────"
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
