# Services

## Purpose

API service layer for communicating with the Elementumd daemon.

## Functionality

Abstracts HTTP calls to the daemon REST API:

### Torrent Operations
- List all torrents
- Add new torrent (magnet/file)
- Delete torrent
- Get torrent details
- Pause/resume torrent

### API Endpoints

```typescript
// Base URL: http://[daemon]:65220

GET    /torrents           // List all
POST   /torrents           // Add new
GET    /torrents/:id       // Get details
DELETE /torrents/:id       // Remove
PUT    /torrents/:id/pause // Pause
PUT    /torrents/:id/resume // Resume
```

## Usage

```typescript
import { getTorrents, addTorrent, deleteTorrent } from './Services';

// Fetch all torrents
const torrents = await getTorrents();

// Add magnet
await addTorrent(magnetLink);

// Delete
await deleteTorrent(torrentId);
```

## Notes

- Uses fetch API or axios
- Handles errors and loading states
- Returns typed responses
- Base URL from configuration
