# delete-modal

## Purpose

Confirmation dialog for deleting torrents.

## Features

- Confirmation message
- Torrent name display
- Delete files option
- Cancel/Confirm buttons
- Modal overlay

## Usage

```tsx
import DeleteModal from './delete-modal';

<DeleteModal
  torrent={torrentToDelete}
  onConfirm={handleDelete}
  onCancel={handleCancel}
  visible={showModal}
/>
```

## Props

- `torrent` - Torrent being deleted
- `onConfirm` - Confirm delete callback
- `onCancel` - Cancel callback
- `visible` - Show/hide modal

## Options

- **Delete files** - Checkbox to also delete downloaded files
- Only deletes from Elementum by default

## Notes

- Prevents accidental deletion
- Clear warning message
- Escape key to cancel
- Click outside to cancel
