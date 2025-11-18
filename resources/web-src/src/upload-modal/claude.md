# upload-modal

## Purpose

Dialog for adding new torrents to Elementum.

## Features

- Magnet link input
- Torrent file upload
- URL input
- Validation
- Progress indicator

## Usage

```tsx
import UploadModal from './upload-modal';

<UploadModal
  onUpload={handleUpload}
  onCancel={handleCancel}
  visible={showModal}
/>
```

## Input Methods

### Magnet Link
- Text input field
- Paste magnet URI
- Validation for magnet format

### Torrent File
- File input/drag-drop
- .torrent file selection
- File size validation

### URL
- Direct torrent URL
- Downloads and adds

## Props

- `onUpload` - Upload callback with data
- `onCancel` - Cancel callback
- `visible` - Show/hide modal

## Validation

- Magnet link format (magnet:?xt=...)
- File type (.torrent)
- URL format

## Notes

- Supports multiple input methods
- Shows upload progress
- Error feedback
- Escape to cancel
