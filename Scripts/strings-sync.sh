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

# xcstringstool sync leaves a multi-argument format string (e.g. "%@ %lld")
# in localizations.<sourceLanguage>.stringUnit.state = "new": Apple's tool
# wants a human to confirm the positional reordering before compiling it.
# But for the source language there is nothing to translate — it's the
# code's own text — so xcstringstool compile skips these, and with nothing
# else in the catalog needing an override, it emits no compiled table at all
# (no en.lproj/Localizable.strings). Promote the source language's own
# entries to "translated" immediately; this is a plain text substitution
# scoped to the sourceLanguage key, so the rest of the file's formatting is
# untouched, and other languages added later keep their own independent
# "new" state.
python3 - "$target" <<'EOF'
import json, re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
d = json.loads(text)
source = d.get("sourceLanguage", "en")

pattern = re.compile(
    r'("%s"\s*:\s*\{\s*"stringUnit"\s*:\s*\{\s*"state"\s*:\s*)"new"' % re.escape(source)
)
promoted = len(pattern.findall(text))
if promoted:
    text = pattern.sub(r'\1"translated"', text)
    open(path, "w", encoding="utf-8").write(text)
    d = json.loads(text)

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
