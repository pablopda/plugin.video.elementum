# menu

## Purpose

Navigation menu component for the web UI sidebar.

## Features

- Navigation links
- Active state indication
- Responsive design
- Icon support

## Usage

```tsx
import Menu from './menu';

<Menu onNavigate={handleNav} activeItem="torrents" />
```

## Structure

Typically contains:
- `index.tsx` or `Menu.tsx` - Component
- `menu.css` or `style.css` - Styles

## Menu Items

- Torrents (main view)
- Settings
- About

## Notes

- Highlights current section
- Consistent across all views
- Mobile-friendly
