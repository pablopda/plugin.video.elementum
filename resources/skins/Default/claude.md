# Default

## Purpose

Default skin that works across all Kodi themes, containing dialog definitions and media assets.

## Structure

```
Default/
├── 720p/             # Dialog XML definitions
│   ├── DialogSelectLarge.xml        # Stream selection (modern)
│   ├── DialogSelectLargeLegacy.xml  # Stream selection (legacy)
│   ├── DialogInsert.xml             # Torrent insert (modern)
│   └── DialogInsertLegacy.xml       # Torrent insert (legacy)
└── media/            # UI graphic assets
    ├── AddonWindow/  # Window backgrounds
    ├── Button/       # Button graphics
    ├── List/         # List item styling
    └── Scrollbar/    # Scrollbar graphics
```

## Dialog Features

### Stream Selection Dialog
- List of available streams/torrents
- Quality indicators (resolution, codec)
- Source icons
- Seed/peer information
- Multi-cloud indicator

### Torrent Insert Dialog
- Text input for magnet links
- Search functionality
- Results display
- Close button

## Modern vs Legacy

- **Modern** - For Kodi 17+ (Krypton)
- **Legacy** - For Kodi 16 (Jarvis)

## Notes

- Dialogs inherit from xbmcgui.WindowXMLDialog
- Use Kodi's standard control IDs
- Support navigation (up/down/left/right)
