# src

## Purpose

React source code for the Elementum web UI.

## Main Files

- **index.tsx** - React entry point, renders App
- **App.tsx** - Main React component
- **style.css** - Global styles
- **dataStructure.ts** - TypeScript type definitions
- **react-app-env.d.ts** - Create React App types

## Components

### Core
- **App.tsx** - Main container, routing, state management

### UI Components
- **menu/** - Navigation sidebar
- **search-bar/** - Search input component
- **torrents-list/** - List of all torrents
  - **torrent/** - Individual torrent item
- **torrent-info/** - Detailed torrent view
- **delete-modal/** - Delete confirmation dialog
- **upload-modal/** - Add torrent dialog

### Services
- **Services/** - API communication layer

### Assets
- **static/** - Static files (images, etc.)

## Type Definitions

`dataStructure.ts` defines:
- Torrent interface
- File interface
- API response types

## Architecture

```
index.tsx
    └── App.tsx
        ├── menu/
        ├── search-bar/
        ├── torrents-list/
        │   └── torrent/
        ├── torrent-info/
        ├── delete-modal/
        └── upload-modal/
```

## Notes

- Component-based React architecture
- TypeScript for type safety
- Each component in its own folder
- Services abstract API calls
