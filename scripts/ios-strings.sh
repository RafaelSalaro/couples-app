#!/bin/bash
# Keeps the String Catalogs in step with the code, the way Xcode's own string
# extraction does for app targets (it does not run for Swift packages built from
# the command line).
#
# Every user-facing string is written as L("English text") or
# L("Ask \(name)"); the English text is the key. This script collects those
# keys per module and writes them to that module's Localizable.xcstrings,
# keeping existing translations and manually added entries.
#
#   ./scripts/ios-strings.sh          update the catalogs
#   ./scripts/ios-strings.sh --check  fail if a catalog is out of date (used by tests/CI)
#
# Interpolated values must be Strings (format numbers first, e.g. "\(n.formatted())"),
# so every placeholder is %@.
set -euo pipefail
cd "$(dirname "$0")/../ios"
python3 - "$@" <<'PY'
import json, os, re, sys

check = "--check" in sys.argv
# (source directory, catalog path)
modules = [("App", "App/Localizable.xcstrings")]
for ext in sorted(os.listdir("Extensions")):
    if os.path.isdir(os.path.join("Extensions", ext)):
        modules.append((os.path.join("Extensions", ext), os.path.join("Extensions", ext, "Localizable.xcstrings")))
for pkg in sorted(os.listdir("Packages")):
    src = os.path.join("Packages", pkg, "Sources")
    if not os.path.isdir(src):
        continue
    for target in sorted(os.listdir(src)):
        d = os.path.join(src, target)
        if os.path.isdir(d):
            modules.append((d, os.path.join(d, "Resources", "Localizable.xcstrings")))

def skip_string(text, i):
    """Index just past the Swift string literal starting at text[i] == '"', including
    interpolations that themselves contain strings and parentheses."""
    i += 1
    while i < len(text):
        c = text[i]
        if c == "\\" and text.startswith("\\(", i):
            i = skip_interpolation(text, i + 2)
            continue
        if c == "\\":
            i += 2
            continue
        if c == '"':
            return i + 1
        if c == "\n":
            return -1  # not a single-line literal
        i += 1
    return -1

def skip_interpolation(text, i):
    """Index just past the ')' closing an interpolation whose content starts at text[i]."""
    depth = 1
    while i < len(text) and depth:
        c = text[i]
        if c == '"':
            j = skip_string(text, i)
            if j < 0:
                return len(text)
            i = j
            continue
        depth += {"(": 1, ")": -1}.get(c, 0)
        i += 1
    return i

def literals(text):
    """The contents of every L("…") call's first argument (single-line string literals)."""
    for m in re.finditer(r'\bL\(\s*', text):
        start = m.end()
        if not text.startswith('"', start) or text.startswith('"""', start):
            continue
        end = skip_string(text, start)
        if end < 0 or not re.match(r'\s*[,)]', text[end:]):
            continue
        yield text[start + 1:end - 1]


def key_of(literal):
    out, i, n = [], 0, len(literal)
    while i < n:
        c = literal[i]
        if c == "\\" and i + 1 < n:
            nxt = literal[i + 1]
            if nxt == "(":
                out.append("%@")
                i = skip_interpolation(literal, i + 2)
                continue
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(nxt, nxt))
            i += 2
            continue
        out.append("%%" if c == "%" else c)
        i += 1
    return "".join(out)

# Self-test on every run: interpolations may contain strings and parentheses (an earlier
# pattern silently dropped such strings from the catalogs).
_sample = 'Text(L("\\(name ?? "") asks for \\(short(m)) (now)")) x L("Plain %"), L("a \\("q)") b")'
assert [key_of(x) for x in literals(_sample)] == ["%@ asks for %@ (now)", "Plain %%", "a %@ b"], [key_of(x) for x in literals(_sample)]

stale = False
for src, catalog in modules:
    keys = set()
    for root, _, files in os.walk(src):
        for f in files:
            if f.endswith(".swift"):
                text = open(os.path.join(root, f), encoding="utf-8").read()
                keys.update(key_of(m) for m in literals(text))
    existing = {"sourceLanguage": "en", "strings": {}, "version": "1.0"}
    if os.path.exists(catalog):
        existing = json.load(open(catalog, encoding="utf-8"))
    elif not keys:
        continue
    strings = {}
    for k, v in existing.get("strings", {}).items():
        if k in keys or v.get("extractionState") == "manual":
            strings[k] = v
    for k in keys:
        strings.setdefault(k, {})
    result = dict(existing, strings=dict(sorted(strings.items())))
    rendered = json.dumps(result, indent=2, ensure_ascii=False, separators=(",", " : ")) + "\n"
    current = open(catalog, encoding="utf-8").read() if os.path.exists(catalog) else None
    if rendered != current:
        if check:
            print("out of date:", catalog)
            stale = True
        else:
            os.makedirs(os.path.dirname(catalog), exist_ok=True)
            open(catalog, "w", encoding="utf-8").write(rendered)
            print("updated", catalog, "(%d strings)" % len(strings))
if check and stale:
    print("Run ./scripts/ios-strings.sh")
    sys.exit(1)
PY
