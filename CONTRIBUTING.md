# Pull Requests

Small fixes: just open a pull request. For larger changes, open an issue first so we can discuss the approach before you spend time on it — MacPacker is still early and some breaking changes are ahead.

If your PR addresses an existing issue, reference it in the description (`Closes #123`).

[AGENTS.md](AGENTS.md) documents how to build and test the project, and the repository rules that apply to every change (changelog entries, vendored dependencies, versioning). Worth reading before the first PR, whether or not you use an AI tool.

# AI

MacPacker accepts AI-assisted contributions. Pull requests where AI is the primary author must follow the [AI Contribution Guidelines](AI_CONTRIBUTING.md): disclose AI involvement, open the PR from a human account, and include verification evidence that the change works. 

Using AI as a coding buddy for minor edits and completions, where you are clearly the primary author, is fine and needs no special disclosure.

# Localization

Localization (translation of all strings to specific languages) is done using [POEditor](poeditor.com). Add new strings to `Localizable.xcstrings` in English only — the other languages come back from POEditor.

## Push new texts for translation

- Open the [project import](https://poeditor.com/projects/import?id=807352) in POEditor
- Import the `Localizable.xcstrings` (this will just add new terms)
- Open the [English import](https://poeditor.com/projects/import_translations?id_language=43&id=807352) in POEditor
- Import the `Localizable.xcstrings` again (this will add new translations for the English reference language)

(Alternatively, one could also import all languages when importing the terms. There is a setting for that.)

## Note

POEditor only supports standard string catalog key value pairs. Symbols are not supported yet!