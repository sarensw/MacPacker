# Agent Guide

Instructions for AI coding agents. Humans: [CONTRIBUTING.md](CONTRIBUTING.md),
[AI_CONTRIBUTING.md](AI_CONTRIBUTING.md).

App logic is in the `Modules` Swift package; the Xcode project is the shell plus
a Finder and a Quick Look extension.

## Build & test

```bash
git submodule update --init --recursive   # required — the build fails without it
swift test --package-path Modules         # unit tests; what PR CI runs
xcodebuild -scheme MacPacker build        # app build; also extracts new UI strings
```

`MacPacker.xctestplan` runs the XCUITest target only, outside PR CI.

## Rules

**Never set the version.** `Config/Version.xcconfig` stays at
`MARKETING_VERSION = 0.0.0-dev`; CI sets the real one at tag time. Never edit
`MARKETING_VERSION` or `CURRENT_PROJECT_VERSION`, in any branch, including "for
version X". Naming a version in a changelog entry or commit message is fine.

**Vendored submodules stay pristine.** `Modules/Sources/CSevenZip/vendor/7zip`
tracks upstream unmodified. Fix in the bridging layer or in MacPacker code.

**New UI strings: build, then commit the catalog.** Extraction runs on the app
target build, so `swift test` alone leaves new strings out and they never reach
POEditor. Commit whichever catalog changed (`MacPacker/`, `FinderExtension/`,
`Modules/Sources/ArchivePreviewUI/`) with the English value only; the other
languages come back from POEditor.

**Bug fixes start with a failing test** in `Modules/Tests/CoreTests`.

**Archive fixtures live in the `MacPacker-TestArchives` submodule**, never in
this repository. Do not synthesize a substitute in the test — the quirk under
fix is usually what a synthetic archive lacks. Order: PR the archive to
MacPacker-TestArchives, wait for merge, bump the submodule pointer here, then
the fix. Never contribute archives holding third-party or personal content.

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

**Never pick a version number.** Versions run newest first; add to the first
block unless it is already tagged (`git tag --list "v0.20.0"` — beta tags do not
count). If tagged, write the full item into the PR body instead and say a new
block is needed.

**`issues` is never empty.** Prefer the issue, so readers land on the report in
a user's own words; otherwise this PR's own number, which shares GitHub's
numbering. That number exists only after the PR is open — add it in a second
push. Never guess one.

**Titles: customer-facing, under ~50 characters.** What changed for the user,
not how it was built.

- Yes: `Extract-to-folder ignores extension case`
- No: `Normalize archive extension casing in ExtractDestinationResolver`

**Translate into every language already in the file**, not a fixed list.
Translate meaning, not wording; keep each roughly as short as the English.
`MacPacker`, format names (`zip`, `7z`) and macOS features (`Finder`,
`Quick Look`) stay untranslated. Get the English approved first.

## Conventions

- Commit and PR titles: `feat:`, `fix:`, `core:`, `lang:`, `docs:`, `ci:`,
  `refactor:` — the changelog `type` set.
- No `Co-Authored-By` trailers for AI tools.
- Never commit `Config/SigningOverride.xcconfig` (gitignored).
