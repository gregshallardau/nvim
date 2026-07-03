<?php
/**
 * callees.php — extract the symbols a PHP method/function calls (downstream).
 *
 * Given a source file and an optional line range (the target symbol's body),
 * emit the DISTINCT set of call targets found inside it:
 *
 *   [{"kind":"method|static|func|new","class":<string|null>,"name":<string>}, ...]
 *
 * The shell layer intersects each `name` with the local symbol index:
 *   - hit  -> expand the callee's full body
 *   - miss -> list in the "External" manifest (facades, vendor, built-ins)
 *
 * This is the mechanism that makes the Laravel facade problem solve itself:
 * `Cache::get(...)` yields {kind:static,class:"Cache",name:"get"}; because no
 * local symbol named `Cache::get`/`get` matches a first-party class body, it
 * falls through to the manifest as external — never chased into vendor code.
 *
 * IMPLEMENTATION: PHP's built-in tokenizer (token_get_all). No composer
 * dependency, so it runs anywhere PHP does. The briefing's Tier-1 upgrade is to
 * swap this for a nikic/php-parser AST walk once `composer require
 * nikic/php-parser` is in the project; the JSON contract above stays identical,
 * so ctxslice.sh does not change. See bin/README.md.
 *
 * Usage:
 *   php callees.php --file PATH [--start N] [--end N]
 *   php callees.php --stdin            # read source from STDIN, whole buffer
 */

error_reporting(E_ALL & ~E_DEPRECATED);

$opts = parse_args($argv);
if (isset($opts['stdin'])) {
    $src = stream_get_contents(STDIN);
    $start = 1;
    $end = PHP_INT_MAX;
} elseif (isset($opts['file'])) {
    $src = @file_get_contents($opts['file']);
    if ($src === false) {
        fwrite(STDERR, "callees: cannot read {$opts['file']}\n");
        exit(2);
    }
    $start = isset($opts['start']) ? (int) $opts['start'] : 1;
    $end = isset($opts['end']) ? (int) $opts['end'] : PHP_INT_MAX;
} else {
    fwrite(STDERR, "usage: php callees.php --file PATH [--start N --end N] | --stdin\n");
    exit(2);
}

echo json_encode(array_values(extract_calls($src, $start, $end)), JSON_UNESCAPED_SLASHES), "\n";

/**
 * @return array<string,array{kind:string,class:?string,name:string}> keyed by
 *         a dedup signature so each distinct call target appears once.
 */
function extract_calls(string $src, int $start, int $end): array
{
    $toks = @token_get_all($src);
    $n = count($toks);
    $found = [];

    // Precompute a "line for token index" walk so single-char '(' can be tested,
    // and so we can gate every candidate on the target range by its NAME token.
    for ($i = 0; $i < $n; $i++) {
        $t = $toks[$i];
        if (!is_array($t)) {
            continue;
        }
        [$id, $text, $line] = $t;
        if ($line < $start || $line > $end) {
            continue;
        }

        // --- `new ClassName(` : constructor of a (possibly local) class -------
        if ($id === T_NEW) {
            $cls = read_class_ref($toks, $i + 1, $n);
            if ($cls !== null && followed_by_paren($toks, $cls['next'], $n)) {
                $short = short_name($cls['name']);
                add($found, 'new', $cls['name'], $short);
            }
            continue;
        }

        // --- static call: Class::method( ------------------------------------
        // The class ref is the token(s) *before* '::'. Detect when we're at a
        // T_DOUBLE_COLON and look both directions.
        if ($id === T_DOUBLE_COLON) {
            $method = next_string($toks, $i + 1, $n);
            if ($method !== null) {
                $pos = index_of_next_string($toks, $i + 1, $n);
                if ($pos !== null && followed_by_paren($toks, $pos + 1, $n)) {
                    $class = read_class_ref_backwards($toks, $i - 1);
                    add($found, 'static', $class, $method['name']);
                }
            }
            continue;
        }

        // --- method call: ->method(  or  ?->method( -------------------------
        if ($id === T_OBJECT_OPERATOR
            || (defined('T_NULLSAFE_OBJECT_OPERATOR') && $id === T_NULLSAFE_OBJECT_OPERATOR)) {
            $method = next_string($toks, $i + 1, $n);
            if ($method !== null) {
                $pos = index_of_next_string($toks, $i + 1, $n);
                if ($pos !== null && followed_by_paren($toks, $pos + 1, $n)) {
                    add($found, 'method', null, $method['name']);
                }
            }
            continue;
        }

        // --- free function call: name( --------------------------------------
        if ($id === T_STRING && followed_by_paren($toks, $i + 1, $n)) {
            // Exclude names that are actually the callee side of ->/:: (handled
            // above) or a declaration. Look back one significant token.
            $prev = prev_significant($toks, $i - 1);
            $skip = $prev !== null && is_array($prev) && in_array($prev[0], [
                T_OBJECT_OPERATOR, T_DOUBLE_COLON, T_FUNCTION, T_NEW, T_CLASS,
                T_INTERFACE, T_TRAIT,
            ], true);
            if (defined('T_NULLSAFE_OBJECT_OPERATOR') && $prev !== null && is_array($prev)
                && $prev[0] === T_NULLSAFE_OBJECT_OPERATOR) {
                $skip = true;
            }
            if (!$skip) {
                add($found, 'func', null, $t[1]);
            }
        }
    }

    return $found;
}

