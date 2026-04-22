#!/bin/bash
# ── Post-generate_appcast processing ─────────────────────────────────────────
# Injects changelog HTML into the <description> of the newly added appcast item
# and trims the feed to keep only the 3 most recent items.
#
# Required environment variables:
#   VERSION        — marketing version (e.g., 0.15.0)
#   APPCAST_PATH   — path to appcast.xml (modified in-place)
#   CHANGELOG_PATH — path to CHANGELOG.md
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

: "${VERSION:?VERSION is required}"
: "${APPCAST_PATH:?APPCAST_PATH is required}"
: "${CHANGELOG_PATH:?CHANGELOG_PATH is required}"

# ── Step 1: Parse CHANGELOG.md → HTML ───────────────────────────────────────
# Converts the full cumulative changelog to HTML matching the existing appcast
# format: <h2>vX.Y</h2> headers with <ul><li>...</li></ul> lists.

CHANGELOG_HTML=$(awk '
  BEGIN { in_list = 0 }
  /^#*[[:space:]]*v?[0-9]+\.[0-9]/ {
    if (in_list) { print "</ul>"; in_list = 0 }
    gsub(/\r/, "")
    ver = $0
    gsub(/^#*[[:space:]]*/, "", ver)
    if (ver !~ /^v/) ver = "v" ver
    print "<h2>" ver "</h2>"
    next
  }
  /^- / {
    if (!in_list) { print "<ul>"; in_list = 1 }
    entry = substr($0, 3)
    gsub(/\r/, "", entry)
    print "<li>" entry "</li>"
    next
  }
  /^[[:space:]]*$/ {
    if (in_list) { print "</ul>"; in_list = 0 }
    next
  }
  END { if (in_list) print "</ul>" }
' "$CHANGELOG_PATH")

if [ -z "$CHANGELOG_HTML" ]; then
  echo "::error::Failed to parse changelog from ${CHANGELOG_PATH}"
  exit 1
fi

# ── Step 2: Insert <description> into the new item ──────────────────────────
# generate_appcast does not create a <description> tag. We find the item whose
# <sparkle:shortVersionString> matches $VERSION and insert the description
# block before the <enclosure line of that item.

# Write the description block to a temp file to avoid issues with awk -v and
# special characters (backslashes, ampersands) in the changelog HTML.
DESCRIPTION_FILE=$(mktemp)
cat > "$DESCRIPTION_FILE" <<DESCEOF
            <description><![CDATA[
${CHANGELOG_HTML}
]]></description>
DESCEOF

awk -v version="$VERSION" -v desc_file="$DESCRIPTION_FILE" '
  BEGIN { found_item = 0; injected = 0 }
  /<item>/ { found_item = 0 }
  $0 ~ "<sparkle:shortVersionString>" version "</sparkle:shortVersionString>" {
    found_item = 1
  }
  found_item && !injected && /<enclosure / {
    while ((getline line < desc_file) > 0) print line
    close(desc_file)
    injected = 1
  }
  { print }
' "$APPCAST_PATH" > "${APPCAST_PATH}.tmp"
mv "${APPCAST_PATH}.tmp" "$APPCAST_PATH"
rm -f "$DESCRIPTION_FILE"

# Verify description was injected
if ! grep -q '<description>' "$APPCAST_PATH"; then
  echo "::error::Failed to inject description for version ${VERSION}"
  exit 1
fi

# ── Step 3: Trim to 3 most recent items ────────────────────────────────────
ITEM_COUNT=$(grep -c '<item>' "$APPCAST_PATH")
echo "Items before trim: ${ITEM_COUNT}"

while [ "$ITEM_COUNT" -gt 3 ]; do
  # Remove the last <item>...</item> block
  awk '
    BEGIN { last_start = 0; last_end = 0 }
    { lines[NR] = $0 }
    /<item>/  { last_start = NR }
    /<\/item>/ { last_end = NR }
    END {
      for (i = 1; i <= NR; i++) {
        if (i >= last_start && i <= last_end) continue
        print lines[i]
      }
    }
  ' "$APPCAST_PATH" > "${APPCAST_PATH}.tmp"
  mv "${APPCAST_PATH}.tmp" "$APPCAST_PATH"
  ITEM_COUNT=$(grep -c '<item>' "$APPCAST_PATH")
done

echo "Items after trim: ${ITEM_COUNT}"

echo "Appcast updated successfully"
echo "  Version:     ${VERSION}"
echo "  Items:       ${ITEM_COUNT}"
echo "  Appcast:     ${APPCAST_PATH}"
