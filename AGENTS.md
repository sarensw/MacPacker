# Agent Guide

Working instructions for AI coding agents in this repository. Humans: see
[CONTRIBUTING.md](CONTRIBUTING.md) and [AI_CONTRIBUTING.md](AI_CONTRIBUTING.md).

MacPacker is a sandboxed SwiftUI archive manager for macOS, with a Finder
extension and a Quick Look extension. Most logic lives in the `Modules` Swift
package; the Xcode project is the app shell.

## Build & test

```bash
git submodule update --init --recursive   # required — the build fails without it
swift test --package-path Modules         # unit tests (what CI runs on every PR)
open MacPacker.xcodeproj                  # app build, Cmd+R
```

The `MacPacker.xctestplan` scheme runs the XCUITest target only; it is not part
of PR CI.

## Rules

**Never set the version.** `Config/Version.xcconfig` stays at
`MARKETING_VERSION = 0.0.0-dev`. That is the permanent local value, not a
placeholder. Never edit `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` in any
branch for any reason, including when a change is "for version X". Naming a
target version in a changelog entry or commit message is fine; changing the
build setting is not. CI sets the real version at tag time.

**Vendored dependencies are pristine submodules.** `Modules/Sources/CSevenZip/vendor/7zip`
and friends track upstream unmodified. Fixes belong in the bridging layer or in
MacPacker code, never in vendored sources.

**Localization goes through POEditor, not by hand.** Do not add translations to
`Localizable.xcstrings` directly — add the English key and leave the rest.
See [CONTRIBUTING.md](CONTRIBUTING.md#localization). The changelog is the one
exception (below).

**Bug fixes start with a failing test.** Reproduce in a test in
`Modules/Tests/CoreTests`, then fix. Archive fixtures live in the
`MacPacker-TestArchives` submodule.

**Link the issue, if there is one.** When the change addresses a reported issue,
reference it in the PR body (`Closes #123`). The changelog entry's `issues` field
is always filled — see below. No need to open an issue just to have one to link.

## Changelog

User-visible changes need an entry in `Config/products/macpacker.json` under
`changelog.versions[]`. There is no separate CHANGELOG file. CI validates at tag
time that the released version exists here.

```jsonc
{
  "version": "0.20.0",
  "items": [
    {
      "type": "fix",              // feat | fix | core | lang
      "title": { "en": "…", "de": "…", /* all 14 languages */ },
      "issues": ["170"]           // issue number, or this PR's own number
    }
  ]
}
```

Add to the topmost unreleased `version` block, or open a new one if the last
block is already released.

**`issues` always points at something.** Prefer the issue the change addresses —
readers land on the report in a user's own words. If there is no issue, use this
pull request's own number instead; GitHub resolves issue and PR numbers from the
same namespace, so either link works.

That means the number does not exist until the PR is opened. Sequence:

1. Write the entry with everything except `issues`, and open the PR.
2. Add `"issues": ["<pr-number>"]` and push again.

Never guess a number. An invented one resolves to somebody else's issue. Leave
the field out until the real number exists, and never write an empty `[]`.

**Writing the title.** Customer-facing and short. Describe what changed for the
user, not how it was implemented. Aim for under ~50 characters.

- Yes: `Extract-to-folder ignores extension case`
- No: `Normalize archive extension casing in ExtractDestinationResolver`

**Translations.** Fill in all 14 languages: `en`, `de`, `es-MX`, `fa`, `fr`,
`it`, `ja`, `ko`, `nl`, `pl`, `pt-BR`, `ru`, `uk`, `zh-Hans`. Translate the
meaning for a user of that language, not the English wording literally. Keep
each one roughly as short as the English. Format names (`zip`, `7z`, `apk`),
`MacPacker`, and macOS feature names (`Finder`, `Quick Look`) stay untranslated.

Get the English wording approved before writing out all 14 languages.

## Conventions

- Commit and PR titles: `feat:`, `fix:`, `core:`, `lang:`, `docs:`, `ci:`,
  `refactor:` — same set as the changelog `type` field.
- Do not add `Co-Authored-By` trailers for AI tools.
- Do not commit `Config/SigningOverride.xcconfig` (gitignored, local only).
