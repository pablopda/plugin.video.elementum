# web

## Purpose

Compiled production React web UI for remote management of Elementum.

## Structure

```
web/
├── index.html              # Main entry point
├── favicon.ico             # Browser favicon
├── asset-manifest.json     # Build manifest
└── static/
    ├── css/                # Compiled CSS
    ├── js/                 # Compiled JavaScript
    └── media/              # Static assets
```

## Features

The web UI provides:
- Torrent list management
- Upload new torrents
- Delete torrents
- View torrent details
- Search functionality
- Real-time status updates

## Access

Accessible at: `http://[daemon-host]:65220/web/`

Default: `http://127.0.0.1:65220/web/`

## Build Source

This folder contains compiled output from `resources/web-src/`.

To rebuild:
```bash
cd resources/web-src
npm install
npm run build
# Output goes to ../web/
```

## Technology

- React (compiled from TypeScript)
- Create React App build system
- Single-page application
- REST API communication with daemon

## Notes

- Do not edit files here directly
- Edit source in `web-src/` and rebuild
- Production-optimized (minified, bundled)
- Served by Elementumd daemon
