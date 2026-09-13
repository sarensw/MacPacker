#!/bin/bash
# ── Architecture guard ───────────────────────────────────────────────────────
# macOS 27 is the last release that runs Intel-only apps under Rosetta on Apple
# silicon, so every executable MacPacker ships needs an arm64 slice.
#
# Code that is *linked* cannot regress unnoticed: a dependency without arm64
# fails the link and the build goes red. The gap this closes is code that is
# only *copied* into the bundle — helper tools, XPC services and nested apps
# inside a binary dependency. Sparkle alone contributes four of those
# (Autoupdate, Updater.app, Downloader.xpc, Installer.xpc). Nothing examines
# their slices today, so a dependency update could swap in an Intel-only build
# and ship it.
#
# Requires an arm64 slice rather than a universal binary, so it holds for a
# local Debug build (arm64 only, ONLY_ACTIVE_ARCH) as well as for Release.
#
# Usage:
#   scripts/check-architectures.sh <path> [<path> …]
#
#   # a built app bundle
#   scripts/check-architectures.sh build/Build/Products/Release/MacPacker.app
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

if [ "$#" -eq 0 ]; then
    echo "usage: $(basename "$0") <path> [<path> …]" >&2
    exit 2
fi

table=$(mktemp)
trap 'rm -f "$table"' EXIT

checked=0
offenders=""
offender_count=0

for root in "$@"; do
    root="${root%/}"
    if [ ! -e "$root" ]; then
        echo "::error::$root does not exist" >&2
        exit 1
    fi

    # Paths are reported relative to the parent, so the bundle name stays in.
    base=$(dirname "$root")

    # -type f skips the symlinks a framework uses for its Versions/Current
    # layout, which would otherwise report the same binary several times.
    while IFS= read -r -d '' file; do
        # The only Mach-O test that needs no parsing: lipo fails on anything
        # else. Thin binaries report their one slice, fat binaries all of them.
        archs=$(lipo -archs "$file" 2>/dev/null) || continue

        checked=$((checked + 1))
        rel="${file#"$base"/}"
        printf '%-24s %s\n' "$archs" "$rel" >>"$table"

        case " $archs " in
            *" arm64 "* | *" arm64e "*) ;;
            *)
                offenders="${offenders}${rel} (${archs})"$'\n'
                offender_count=$((offender_count + 1))
                ;;
        esac
    done < <(find "$root" -type f -print0)
done

sort -k2 "$table"
echo

if [ "$checked" -eq 0 ]; then
    echo "::error::no Mach-O files found under $* — check the path" >&2
    exit 1
fi

if [ "$offender_count" -gt 0 ]; then
    printf '%s' "$offenders" | while IFS= read -r line; do
        echo "::error::no arm64 slice, so this needs Rosetta: $line"
    done
    echo "$checked Mach-O files checked, $offender_count without an arm64 slice." >&2
    exit 1
fi

echo "$checked Mach-O files checked, every one has an arm64 slice."
