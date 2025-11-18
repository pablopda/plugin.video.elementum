# Integration Patches for Elementum Daemon

This document shows the exact changes to make in existing Elementum source files.

---

## 1. torrent.go Patches

### Add field to Torrent struct

Find the `Torrent` struct and add:

```go
type Torrent struct {
    // ... existing fields ...

    // Lookbehind buffer manager
    lookbehind *LookbehindManager
}
```

### Add InitLookbehind method

Add this method to torrent.go:

```go
// InitLookbehind initializes the lookbehind manager for a file.
// Call after selecting the file to play.
func (t *Torrent) InitLookbehind(fileSize, fileOffset int64, duration float64) {
    if config.Get().LookbehindEnabled {
        t.lookbehind = NewLookbehindManager(t, fileSize, fileOffset, duration)
    }
}
```

### Add OnSeekEvent method

Add this method to torrent.go:

```go
// OnSeekEvent handles seek events from the file system layer.
// Logs whether the seek target is in the lookbehind buffer.
func (t *Torrent) OnSeekEvent(fromBytePos, toBytePos int64) {
    if t.lookbehind == nil {
        return
    }

    fromPiece := int(fromBytePos / t.ti.PieceLength())
    toPiece := int(toBytePos / t.ti.PieceLength())
    delta := toBytePos - fromBytePos

    if delta < 0 {
        // Backward seek
        if t.lookbehind.IsAvailable(toPiece) {
            log.Debugf("Backward seek to piece %d - data available in lookbehind", toPiece)
        } else if t.lookbehind.IsInWindow(toPiece) {
            log.Debugf("Backward seek to piece %d - in window but not cached", toPiece)
        } else {
            log.Debugf("Backward seek to piece %d - outside lookbehind, will download", toPiece)
        }
    } else {
        log.Debugf("Forward seek from piece %d to %d", fromPiece, toPiece)
    }

    // Update lookbehind position
    t.lookbehind.UpdatePosition(toBytePos - t.lookbehind.fileOffset)
}
```

### Modify Close method

In the `Close()` method of Torrent, add lookbehind cleanup:

```go
func (t *Torrent) Close() {
    // ... existing close logic ...

    // Clear lookbehind
    if t.lookbehind != nil {
        t.lookbehind.Clear()
        t.lookbehind = nil
    }
}
```

---

## 2. torrentfs.go Patches

### Modify TorrentFSEntry Seek method

Replace or modify the Seek method to include lookbehind updates:

```go
func (tf *TorrentFSEntry) Seek(offset int64, whence int) (int64, error) {
    oldPos := tf.pos

    // Calculate new position
    var newPos int64
    switch whence {
    case io.SeekStart:
        newPos = offset
    case io.SeekCurrent:
        newPos = tf.pos + offset
    case io.SeekEnd:
        newPos = tf.file.Size + offset
    default:
        return 0, errors.New("invalid whence")
    }

    // Validate
    if newPos < 0 {
        return 0, errors.New("negative position")
    }
    if newPos > tf.file.Size {
        newPos = tf.file.Size
    }

    tf.pos = newPos

    // Update lookbehind on seeks
    if tf.t != nil && tf.t.lookbehind != nil {
        delta := newPos - oldPos
        pieceLength := tf.t.ti.PieceLength()

        if delta < 0 || delta > pieceLength {
            // Significant seek - notify torrent
            tf.t.OnSeekEvent(
                tf.file.Offset+oldPos,
                tf.file.Offset+newPos,
            )
        } else {
            // Regular position update
            tf.t.lookbehind.UpdatePosition(newPos)
        }
    }

    return tf.pos, nil
}
```

### Modify TorrentFSEntry Read method

Add lookbehind position update after successful reads:

```go
func (tf *TorrentFSEntry) Read(b []byte) (int, error) {
    // ... existing read logic ...

    n, err := tf.readPiece(b)

    // Update lookbehind position after successful read
    if n > 0 && tf.t != nil && tf.t.lookbehind != nil {
        tf.t.lookbehind.UpdatePosition(tf.pos)
    }

    return n, err
}
```

---

## 3. player.go Patches

### Modify Buffer method

After the file is selected (chosenFile is set), initialize lookbehind:

```go
func (btp *Player) Buffer() error {
    // ... existing buffer logic that selects chosenFile ...

    // After file selection, initialize lookbehind
    if btp.chosenFile != nil && config.Get().LookbehindEnabled {
        duration := btp.getVideoDuration()
        btp.t.InitLookbehind(
            btp.chosenFile.Size,
            btp.chosenFile.Offset,
            duration,
        )
    }

    // ... rest of buffer logic ...
}
```

### Add getVideoDuration helper

Add this helper method to Player:

```go
// getVideoDuration returns the video duration in seconds
func (btp *Player) getVideoDuration() float64 {
    // Try to get from player params (runtime in minutes)
    if btp.p != nil && btp.p.Runtime > 0 {
        return float64(btp.p.Runtime) * 60
    }

    // Estimate from file size assuming 2.5 MB/s for 1080p
    if btp.chosenFile != nil && btp.chosenFile.Size > 0 {
        return float64(btp.chosenFile.Size) / (2500 * 1024)
    }

    return 0
}
```

### Modify Close method

Add lookbehind cleanup to Player.Close():

```go
func (btp *Player) Close() {
    // ... existing close logic ...

    if btp.t != nil && btp.t.lookbehind != nil {
        btp.t.lookbehind.Clear()
    }
}
```

---

## 4. service.go Patches

### Add validation in configure method

Add this validation to the configure() method:

```go
func (s *BTService) configure() {
    // ... existing configuration ...

    // Validate memory for lookbehind
    if config.Get().LookbehindEnabled {
        lookbehindSize := config.Get().LookbehindMaxSize

        minMemory := int64(s.config.BufferSize) +
            s.config.EndBufferSize +
            lookbehindSize +
            8*1024*1024

        if config.Get().MemorySize < minMemory {
            log.Warningf("Memory %d MB may be insufficient for lookbehind. Recommended: %d MB",
                config.Get().MemorySize/1024/1024,
                minMemory/1024/1024)
        }

        log.Infof("Lookbehind enabled: %ds window, max %d MB",
            config.Get().LookbehindTime,
            config.Get().LookbehindMaxSize/1024/1024)
    }
}
```

---

## Summary of Changes

| File | Changes |
|------|---------|
| torrent.go | Add `lookbehind` field, `InitLookbehind()`, `OnSeekEvent()`, cleanup in `Close()` |
| torrentfs.go | Update `Seek()` and `Read()` to notify lookbehind |
| player.go | Initialize lookbehind in `Buffer()`, add `getVideoDuration()`, cleanup in `Close()` |
| service.go | Add validation in `configure()` |

---

## Testing After Integration

1. Build the daemon: `make all`
2. Run with debug: `./elementum --debug`
3. Play a video and seek backward
4. Check logs for "Lookbehind" messages
5. Verify backward seeks within 30s are fast
