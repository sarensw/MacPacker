#!/usr/bin/env python3
"""Build pinned static DAR dependencies for macOS; nothing installs outside .build."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / "Modules/.build/dar-dependencies"
MANIFEST = ROOT / "scripts/dar-dependencies.json"
SPECS = json.loads(MANIFEST.read_text())


def run(args, cwd, env=None):
    subprocess.run([str(x) for x in args], cwd=cwd, env=env, check=True)


def build(arch):
    prefix = WORK / arch / "installed"
    stamp = prefix / ".complete"
    identity = hashlib.sha256(MANIFEST.read_bytes() + Path(__file__).read_bytes()).hexdigest()
    if stamp.exists() and stamp.read_text() == identity:
        return prefix
    directory = WORK / arch
    if directory.exists():
        shutil.rmtree(directory)
    directory.mkdir(parents=True)
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    env = dict(os.environ)
    flags = f"-O2 -fPIC -arch {arch} -isysroot {sdk} -mmacosx-version-min=14.6"
    env.update(CC="clang", CXX="clang++", CFLAGS=flags, CXXFLAGS=flags,
               CPPFLAGS=f"-I{prefix}/include", LDFLAGS=f"-arch {arch} -isysroot {sdk} -mmacosx-version-min=14.6 -L{prefix}/lib",
               PKG_CONFIG_PATH=str(prefix / "lib/pkgconfig"), MACOSX_DEPLOYMENT_TARGET="14.6")
    for name in ["libgpg-error", "libgcrypt", "xz", "lz4", "zstd", "dar"]:
        spec = SPECS[name]
        archive = WORK / "downloads" / (name + ".tar")
        archive.parent.mkdir(exist_ok=True)
        if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != spec["sha256"]:
            run(["curl", "--fail", "--location", "--retry", "3", spec["url"], "-o", archive], WORK)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != spec["sha256"]:
            raise RuntimeError(f"Checksum mismatch: {name}")
        source = directory / name
        source.mkdir()
        run(["tar", "-xf", archive, "--strip-components=1", "-C", source], WORK)
        print(f"Building {name} for {arch}", flush=True)
        if name in ["lz4", "zstd"]:
            run(["make", "-C", "lib", "-j6", "lib" + name + ".a", "CC=clang", "CFLAGS=" + flags], source, env)
            (prefix / "lib").mkdir(parents=True, exist_ok=True)
            (prefix / "include").mkdir(exist_ok=True)
            shutil.copy2(source / "lib" / ("lib" + name + ".a"), prefix / "lib")
            for header in (source / "lib").glob("*.h"):
                shutil.copy2(header, prefix / "include")
        else:
            options = ["./configure", "--prefix=" + str(prefix), "--disable-shared", "--enable-static", "--disable-nls", "--disable-dependency-tracking", "--host=" + ("aarch64" if arch == "arm64" else "x86_64") + "-apple-darwin"]
            if name == "dar":
                # DAR 2.8.6 tests sizeof(off_t) by running a program, without a
                # cross-compile fallback. Compile the same assertion instead.
                # This works for both macOS architectures without Rosetta.
                configure = source / "configure"
                text = configure.read_text()
                start = text.rfind('if test "$cross_compiling" = yes', 0, text.index('off_t var = 0;'))
                end = text.index('# Checks for typedefs', start)
                probe = text[start:end]
                probe = probe.replace('if test "$cross_compiling" = yes', 'if false', 1)
                probe = probe.replace('ac_fn_cxx_try_run', 'ac_fn_cxx_try_compile')
                probe = probe.replace('off_t var = 0;', 'static_assert(sizeof(off_t) >= 8, "64-bit file offsets required"); off_t var = 0;')
                configure.write_text(text[:start] + probe + text[end:])
            if name == "libgpg-error": options += ["--disable-doc", "--disable-tests"]
            if name == "libgcrypt": options += ["--with-libgpg-error-prefix=" + str(prefix), "--disable-doc", "--disable-asm"]
            if name == "xz": options += ["--disable-xz", "--disable-xzdec", "--disable-lzmadec", "--disable-lzmainfo", "--disable-scripts", "--disable-doc", "--disable-tests"]
            if name == "dar": options += ["--disable-build-html", "--disable-dar-static", "--disable-python-binding", "--disable-liblzo2-linking", "--disable-libargon2-linking", "--disable-gpgme-linking", "--disable-librsync-linking", "--disable-libcurl-linking", "--disable-libssh-linking", "--disable-threadar", "--disable-librhash-linking", "--disable-linux-statx", "--enable-mode=64"]
            run(options, source, env)
            build_directory = source / "src/libdar" if name == "dar" else source
            run(["make", "-j6"], build_directory, env)
            run(["make", "install"], build_directory, env)
    stamp.write_text(identity)
    return prefix


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", action="append", choices=["arm64", "x86_64"])
    args = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    prefixes = [build(arch) for arch in (args.arch or ["arm64", "x86_64"])]
    output = WORK / "universal"
    output.mkdir(exist_ok=True)
    # Configure generates architecture-specific headers (notably gpg-error's
    # lock initializer). Keep each set and select it at compile time.
    include = output / "include"
    if include.exists():
        shutil.rmtree(include)
    for prefix in prefixes:
        arch = prefix.parent.name
        shutil.copytree(prefix / "include", include / arch)
        for header in (include / arch / "dar").glob("*"):
            if header.is_file():
                header.write_text(header.read_text().replace(str(prefix / "include/dar") + "/", ""))
    headers = set(path.relative_to(prefix / "include") for prefix in prefixes
                  for path in (prefix / "include").rglob("*") if path.is_file())
    for path in headers:
        wrapper = include / path
        wrapper.parent.mkdir(parents=True, exist_ok=True)
        lines = []
        for index, prefix in enumerate(prefixes):
            arch = prefix.parent.name
            macro = "__arm64__" if arch == "arm64" else "__x86_64__"
            lines += [("#if" if index == 0 else "#elif") + " defined(" + macro + ")",
                      '#include "' + str(Path(os.path.relpath(include / arch / path, wrapper.parent))) + '"']
        wrapper.write_text("\n".join(lines + ['#else', '#error DAR dependencies were not built for this architecture', '#endif', '']))
    (output / "lib").mkdir(exist_ok=True)
    for name in ["dar64", "gcrypt", "gpg-error", "lzma", "lz4", "zstd"]:
        libs = [p / "lib" / ("lib" + name + ".a") for p in prefixes]
        run(["lipo", "-create", *libs, "-output", output / "lib" / ("lib" + name + ".a")], ROOT)
    print("DAR dependencies ready:", output)


if __name__ == "__main__":
    main()
