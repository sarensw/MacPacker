#!/bin/bash
#
# Regenerates the password-protected test archives in this folder.
#
# The archives are committed so the test suite has no external tool dependency;
# this script only needs to run when the matrix changes.
#
# Requires: 7zz (brew install sevenzip), zip (macOS built-in), rar (brew install rar).
#
set -euo pipefail

cd "$(dirname "$0")"

PW="password"
PW_UNICODE="pässwörd"
PW_SYMBOLS="p@ss w'ord\"\$x"
PW_LONG="$(printf 'a%.0s' {1..200})"

# --- payload ------------------------------------------------------------------
# Kept tiny and deterministic so tests can assert exact bytes. Stored (not
# deflated) where possible keeps the archives readable in a hex dump.
src="$(mktemp -d)"
trap 'rm -rf "$src"' EXIT

mkdir -p "$src/folder"
printf 'encrypted hello\n' > "$src/hello.txt"
printf 'nested secret\n' > "$src/folder/nested.txt"
printf 'public data\n' > "$src/public.txt"

rm -f ./*.zip ./*.7z ./*.rar

# --- zip: ZipCrypto (legacy PKWARE) -------------------------------------------
# What `zip -e`, Finder-adjacent tools and most "quick password" flows produce.
(cd "$src" && zip -q -r -P "$PW" zip_zipcrypto.zip hello.txt folder)
mv "$src/zip_zipcrypto.zip" .

# --- zip: WinZip AES ----------------------------------------------------------
# The modern default of 7-Zip/WinZip/Keka. AES needs the extra field 0x9901 and
# an HMAC check, so it fails differently from ZipCrypto on a wrong password.
(cd "$src" && 7zz a -tzip -mem=AES256 -p"$PW" -bso0 -bsp0 zip_aes256.zip hello.txt folder >/dev/null)
mv "$src/zip_aes256.zip" .
(cd "$src" && 7zz a -tzip -mem=AES128 -p"$PW" -bso0 -bsp0 zip_aes128.zip hello.txt folder >/dev/null)
mv "$src/zip_aes128.zip" .

# --- zip: only some entries encrypted -----------------------------------------
# public.txt is appended without a password, so listing and extracting the
# plain entry must work with no prompt at all.
cp zip_aes256.zip "$src/zip_mixed.zip"
(cd "$src" && zip -q zip_mixed.zip public.txt)
mv "$src/zip_mixed.zip" .

# --- zip: awkward passwords ---------------------------------------------------
# Non-ASCII exercises the bridge's UTF-8 -> UTF-16 password conversion. Written
# with `zip` because the 7zz CLI rejects non-ASCII -p arguments on macOS; both
# ZipCrypto and AES reach the conversion through CryptoGetTextPassword anyway.
(cd "$src" && zip -q -P "$PW_UNICODE" zip_unicode_pw.zip hello.txt)
mv "$src/zip_unicode_pw.zip" .
(cd "$src" && zip -q -P "$PW_LONG" zip_long_pw.zip hello.txt)
mv "$src/zip_long_pw.zip" .
(cd "$src" && 7zz a -tzip -mem=AES256 -p"$PW_SYMBOLS" -bso0 -bsp0 zip_symbol_pw.zip hello.txt >/dev/null)
mv "$src/zip_symbol_pw.zip" .

# --- zip: encrypted archive nested inside a plain one -------------------------
# Opening the inner archive extracts it first, so the password prompt has to
# survive one level of nesting.
cp zip_aes256.zip "$src/inner_encrypted.zip"
(cd "$src" && zip -q zip_nested_outer.zip inner_encrypted.zip public.txt)
mv "$src/zip_nested_outer.zip" .

# --- 7z -----------------------------------------------------------------------
(cd "$src" && 7zz a -t7z -p"$PW" -bso0 -bsp0 7z_aes256.7z hello.txt folder >/dev/null)
mv "$src/7z_aes256.7z" .
# -mhe=on encrypts the header too: the entry list itself needs the password,
# so loadArchive (not just extract) has to prompt.
(cd "$src" && 7zz a -t7z -p"$PW" -mhe=on -bso0 -bsp0 7z_header_encrypted.7z hello.txt folder >/dev/null)
mv "$src/7z_header_encrypted.7z" .
(cd "$src" && 7zz a -t7z -p"$PW_SYMBOLS" -bso0 -bsp0 7z_symbol_pw.7z hello.txt >/dev/null)
mv "$src/7z_symbol_pw.7z" .

# No RAR fixtures: nothing in the toolchain can *create* encrypted RAR. Both
# engines read RAR through the same password paths these zip/7z fixtures cover
# (7-Zip: CryptoGetTextPassword + SetOperationResult, XAD: error 15 retry), so
# the RAR gap is fixture coverage, not code coverage. See README.md.

ls -l
