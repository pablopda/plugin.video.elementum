# media

## Purpose

UI graphic assets for the custom Kodi dialogs.

## Structure

```
media/
├── AddonWindow/    # Window backgrounds
├── Button/         # Button graphics
├── List/           # List item styling
└── Scrollbar/      # Scrollbar controls
```

## Asset Types

### AddonWindow
- Dialog background images
- Border graphics
- Corner pieces

### Button
- Close button (normal, focus, pressed)
- Action buttons
- Icon buttons

### List
- List item backgrounds
- Selection highlights
- Focus states

### Scrollbar
- Scroll track
- Scroll thumb
- Arrow buttons

## Usage in XML

```xml
<control type="image">
    <texture>media/Button/close-focus.png</texture>
</control>
```

## Specifications

- Format: PNG with transparency
- States: Normal, Focus, Pressed
- Colors: Match dark theme
- Size: Varies by element

## Notes

- Keep consistent with Kodi design language
- Support focus navigation visuals
- Test with different Kodi skins
