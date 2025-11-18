# language

## Purpose

Localization files for 20 supported languages using GNU gettext format.

## Structure

```
language/
├── messages.pot          # Translation template (source)
├── English/
│   └── strings.po        # Source strings
├── Spanish/
│   └── strings.po
├── Russian/
│   └── strings.po
├── German/
│   └── strings.po
├── French/
│   └── strings.po
└── [16 more languages]/
```

## Supported Languages

1. Czech
2. Croatian
3. Dutch
4. English (source)
5. Finnish
6. French
7. German
8. Greek
9. Hebrew
10. Hungarian
11. Italian
12. Polish
13. Portuguese
14. Romanian
15. Russian
16. Slovak
17. Spanish
18. Swedish
19. Turkish
20. Ukrainian

## File Format

GNU gettext PO format:
```po
msgctxt "#30001"
msgid "Movies"
msgstr "Películas"
```

## String ID Ranges

- **30000-30099** - General UI strings
- **30100-30199** - Menu items
- **30200-30299** - Settings
- **30300-30399** - Library
- **30400-30499** - Dialogs
- **30500+** - Additional strings

## Usage in Code

```python
from elementum.util import getLocalizedString
label = getLocalizedString(30001)  # Returns "Movies" or translated
```

## Translation Workflow

1. Add strings to `English/strings.po`
2. Update `messages.pot` template
3. Run `scripts/xgettext_merge.sh`
4. Translators update their language files
5. Validate with `scripts/xgettext.sh`

## Notes

- English is the source language
- Keep msgctxt as "#XXXXX" format
- Use consistent terminology
- Test UI with long translations
