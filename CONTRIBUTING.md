# Localization

Localization (translation of all strings to specific languages) is done using [POEditor](poeditor.com).

## Update Language

- 

## Push new texts for translation

- Open the [project import](https://poeditor.com/projects/import?id=807352) in POEditor
- Import the `Localizable.xcstrings` (this will just add new terms)
- Open the [English import](https://poeditor.com/projects/import_translations?id_language=43&id=807352) in POEditor
- Import the `Localizable.xcstrings` again (this will add new translations for the English reference language)

## Note

POEditor only supports standard string catalog key value pairs. Symbols are not supported yet!