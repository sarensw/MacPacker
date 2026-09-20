#!/bin/bash
# ── Architecture guard ───────────────────────────────────────────────────────
# MacPacker ships universal: every executable in the bundle needs both slices.
#
#   arm64  — macOS 27 is the last release that runs Intel-only apps under
#            Rosetta on Apple silicon. A binary without arm64 works today and
#            stops working on macOS 28, on almost every Mac in use.
#   x86_64 — Intel Macs cap out at macOS 26, but they are supported until the
#            deployment target passes it. A binary without x86_64 is broken on
#            them right now.
#
# Code that is *linked* cannot regress unnoticed: a dependency missing either
# slice fails the link and the build goes red. The gap this closes is code that
# is only *copied* into the bundle — helper tools, XPC services and nested apps
# inside a binary dependency (Sparkle contributes four). Every dependency is a
# source package today, so those are built from our own sources with our own
# ARCHS; this guards the day one of them becomes a binaryTarget or an
# .xcframework, where the slices are upstream's choice and nothing else looks.
#
# Usage:
#   scripts/check-architectures.sh [--arm64-only] <path> [<path> …]
#
#   # a Release bundle — universal, both slices required
#   scripts/check-architectures.sh build/Build/Products/Release/MacPacker.app
#
#   # a local Debug bundle — arm64 only, ONLY_ACTIVE_ARCH drops x86_64
#   scripts/check-architectures.sh --arm64-only build-debug/…/MacPacker.app
#
# When the deployment target reaches macOS 27 no Intel Mac can run MacPacker at
# all, and the x86_64 half of this check should go.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

require_x86_64=1
if [ "${1:-}" = "--arm64-only" ]; then
    require_x86_64=0
    shift
fi

if [ "$#" -eq 0 ]; then
    echo "usage: $(basename "$0") [--arm64-only] <path> [<path> …]" >&2
    exit 2
fi

# Same reason as the per-file sanitising below, for the paths we were handed.
safe_args=${*//$'\n'/?}

if [ "$require_x86_64" -eq 1 ]; then
    expected="an arm64 and an x86_64 slice"
else
    expected="an arm64 slice"
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
        # A macOS filename may hold a newline, and a log line starting with "::"
        # is a GitHub Actions workflow command — so an unsanitised path out of a
        # fork's bundle could forge one. "|" is the field separator below.
        rel=${rel//$'\n'/?}
        rel=${rel//|/?}
        printf '%-24s %s\n' "$archs" "$rel" >>"$table"

        missing=""
        case " $archs " in
            *" arm64 "* | *" arm64e "*) ;;
            *) missing="arm64, so this needs Rosetta and dies on macOS 28" ;;
        esac

        if [ "$require_x86_64" -eq 1 ]; then
            case " $archs " in
                *" x86_64 "*) ;;
                *) missing="${missing:+$missing; missing }x86_64, so this is already broken on Intel Macs" ;;
            esac
        fi

        if [ -n "$missing" ]; then
            offenders="${offenders}${rel}|${missing}|${archs}"$'\n'
            offender_count=$((offender_count + 1))
        fi
    done < <(find "$root" -type f -print0)
done

sort -k2 "$table"
echo

if [ "$checked" -eq 0 ]; then
    echo "::error::no Mach-O files found under $safe_args — check the path" >&2
    exit 1
fi

if [ "$offender_count" -gt 0 ]; then
    printf '%s' "$offenders" | while IFS='|' read -r rel missing archs; do
        echo "::error::missing $missing: $rel ($archs)"
    done
    echo "$checked Mach-O files checked, $offender_count without $expected." >&2
    exit 1
fi

echo "$checked Mach-O files checked, every one has $expected."
