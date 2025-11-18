# scripts

## Purpose

Build automation, translation management, and release scripts for the plugin.

## Files

### Translation Scripts

- **xgettext.sh** - Validates translation files
  - Checks string IDs are properly formatted
  - Ensures translations are complete

- **xgettext_get_available_ids.sh** - Lists available string IDs
  - Helps translators find unused IDs
  - Prevents ID conflicts

- **xgettext_merge.sh** - Merges translation updates
  - Combines new strings with existing translations
  - Maintains translation memory

- **xgettext_remove_old_messages.sh** - Cleans obsolete strings
  - Removes unused translations
  - Keeps language files clean

### Build Scripts

- **changelog.sh** - Generates changelog from git history
  - Formats commit messages
  - Creates whatsnew.txt content

## Usage

```bash
# Validate translations
./scripts/xgettext.sh

# Generate changelog
./scripts/changelog.sh

# Get available translation IDs
./scripts/xgettext_get_available_ids.sh
```

## Translation Workflow

1. Add new strings to code with IDs (30000-30999)
2. Update `resources/language/English/strings.po`
3. Run `xgettext_merge.sh` to propagate to other languages
4. Translators update their language files
5. Run `xgettext.sh` to validate

## Notes

- String IDs use range 30000-30999
- GNU gettext format (.po files)
- English is the source language
- 20 languages currently supported
