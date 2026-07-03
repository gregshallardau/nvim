<?php
/**
 * phpindex.php — deterministic PHP symbol index for ctxslice.
 *
 * Emits one JSON object per line (JSON Lines) describing every class-like and
 * function/method symbol in the given files, with ACCURATE start and end lines.
 *
 * The output schema is deliberately a subset of universal-ctags'
 * `--output-format=json --fields=+ne` shape, so the shell layer treats this and
 * ctags interchangeably:
 *
 *   {"name","path","line","end","kind","scope","scopeKind"}
 *
 * WHY NOT CTAGS: universal-ctags' bundled PHP parser (through 5.9.x) does not
 * populate the `end:` field, so `sed -n "start,end p"` body extraction is
 * impossible off ctags for PHP. token_get_all gives exact ranges with no brace
 * text-matching, so it is both more correct and dependency-free here.
 *
 * Usage:
 *   php phpindex.php FILE [FILE ...]
 *   rg --files -tphp DIR | xargs php phpindex.php
 */

error_reporting(E_ALL & ~E_DEPRECATED);

$files = array_slice($argv, 1);
if (!$files) {
    fwrite(STDERR, "usage: php phpindex.php FILE [FILE ...]\n");
    exit(2);
}

foreach ($files as $file) {
    $src = @file_get_contents($file);
    if ($src === false) {
        fwrite(STDERR, "phpindex: cannot read $file\n");
        continue;
    }
    foreach (index_file($file, $src) as $tag) {
        echo json_encode($tag, JSON_UNESCAPED_SLASHES), "\n";
    }
}

/**
 * Return a list of ctags-shaped tag arrays for one PHP source string.
 */
function index_file(string $path, string $src): array
{
    $toks = @token_get_all($src);
    $n = count($toks);
    $tags = [];

    $namespace = null;
    // Stack frames: ['kind'=>..,'name'=>..,'line'=>..,'depth'=>brace depth at open,'scope'=>..]
    $stack = [];
    $depth = 0;
    $line = 1;

    // A symbol whose name we've read but whose opening `{` we haven't seen yet.
    $pending = null; // ['kind'=>'class'|'function','name'=>..,'line'=>..]

    for ($i = 0; $i < $n; $i++) {
        $t = $toks[$i];

        if (is_array($t)) {
            [$id, $text, $tline] = $t;
            $line = $tline; // array tokens carry their start line

            switch ($id) {
                case T_NAMESPACE:
                    $namespace = read_name($toks, $i + 1, $n);
                    break;

                case T_CLASS:
                case T_INTERFACE:
                case T_TRAIT:
                    // Skip anonymous classes: `new class {...}` has no name and
                    // `T_CLASS` not followed by a name token.
                    $name = next_string($toks, $i + 1, $n);
                    if ($name !== null && !is_class_keyword_context($toks, $i, $n)) {
                        $pending = ['kind' => 'class', 'name' => $name, 'line' => $tline];
                    }
                    break;

                case (defined('T_ENUM') ? T_ENUM : -1):
                    $name = next_string($toks, $i + 1, $n);
                    if ($name !== null) {
                        $pending = ['kind' => 'class', 'name' => $name, 'line' => $tline];
                    }
                    break;

                case T_FUNCTION:
                    $name = next_string($toks, $i + 1, $n);
                    if ($name !== null) {
                        // method if inside a class frame, else free function
                        $kind = 'function';
                        $pending = ['kind' => $kind, 'name' => $name, 'line' => $tline];
                    }
                    // else: closure / arrow fn (no name) — ignore.
                    break;
            }

            // advance line past any newlines inside this token's text
            $line += substr_count($text, "\n");
            continue;
        }

        // single-character token ('{', '}', ';', ...) — no line info attached
        if ($t === '{') {
            $depth++;
            if ($pending !== null) {
                $scope = current_scope($stack);
                $stack[] = [
                    'kind'      => $pending['kind'],
                    'name'      => $pending['name'],
                    'line'      => $pending['line'],
                    'depth'     => $depth,
                    'scope'     => $scope['name'],
                    'scopeKind' => $scope['kind'],
                ];
                $pending = null;
            }
        } elseif ($t === '}') {
            if (!empty($stack) && $stack[count($stack) - 1]['depth'] === $depth) {
                $frame = array_pop($stack);
                $tags[] = build_tag($frame, $path, $namespace, $line);
            }
            $depth--;
        }
        // `$pending` for an interface/abstract method ends at ';' with no body.
        elseif ($t === ';' && $pending !== null) {
            $scope = current_scope($stack);
            $tags[] = build_tag([
                'kind'      => $pending['kind'],
                'name'      => $pending['name'],
                'line'      => $pending['line'],
                'scope'     => $scope['name'],
                'scopeKind' => $scope['kind'],
            ], $path, $namespace, $line);
            $pending = null;
        }
    }

    return $tags;
}

