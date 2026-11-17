#!/bin/bash
# ── Restore manual extraction state ──────────────────────────────────────────
# POEditor's export doesn't know about Xcode's `extractionState` field and
# drops it from every entry on the way out. Without it, Xcode won't generate a
# `.symbolName` for a key that doesn't match a literal string found by
# scanning source — which is every key here, since they're all hand-renamed.
# Losing the field breaks symbol generation catalog-wide: dozens of unrelated
# files fail to compile at once, even though every key is still present.
#
# It also writes the catalog back with its keys sorted, as on main. POEditor
# exports them in its own order, so without this every download shows up as
# thousands of moved lines, even when it carries the field already.
#
# And it fills plural forms POEditor exports empty. An untranslated plural
# comes out with English in `one` and "" in `few`, `many` and `other`, so the
# app would show a blank label for any count but one. Each empty form gets the
# language's own `other`, else its translated `one` (right where nouns don't
# change after a number, readable where they do), else the English `other`.
#
# Run this after every POEditor download, before building:
#   scripts/restore-manual-extraction-state.sh
#
# Safe to re-run: entries that already carry the field are left untouched.
set -euo pipefail

CATALOG="${1:-MacPacker/Localizable.xcstrings}"

if [[ ! -f "$CATALOG" ]]; then
    echo "error: $CATALOG not found" >&2
    exit 1
fi

python3 - "$CATALOG" <<'PYEOF'
import json
import sys

path = sys.argv[1]

with open(path, encoding="utf-8") as f:
    data = json.load(f)

fixed = 0
already = 0
for entry in data["strings"].values():
    if "extractionState" not in entry:
        entry["extractionState"] = "manual"
        fixed += 1
    else:
        already += 1

def plural_value(forms, name):
    return ((forms.get(name) or {}).get("stringUnit") or {}).get("value") or ""

filled = 0
for entry in data["strings"].values():
    localizations = entry.get("localizations", {})
    english = (localizations.get("en", {}).get("variations") or {}).get("plural") or {}
    for language, localization in localizations.items():
        forms = (localization.get("variations") or {}).get("plural")
        if language == "en" or not forms:
            continue
        own_one = plural_value(forms, "one")
        fallback = (plural_value(forms, "other")
                    or (own_one if own_one != plural_value(english, "one") else "")
                    or plural_value(english, "other"))
        for form in forms.values():
            unit = form.get("stringUnit")
            if unit is not None and not unit.get("value") and fallback:
                unit["value"] = fallback
                filled += 1

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True, ensure_ascii=False)

total = len(data["strings"])
print(f"{path}: restored extractionState on {fixed} entr{'y' if fixed == 1 else 'ies'} "
      f"({already} already had it, {total} total), filled {filled} empty plural form"
      f"{'' if filled == 1 else 's'}")
PYEOF
