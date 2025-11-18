# torrents-list

## Purpose

Main torrent listing component showing all active torrents.

## Features

- List of torrent items
- Sorting options
- Filtering by search
- Selection handling
- Empty state
- Loading state

## Structure

```
torrents-list/
├── index.tsx          # Main list component
├── style.css          # List styles
└── torrent/           # Individual torrent component
```

## Usage

```tsx
import TorrentsList from './torrents-list';

<TorrentsList
  torrents={torrentData}
  onSelect={handleSelect}
  selectedId={selected}
/>
```

## Props

- `torrents` - Array of torrent objects
- `onSelect` - Selection callback
- `selectedId` - Currently selected ID
- `filter` - Search filter

## Display Information

For each torrent:
- Name
- Progress percentage
- Download/upload speed
- Seeds/peers
- Status (downloading, seeding, paused)

## Notes

- Renders list of `torrent/` components
- Handles empty/loading states
- Supports keyboard navigation
