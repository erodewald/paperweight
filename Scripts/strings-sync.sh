#!/usr/bin/env bash
# Merges the strings the compiler saw into the shared String Catalog.
#
#   Scripts/strings-sync.sh          rebuild the app target, update the catalog
#   Scripts/strings-sync.sh --check  same, but into a copy; fail if it differs
#                                    from the committed catalog (CI)
#
# Only the app target's .stringsdata is used: it compiles every view and every
# shared file. Feeding the widget's or monitor's would mark every shared key
# they don't compile as stale.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

CATALOG=Shared/Resources/Localizable.xcstrings
DERIVED=.build/strings-sync
TOOL="$(xcode-select -p)/usr/bin/xcstringstool"
MODE="${1:-sync}"

[ -d Paperweight.xcodeproj ] || xcodegen generate

sim=$(xcrun simctl list devices available \
      | grep -oE 'iPhone [A-Za-z0-9][A-Za-z0-9 ]*' | sed 's/ *$//' | head -1 || true)
[ -n "$sim" ] || { echo "No iPhone simulator available" >&2; exit 1; }

xcodebuild build \
  -project Paperweight.xcodeproj -scheme Paperweight \
  -destination "platform=iOS Simulator,name=$sim" \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO -quiet

files=()
while IFS= read -r f; do files+=("$f"); done < <(
  find "$DERIVED/Build/Intermediates.noindex" \
       -path "*/Debug-iphonesimulator/Paperweight.build/*" -name "*.stringsdata" | sort)
[ "${#files[@]}" -gt 0 ] || { echo "No .stringsdata found; is SWIFT_EMIT_LOC_STRINGS on?" >&2; exit 1; }

target="$CATALOG"
if [ "$MODE" = "--check" ]; then
  target="$(mktemp -d)/Localizable.xcstrings"
  cp "$CATALOG" "$target"
fi

"$TOOL" sync "$target" --stringsdata "${files[@]}"

# xcstringstool sync leaves freshly-added source-language content in state
# "new" wherever a human might plausibly want to confirm it — a plain
# stringUnit, or one nested under "variations" (plural/device/width) or
# "substitutions", at any depth. For the source language there is nothing to
# translate — it's the code's own text — so xcstringstool compile silently
# drops any entry that isn't "translated", and with nothing left to compile
# it emits no table at all (no en.lproj/Localizable.strings). Promote every
# "new" stringUnit under the source language to "translated", recursively,
# then re-sync so the file ends up in xcstringstool's own canonical
# formatting (the tool preserves the "translated" states we just set) —
# that keeps --check diffs meaningful.
promoted=$(python3 - "$target" <<'EOF'
import json, sys

path = sys.argv[1]

def promote(node):
    """Recursively promote every 'new' stringUnit state to 'translated',
    descending through variations/substitutions at any depth. Returns the
    number of promotions made."""
    count = 0
    if isinstance(node, dict):
        unit = node.get("stringUnit")
        if isinstance(unit, dict) and unit.get("state") == "new":
            unit["state"] = "translated"
            count += 1
        for value in node.values():
            count += promote(value)
    elif isinstance(node, list):
        for item in node:
            count += promote(item)
    return count

d = json.load(open(path, encoding="utf-8"))
source = d.get("sourceLanguage", "en")

promoted = 0
for entry in d["strings"].values():
    loc = entry.get("localizations", {}).get(source)
    if loc is not None:
        promoted += promote(loc)

with open(path, "w", encoding="utf-8") as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(promoted)
EOF
)

"$TOOL" sync "$target" --stringsdata "${files[@]}"

python3 - "$target" "$promoted" <<'EOF'
import json, sys

path = sys.argv[1]
promoted = sys.argv[2]

def find_new(node):
    """True if a 'new' stringUnit state remains anywhere below node."""
    if isinstance(node, dict):
        unit = node.get("stringUnit")
        if isinstance(unit, dict) and unit.get("state") == "new":
            return True
        return any(find_new(v) for v in node.values())
    if isinstance(node, list):
        return any(find_new(item) for item in node)
    return False

d = json.load(open(path, encoding="utf-8"))
source = d.get("sourceLanguage", "en")

offenders = [
    key for key, entry in d["strings"].items()
    if (loc := entry.get("localizations", {}).get(source)) is not None and find_new(loc)
]
if offenders:
    for key in offenders:
        print(f"::error::{key!r} still has a source-language 'new' state after promotion", file=sys.stderr)
    sys.exit(1)

stale = sorted(k for k, v in d["strings"].items() if v.get("extractionState") == "stale")
print(f"{len(d['strings'])} keys, {len(stale)} stale, {promoted} promoted to translated")
for k in stale: print(f"  stale: {k!r}")
EOF

if [ "$MODE" = "--check" ]; then
  if ! diff -u "$CATALOG" "$target"; then
    echo "::error::Localizable.xcstrings is out of date. Run Scripts/strings-sync.sh and commit." >&2
    exit 1
  fi
  echo "Catalog is in sync with the code."
fi
