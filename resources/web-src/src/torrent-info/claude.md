# torrent-info

## Purpose

Detailed view component for a selected torrent.

## Features

- Full torrent information
- File list
- Peer list
- Trackers
- Transfer statistics
- Action buttons

## Usage

```tsx
import TorrentInfo from './torrent-info';

<TorrentInfo
  torrent={selectedTorrent}
  onClose={handleClose}
  onDelete={handleDelete}
/>
```

## Displayed Information

### General
- Name
- Hash
- Size
- Added date
- Status

### Transfer
- Progress percentage
- Downloaded/uploaded bytes
- Download/upload speed
- ETA
- Ratio

### Peers
- Connected peers
- Seeds/leechers
- Peer countries (if available)

### Files
- File list with sizes
- Individual file progress
- Priority settings

### Trackers
- Tracker URLs
- Tracker status
- Last announce

## Actions

- Pause/Resume
- Delete (with modal)
- Copy magnet link
- Force recheck

## Notes

- Detailed view for analysis
- File selection support
- Real-time updates
