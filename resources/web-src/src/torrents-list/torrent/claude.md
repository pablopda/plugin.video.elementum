# torrent

## Purpose

Individual torrent item component within the torrents list.

## Features

- Torrent name display
- Progress bar
- Speed indicators
- Peer information
- Status icon
- Click to select
- Action buttons (pause, delete)

## Usage

```tsx
import Torrent from './torrent';

<Torrent
  data={torrentData}
  selected={isSelected}
  onClick={handleClick}
/>
```

## Props

- `data` - Torrent object
- `selected` - Boolean selection state
- `onClick` - Click handler

## Displayed Data

- **Name** - Torrent name
- **Progress** - Download percentage
- **Size** - Total/downloaded size
- **Speed** - Download/upload rates
- **Peers** - Seeds/leechers count
- **Status** - Current state

## Status Types

- `downloading` - Active download
- `seeding` - Complete, seeding
- `paused` - Paused by user
- `queued` - Waiting to start
- `error` - Error state

## Notes

- Visual feedback for selection
- Color coding by status
- Compact view for list
