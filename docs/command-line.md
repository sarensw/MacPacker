# Command-line archives

Direct-download builds include a command-line executable inside MacPacker.app.
It does not open the graphical app or require a background service.

```sh
"/Applications/MacPacker.app/Contents/MacOS/macpacker-cli" --help
```

For a shorter command, add this alias to your shell configuration:

```sh
alias macpacker='/Applications/MacPacker.app/Contents/MacOS/macpacker-cli'
```

Examples:

```sh
macpacker list files.rar
macpacker extract files.part03.rar --output extracted
macpacker extract files.r01 --output extracted
macpacker create backup.7z Documents --volume-size 100m --ask-password --encrypt-names
macpacker create backup.tar Documents
macpacker update backup.7z another-file.txt --ask-password
macpacker rename backup.7z old-name.txt new-name.txt --ask-password
macpacker delete backup.7z unwanted.txt --ask-password
```

All parts must be present in the same directory. Opening a later RAR/7z/TAR
part resolves the first part by name; the engine reads volumes directly, without
first concatenating them into a temporary archive. File sizes and solid compression
still affect speed. A missing/corrupt volume reports failure.

New archive paths and extraction directories must not already exist. Use `--`
before filenames starting with a dash. `--password-stdin` reads one line from
standard input for scripts; never put passwords in command arguments. Exit status
is 0 on success, 1 on an operation failure, and 2 for invalid arguments.

Output formats are 7z, ZIP and TAR. TAR has no encryption/compression; choose 7z
for AES-256, encrypted filenames and split volumes. Edits replace the original
archive after writing the updated contents; split archives cannot be edited in
place. RAR/RAR5 extraction is built in and free. RAR writing is not implemented:
7-Zip cannot create RAR, and a separate RARLAB writer has its own licence.

The GUI's **Move archives to Trash after successful extraction** preference does
not apply to CLI commands. The CLI always preserves its source archives.

Developers can also run `swift run --package-path Modules macpacker --help`.
The App Store target does not bundle the CLI.
