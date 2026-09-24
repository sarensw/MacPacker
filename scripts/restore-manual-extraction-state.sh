#!/bin/bash
# ── Restore manual extraction state ──────────────────────────────────────────
# POEditor's export doesn't know about Xcode's `extractionState` field and
# drops it from every entry on the way out. Without it, Xcode won't generate a
# `.symbolName` for a key that doesn't match a literal string found by
# scanning source — which is every key here, since they're all hand-renamed.
# Losing the field breaks symbol generation catalog-wide: dozens of unrelated
# files fail to compile at once, even though every key is still present.
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

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True, ensure_ascii=False)

total = len(data["strings"])
print(f"{path}: restored extractionState on {fixed} entr{'y' if fixed == 1 else 'ies'} "
      f"({already} already had it, {total} total)")
PYEOF
