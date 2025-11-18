# img

## Purpose

UI icon graphics used throughout the Kodi plugin interface.

## Contents

45 PNG image files for various UI elements.

### Genre Icons (30 files)

Genre-specific icons for content browsing:
- `genre_action.png`
- `genre_adventure.png`
- `genre_animation.png`
- `genre_comedy.png`
- `genre_crime.png`
- `genre_documentary.png`
- `genre_drama.png`
- `genre_family.png`
- `genre_fantasy.png`
- `genre_history.png`
- `genre_horror.png`
- `genre_music.png`
- `genre_mystery.png`
- `genre_romance.png`
- `genre_science_fiction.png`
- `genre_thriller.png`
- `genre_war.png`
- `genre_western.png`
- And more variants...

### Service Icons

- `trakt.png` - Trakt.tv integration
- `imdb.png` - IMDb references
- `tmdb.png` - TheMovieDB

### UI Icons

- `search.png` - Search functionality
- `settings.png` - Settings menu
- `clock.png` - Time/schedule related
- `cloud.png` - Cloud/streaming
- `most_voted.png` - Rating indicators
- `most_watched.png` - Popularity
- `recently_added.png` - New content

## Usage

Icons are referenced in navigation menus:
```python
xbmcgui.ListItem(label, iconImage="special://home/addons/plugin.video.elementum/resources/img/search.png")
```

## Specifications

- Format: PNG
- Transparency: Supported
- Resolution: Typically 256x256 or similar
- Style: Consistent flat design
