# search-bar

## Purpose

Search input component for filtering torrents.

## Features

- Text input field
- Search button/icon
- Clear button
- Real-time filtering
- Keyboard support (Enter to search)

## Usage

```tsx
import SearchBar from './search-bar';

<SearchBar
  value={searchTerm}
  onChange={setSearchTerm}
  onSearch={handleSearch}
/>
```

## Props

- `value` - Current search term
- `onChange` - Update callback
- `onSearch` - Search action callback
- `placeholder` - Input placeholder

## Notes

- Filters torrent list by name
- Debounced input for performance
- Clear button resets filter
