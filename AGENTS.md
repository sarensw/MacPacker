# Agent Guide

Instructions for AI coding agents. Humans: [CONTRIBUTING.md](CONTRIBUTING.md),
[AI_CONTRIBUTING.md](AI_CONTRIBUTING.md).

App logic lives in the `Modules` Swift package. The Xcode project is the shell,
plus a Finder and a Quick Look extension.

## Build & test

```bash
git submodule update --init --recursive   # required — the build fails without it
swift test --package-path Modules         # unit tests; what PR CI runs
xcodebuild -scheme MacPacker build        # app build; also extracts new UI strings
```

`MacPacker.xctestplan` runs the XCUITest target only, outside PR CI.

## Rules

**Never set the version.** `Config/Version.xcconfig` stays at
`MARKETING_VERSION = 0.0.0-dev` permanently; CI sets the real version at tag
time. Never edit `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` in any branch,
including "for version X". Naming a version in a changelog entry or commit
message is fine.

**Vendored submodules stay pristine.** `Modules/Sources/CSevenZip/vendor/7zip`
tracks upstream unmodified. Fix in the bridging layer or in MacPacker code.

**New UI strings: commit the catalog, English only.** Xcode extracts strings
into the `.xcstrings` catalogs when the app target builds, so `swift test` alone
leaves them out. Build once, then commit whichever catalog changed
(`MacPacker/`, `FinderExtension/`, `Modules/Sources/ArchivePreviewUI/`). Fill in
English only — the other languages come back from POEditor. Without the catalog
entry the string can never be translated.

**Bug fixes start with a failing test** in `Modules/Tests/CoreTests`.

**Archive fixtures never go in this repository.** They live in the
`MacPacker-TestArchives` submodule, a permanent regression corpus: each archive
is a real file from a real tool, kept so a later engine change cannot silently
break the quirk it covers. Do not synthesize an equivalent archive in the test —
the quirk is usually exactly what a synthetic archive lacks.

Adding one means landing the archive in MacPacker-TestArchives first, then
bumping the submodule pointer here. Outside contributors cannot push there:
attach the archive to the PR and let the maintainer place it. Never contribute
an archive containing third-party or personal content.

**Link the issue when one exists** in the PR body (`Closes #123`). Do not open
an issue solely to have something to link.

## Changelog

User-visible changes need an entry in `Config/products/macpacker.json` under
`changelog.versions[]`. There is no separate CHANGELOG file.

```jsonc
{
  "version": "0.20.0",
  "items": [
    {
      "type": "fix",              // feat | fix | core | lang
      "title": { "en": "…", "de": "…", /* every language in the file */ },
      "issues": ["170"]           // the issue, or this PR's own number
    }
  ]
}
```

**Do not decide version numbers.** Versions are listed newest first. Add the
item to the first block, unless that version is already tagged (`git tag --list
"v0.20.0"` returns something — beta tags do not count). If it is, the next
number is the maintainer's call: still write the full item, but put it in the PR
body instead of the file, and say the release needs a new block.

**`issues` always points at something.** Prefer the issue, so readers land on
the report in a user's own words; otherwise use this PR's own number, which
shares GitHub's numbering. That number exists only once the PR is open, so add
it in a second push. Never guess a number, and never write an empty `[]`.

**Titles: customer-facing and short.** What changed for the user, not how it was
built. Under ~50 characters.

- Yes: `Extract-to-folder ignores extension case`
- No: `Normalize archive extension casing in ExtractDestinationResolver`

**Translate into every language already present in the file** — match that set,
not a fixed list. Translate the meaning rather than the English wording, and
keep each roughly as short. `MacPacker`, format names (`zip`, `7z`) and macOS
feature names (`Finder`, `Quick Look`) stay untranslated. Get the English
approved before writing the rest.

## Conventions

- Commit and PR titles: `feat:`, `fix:`, `core:`, `lang:`, `docs:`, `ci:`,
  `refactor:` — the changelog `type` set.
- No `Co-Authored-By` trailers for AI tools.
- Never commit `Config/SigningOverride.xcconfig` (gitignored).
