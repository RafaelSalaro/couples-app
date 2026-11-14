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

call = re.compile(r'\bL\(\s*"((?:[^"\\]|\\.)*)"\s*[,)]')

def key_of(literal):
    out, i, n = [], 0, len(literal)
    while i < n:
        c = literal[i]
        if c == "\\" and i + 1 < n:
            nxt = literal[i + 1]
            if nxt == "(":
                depth, j = 1, i + 2
                while j < n and depth:
                    depth += {"(": 1, ")": -1}.get(literal[j], 0)
                    j += 1
                out.append("%@")
                i = j
                continue
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(nxt, nxt))
            i += 2
            continue
        out.append("%%" if c == "%" else c)
        i += 1
    return "".join(out)

stale = False
for src, catalog in modules:
    keys = set()
    for root, _, files in os.walk(src):
        for f in files:
            if f.endswith(".swift"):
                text = open(os.path.join(root, f), encoding="utf-8").read()
                keys.update(key_of(m) for m in call.findall(text))
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
