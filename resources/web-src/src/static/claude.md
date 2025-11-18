# static

## Purpose

Static assets for the React web application.

## Contents

- Images
- Icons
- Fonts (if any)
- Other static files

## Usage

Import in components:
```tsx
import logo from './static/logo.png';

<img src={logo} alt="Logo" />
```

Or reference in CSS:
```css
.icon {
  background-image: url('./static/icon.png');
}
```

## Notes

- Assets are bundled during build
- Optimized and hashed for caching
- Copied to build output
