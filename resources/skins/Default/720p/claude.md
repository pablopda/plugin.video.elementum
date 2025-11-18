# 720p

## Purpose

Kodi WindowXML dialog definitions at 720p resolution.

## Files

### DialogSelectLarge.xml
Modern stream selection dialog for Kodi 17+
- List control with stream items
- Icon support for sources
- Quality/resolution display
- Close button
- Window animations (zoom, fade)

### DialogSelectLargeLegacy.xml
Legacy stream selection for Kodi 16
- Similar to modern but with older control syntax
- Different animation definitions
- Compatible with Jarvis API

### DialogInsert.xml
Modern torrent/magnet insertion dialog
- Text input control
- Search button
- Results list
- Cancel/close actions

### DialogInsertLegacy.xml
Legacy insertion dialog for Kodi 16
- Older control definitions
- Jarvis-compatible

## Control IDs

Standard Kodi control IDs used:
- **5** - Close button
- **6** - List control
- **3** - Edit control (text input)
- **7** - Button controls

## Usage in Python

```python
from elementum.dialog_select import DialogSelect

dialog = DialogSelect("DialogSelectLarge.xml",
                      ADDON_PATH,
                      "Default", "720p",
                      listing=items)
dialog.doModal()
selected = dialog.selected
```

## Styling

- Background: Semi-transparent dark
- Text: White with shadow
- Icons: 40x40 pixels
- Animations: 200-300ms duration

## Notes

- Kodi automatically scales to other resolutions
- Test with different Kodi skins
- Navigation must be properly defined
