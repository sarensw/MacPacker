#!/usr/bin/env bash
#
# Installs the 7-Zip command line the Swift tests check their archives against.
#
# The tests write zip and 7z archives with 7-Zip and then have an outside reader
# confirm what landed on disk. `7zz` — Homebrew's `sevenzip` formula, the current
# official CLI — is that reader. GitHub's macOS images ship only p7zip 17.05 as
# `7z`, a 2021 fork, so without this step the runner checks against code years
# behind what MacPacker embeds.
#
# Runs from the `pre-build-script` hook of LeanBytes/workflows-macos. Idempotent,
# so it costs nothing on a runner that already has it.
set -euo pipefail

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1

if command -v 7zz > /dev/null 2>&1; then
    echo "7zz is already installed: $(command -v 7zz)"
else
    echo "Installing 7-Zip (Homebrew formula 'sevenzip')…"
    brew install --quiet sevenzip
fi

# Says which build verified the run, in the log where the tests are.
7zz i | head -2