/** Insert a distinct call target keyed by kind+class+name. */
function add(array &$found, string $kind, ?string $class, string $name): void
{
    $key = $kind . '|' . ($class ?? '') . '|' . $name;
    if (!isset($found[$key])) {
        $found[$key] = ['kind' => $kind, 'class' => $class, 'name' => $name];
    }
}

/** @return array{name:string}|null Next T_STRING after $j (skip whitespace). */
function next_string(array $toks, int $j, int $n): ?array
{
    $idx = index_of_next_string($toks, $j, $n);
    return $idx === null ? null : ['name' => $toks[$idx][1]];
}

/** Index of the next T_STRING at/after $j, skipping only whitespace. */
function index_of_next_string(array $toks, int $j, int $n): ?int
{
    while ($j < $n && is_array($toks[$j]) && $toks[$j][0] === T_WHITESPACE) {
        $j++;
    }
    if ($j < $n && is_array($toks[$j]) && $toks[$j][0] === T_STRING) {
        return $j;
    }
    return null;
}

/** True if the next significant token at/after $j is '('. */
function followed_by_paren(array $toks, int $j, int $n): bool
{
    while ($j < $n) {
        $t = $toks[$j];
        if (is_array($t) && $t[0] === T_WHITESPACE) { $j++; continue; }
        return $t === '(';
    }
    return false;
}

/**
 * Read a class reference (name token sequence) starting at $j.
 * @return array{name:string,next:int}|null
 */
function read_class_ref(array $toks, int $j, int $n): ?array
{
    while ($j < $n && is_array($toks[$j]) && $toks[$j][0] === T_WHITESPACE) {
        $j++;
    }
    if ($j >= $n || !is_array($toks[$j])) {
        return null;
    }
    $id = $toks[$j][0];
    $ok = $id === T_STRING
        || $id === T_NS_SEPARATOR
        || (defined('T_NAME_QUALIFIED') && $id === T_NAME_QUALIFIED)
        || (defined('T_NAME_FULLY_QUALIFIED') && $id === T_NAME_FULLY_QUALIFIED)
        || $id === T_STATIC;
    if (!$ok) {
        return null;
    }
    return ['name' => $toks[$j][1], 'next' => $j + 1];
}

/** Read the class ref immediately before a `::` at index $k (scanning back). */
function read_class_ref_backwards(array $toks, int $k): ?string
{
    while ($k >= 0 && is_array($toks[$k]) && $toks[$k][0] === T_WHITESPACE) {
        $k--;
    }
    if ($k < 0 || !is_array($toks[$k])) {
        return null;
    }
    $id = $toks[$k][0];
    if ($id === T_STRING
        || (defined('T_NAME_QUALIFIED') && $id === T_NAME_QUALIFIED)
        || (defined('T_NAME_FULLY_QUALIFIED') && $id === T_NAME_FULLY_QUALIFIED)
        || $id === T_STATIC) {
        return short_name($toks[$k][1]);
    }
    return null;
}

/** Previous non-whitespace token before index $k, or null. */
function prev_significant(array $toks, int $k)
{
    while ($k >= 0) {
        if (is_array($toks[$k]) && $toks[$k][0] === T_WHITESPACE) { $k--; continue; }
        return $toks[$k];
    }
    return null;
}

/** Trailing segment of a namespaced name: App\Support\Money -> Money. */
function short_name(string $name): string
{
    $name = ltrim($name, '\\');
    $pos = strrpos($name, '\\');
    return $pos === false ? $name : substr($name, $pos + 1);
}

/** Minimal --flag / --flag=value / --flag value parser. */
function parse_args(array $argv): array
{
    $opts = [];
    for ($i = 1, $c = count($argv); $i < $c; $i++) {
        $a = $argv[$i];
        if (strncmp($a, '--', 2) !== 0) {
            continue;
        }
        $a = substr($a, 2);
        if (str_contains($a, '=')) {
            [$k, $v] = explode('=', $a, 2);
            $opts[$k] = $v;
        } elseif ($i + 1 < $c && strncmp($argv[$i + 1], '--', 2) !== 0) {
            $opts[$a] = $argv[++$i];
        } else {
            $opts[$a] = true;
        }
    }
    return $opts;
}
