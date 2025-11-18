# resources

## Purpose

Main plugin resources including code, binaries, translations, UI assets, and web interface.

## Structure

```
resources/
├── bin/              # Platform-specific Elementumd binaries
├── img/              # UI icon graphics (45 PNGs)
├── language/         # Translations (20 languages)
├── screenshots/      # Marketing/documentation images
├── site-packages/    # Python code and dependencies
├── skins/            # Kodi dialog definitions
├── web/              # Compiled React web UI
├── web-src/          # React source code
└── settings.xml      # Plugin settings configuration
```

## Key Files

### settings.xml

Plugin settings configuration (850+ lines) with categories:
- **General Settings** (30000) - Startup, platform, playback
- **Download Settings** - Paths, storage, caching
- **Library Settings** (30326) - Kodi library integration
- **Advanced Settings** - Remote daemon, providers, subtitles

## Folder Purposes

| Folder | Description |
|--------|-------------|
| `bin/` | Downloaded binaries for each platform |
| `img/` | Genre icons, service icons, UI graphics |
| `language/` | GNU gettext translations (.po files) |
| `screenshots/` | Screenshots for addon description |
| `site-packages/` | Python modules (elementum, bjsonrpc, simplejson) |
| `skins/` | Kodi WindowXML dialog definitions |
| `web/` | Production web UI (compiled JS/CSS) |
| `web-src/` | React development source |

## Notes

- Binaries are not included in repo; downloaded at runtime
- Settings IDs correspond to localized strings (30xxx)
- Web UI can be rebuilt from web-src using npm
