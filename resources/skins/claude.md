# skins

## Purpose

Kodi WindowXML dialog definitions for custom UI elements.

## Structure

```
skins/
└── Default/
    ├── 720p/           # Dialog XML files
    └── media/          # UI graphics
```

## Usage

Kodi skins define custom dialogs using XML. The "Default" skin provides dialogs that work across all Kodi skins.

## Dialog Types

1. **Stream Selection** - Choose from available torrents
2. **Torrent Insert** - Manual magnet/torrent input

## Resolution Support

Currently only 720p resolution is defined. Kodi scales these for other resolutions.

## Notes

- Uses Kodi's WindowXML system
- Compatible with Kodi 16+ (Jarvis)
- Legacy versions provided for older Kodi