/** Build one ctags-shaped tag from a completed frame. */
function build_tag(array $frame, string $path, ?string $namespace, int $end): array
{
    // ctags reports methods with kind "function"; classes/traits/interfaces/enums
    // as "class". We follow that so callers can filter on kind uniformly.
    $kind = $frame['kind'] === 'class' ? 'class' : 'function';

    $scope = $frame['scope'] ?? null;
    $scopeKind = $frame['scopeKind'] ?? null;

    // For top-level classes, ctags uses the namespace as scope.
    if ($kind === 'class' && $scope === null && $namespace) {
        $scope = $namespace;
        $scopeKind = 'namespace';
    }

    $tag = [
        '_type' => 'tag',
        'name'  => $frame['name'],
        'path'  => $path,
        'line'  => $frame['line'],
        'end'   => $end,
        'kind'  => $kind,
    ];
    if ($scope !== null) {
        $tag['scope'] = $scope;
        $tag['scopeKind'] = $scopeKind ?? 'class';
    }
    return $tag;
}

/** Innermost enclosing class/function frame, for scope reporting. */
function current_scope(array $stack): array
{
    for ($k = count($stack) - 1; $k >= 0; $k--) {
        $f = $stack[$k];
        return [
            'name' => $f['name'],
            'kind' => $f['kind'] === 'class' ? 'class' : 'function',
        ];
    }
    return ['name' => null, 'kind' => null];
}

/** The next T_STRING token name at/after index $j, skipping whitespace. */
function next_string(array $toks, int $j, int $n): ?string
{
    while ($j < $n && is_array($toks[$j]) && $toks[$j][0] === T_WHITESPACE) {
        $j++;
    }
    if ($j < $n && is_array($toks[$j]) && $toks[$j][0] === T_STRING) {
        return $toks[$j][1];
    }
    return null;
}

/** Read a (possibly namespaced) name starting at index $j. */
function read_name(array $toks, int $j, int $n): string
{
    $name = '';
    while ($j < $n) {
        $tt = $toks[$j];
        if (is_array($tt)) {
            $id = $tt[0];
            if ($id === T_WHITESPACE) { $j++; continue; }
            if ($id === T_STRING || $id === T_NS_SEPARATOR
                || (defined('T_NAME_QUALIFIED') && $id === T_NAME_QUALIFIED)
                || (defined('T_NAME_FULLY_QUALIFIED') && $id === T_NAME_FULLY_QUALIFIED)) {
                $name .= $tt[1];
                $j++;
                continue;
            }
        }
        break;
    }
    return trim($name);
}

/**
 * Detect `... class` used as a keyword rather than a declaration, e.g.
 * `Foo::class`. In that position T_CLASS is preceded by `::` (T_DOUBLE_COLON).
 */
function is_class_keyword_context(array $toks, int $i, int $n): bool
{
    for ($k = $i - 1; $k >= 0; $k--) {
        $t = $toks[$k];
        if (is_array($t) && $t[0] === T_WHITESPACE) { continue; }
        return is_array($t) && $t[0] === T_DOUBLE_COLON;
    }
    return false;
}
