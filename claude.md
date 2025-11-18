# plugin.video.elementum

## Overview

Elementum is a **torrent finding and streaming engine** for Kodi. It's a fork of the Pulsar/Quasar projects that allows users to search for movies and TV shows via TheMovieDB and Trakt.tv, find torrents through provider addons, and stream content directly within Kodi.

**Important:** Elementum does NOT connect to torrent websites directly. It calls separate provider addons to find torrents, keeping the core addon legal.

## Tech Stack

- **Python 3.6+** - Main plugin interface
- **Go** - Elementumd daemon (core torrent engine)
- **React/TypeScript** - Web UI
- **Kodi API** - kodi-six compatibility layer

## Project Structure

```
plugin.video.elementum/
├── .github/              # GitHub configuration (issues, PRs, contributing)
├── scripts/              # Build and translation scripts
├── resources/            # Main plugin resources
│   ├── bin/              # Platform-specific binaries (downloaded)
│   ├── img/              # UI icons (45 PNGs)
│   ├── language/         # Translations (20 languages)
│   ├── screenshots/      # Marketing screenshots
│   ├── site-packages/    # Python code
│   │   ├── elementum/    # Core plugin modules
│   │   ├── bjsonrpc/     # JSON-RPC library
│   │   └── simplejson/   # JSON parser
│   ├── skins/            # Kodi UI dialogs
│   ├── web/              # Compiled web UI
│   └── web-src/          # React source code
├── addon.xml             # Kodi addon manifest
├── navigation.py         # Plugin entry point
├── service.py            # Service entry point
├── settings.xml          # Plugin settings (in resources/)
└── Makefile              # Build configuration
```

## Architecture

```
┌─────────────────────────────────────┐
│         Kodi Media Center           │
├─────────────────────────────────────┤
│  plugin.video.elementum (Python)    │
│  ├─ navigation.py (UI/menus)        │
│  ├─ service.py (background)         │
│  ├─ provider.py (addon integration) │
│  └─ dialog_*.py (UI components)     │
└─────────────────────────────────────┘
              ↓ JSON-RPC
┌─────────────────────────────────────┐
│  Elementumd Daemon (Go, port 65220) │
│  ├─ Torrent client (libtorrent-go)  │
│  ├─ Stream selection                │
│  └─ Metadata fetching               │
└─────────────────────────────────────┘
              ↓
    BitTorrent Network + APIs
    (TMDB, Trakt, Providers)
```

## Entry Points

- **navigation.py** - Routes user interactions to plugin menus
- **service.py** - Starts RPC server and Elementumd daemon

## Key Configuration

- **addon.xml** - Addon manifest with dependencies and metadata
- **resources/settings.xml** - User-configurable settings (850+ lines)

## Building

```bash
# Install dev dependencies
pip install -r requirements.txt

# Lint code
python -m flake8

# Bundle for specific platform
./bundle.sh --binaries=/path/to/build --platform=android_arm64

# Full release
./release.sh
```

## Supported Platforms

- Windows (x86, x64)
- Linux (x86, x64, ARM v6/v7/v8)
- macOS (x64, arm64)
- Android (ARM, x86)

## Dependencies

- **kodi-six** - Python 2/3 compatibility
- **requests** - HTTP library
- **bjsonrpc** - JSON-RPC communication
- **simplejson** - JSON parsing

## Development Notes

- Binaries are downloaded from `elgatito/elementum-binaries` repository
- Provider addons are separate Kodi addons that find torrents
- The daemon communicates via JSON-RPC on ports 65220 (HTTP) and 65221 (RPC)
- Translations use GNU gettext format (.po files)

## License

Non-commercial license - see LICENSE file.
