# web-src

## Purpose

React source code for the Elementum web management interface.

## Technology Stack

- **Framework:** React
- **Language:** TypeScript/TSX
- **Build Tool:** Create React App
- **Styling:** CSS

## Structure

```
web-src/
├── README.md           # Build instructions
├── package.json        # Dependencies and scripts
├── public/             # Static HTML template
│   └── index.html
└── src/                # React source code
    ├── App.tsx         # Main React component
    ├── index.tsx       # Entry point
    ├── style.css       # Global styles
    ├── dataStructure.ts # Type definitions
    ├── Services/       # API service layer
    ├── menu/           # Navigation menu
    ├── search-bar/     # Search component
    ├── torrents-list/  # Torrent listing
    │   └── torrent/    # Individual torrent
    ├── torrent-info/   # Torrent details
    ├── delete-modal/   # Delete confirmation
    ├── upload-modal/   # Torrent upload
    └── static/         # Static assets
```

## Building

```bash
# Install dependencies
npm install

# Development server
npm start

# Production build
npm run build
# Output: ../web/
```

## Features

- View active torrents
- Upload new torrents/magnets
- Delete torrents
- View torrent details
- Search functionality
- Real-time status updates

## API Communication

Communicates with Elementumd daemon REST API:
- `GET /torrents` - List torrents
- `POST /torrents` - Add torrent
- `DELETE /torrents/:id` - Remove torrent
- `GET /torrents/:id` - Torrent details

## Notes

- Output goes to `../web/` folder
- Uses Create React App defaults
- TypeScript for type safety
- Component-based architecture
