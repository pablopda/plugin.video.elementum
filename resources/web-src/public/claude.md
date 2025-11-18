# public

## Purpose

Static assets and HTML template for the React application.

## Contents

- **index.html** - Main HTML template
  - Root div for React mounting
  - Meta tags
  - Title

## Usage

Create React App uses this as the template. The build process injects compiled JS/CSS into this HTML file.

## HTML Structure

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Elementum</title>
  </head>
  <body>
    <div id="root"></div>
  </body>
</html>
```

## Notes

- Files here are copied to build output
- Only index.html is typically needed
- Favicon and other assets can be added here
