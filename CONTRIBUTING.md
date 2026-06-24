# AI

MacPacker accepts AI-assisted contributions. Pull requests where AI is the primary author must follow the [AI Contribution Guidelines](AI_CONTRIBUTING.md): disclose AI involvement, open the PR from a human account, and include verification evidence that the change works. 

Using AI as a coding buddy for minor edits and completions, where you are clearly the primary author, is fine and needs no special disclosure.

# Localization

Localization (translation of all strings to specific languages) is done using [POEditor](poeditor.com).

## Update Language

- 

## Push new texts for translation

- Open the [project import](https://poeditor.com/projects/import?id=807352) in POEditor
- Import the `Localizable.xcstrings` (this will just add new terms)
- Open the [English import](https://poeditor.com/projects/import_translations?id_language=43&id=807352) in POEditor
- Import the `Localizable.xcstrings` again (this will add new translations for the English reference language)

(Alternatively, one could also import all languages when importing the terms. There is a setting for that.)

## Note

POEditor only supports standard string catalog key value pairs. Symbols are not supported yet!