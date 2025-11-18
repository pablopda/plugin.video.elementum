# Lookbehind Buffer Implementation Guide

## Overview

This document provides complete, production-ready code to implement the lookbehind buffer feature in Elementum. The feature keeps recently played content in memory to enable fast backward seeking.

**Expected Result:** Backward seeks within the lookbehind window complete in <2 seconds instead of 10-25 seconds.

---

## Prerequisites

### Repositories to Modify

1. **ElementumOrg/libtorrent-go** - C++ bindings for libtorrent
2. **elgatito/elementum** - Go daemon

### Build Environment

- Go 1.19+
- C++ compiler with C++14 support
- libtorrent-rasterbar 1.2.x or 2.x
- Cross-compilation toolchain (for multi-platform builds)

---

## Part 1: libtorrent-go Changes

### File: memory_storage.hpp

Add the following methods to the `memory_storage` class:

```cpp
// ============================================================================
// LOOKBEHIND BUFFER IMPLEMENTATION
// Add these to the memory_storage class in memory_storage.hpp
// ============================================================================

public:
    /**
     * Set pieces to protect from eviction for lookbehind buffer.
     * These pieces will be marked as reserved and won't be evicted by trim().
     *
     * THREAD SAFETY: Call from libtorrent's disk thread context.
     * Uses libtorrent's internal synchronization - no additional mutex needed.
     *
     * @param pieces Vector of piece indices to protect
     */
    void set_lookbehind_pieces(std::vector<int> const& pieces) {
        // Clear previous lookbehind reservations
        for (int i = 0; i < m_num_pieces && i < m_lookbehind_pieces.size(); i++) {
            if (m_lookbehind_pieces.get_bit(i)) {
                m_reserved_pieces.clear_bit(i);
            }
        }
        m_lookbehind_pieces.clear();

        if (pieces.empty()) {
            return;
        }

        // Find max piece for resizing
        int max_piece = 0;
        for (int p : pieces) {
            if (p > max_piece) max_piece = p;
        }

        // Resize bitfield if needed
        if (max_piece >= m_lookbehind_pieces.size()) {
            m_lookbehind_pieces.resize(max_piece + 1, false);
        }

        // Set new lookbehind pieces as reserved
        for (int piece : pieces) {
            if (piece >= 0 && piece < m_num_pieces) {
                m_lookbehind_pieces.set_bit(piece);
                m_reserved_pieces.set_bit(piece);
            }
        }
    }

    /**
     * Clear all lookbehind reservations.
     * Call when stopping playback or switching files.
     */
    void clear_lookbehind() {
        for (int i = 0; i < m_num_pieces && i < m_lookbehind_pieces.size(); i++) {
            if (m_lookbehind_pieces.get_bit(i)) {
                m_reserved_pieces.clear_bit(i);
            }
        }
        m_lookbehind_pieces.clear();
    }

    /**
     * Check if a specific piece is in lookbehind AND available in memory.
     * Use this to verify data is actually cached before reporting fast-path availability.
     *
     * @param piece Piece index to check
     * @return true if piece is protected AND has data in memory
     */
    bool is_lookbehind_available(int piece) const {
        if (piece < 0 || piece >= m_num_pieces) {
            return false;
        }
        if (piece >= m_lookbehind_pieces.size() || !m_lookbehind_pieces.get_bit(piece)) {
            return false;
        }
        // Verify piece is actually in memory (has buffer assigned)
        return m_pieces[piece].bi >= 0;
    }

    /**
     * Get count of lookbehind pieces that are actually available in memory.
     * Useful for monitoring and debugging.
     *
     * @return Number of protected pieces with data
     */
    int get_lookbehind_available_count() const {
        int count = 0;
        int max_check = std::min(m_num_pieces, (int)m_lookbehind_pieces.size());
        for (int i = 0; i < max_check; i++) {
            if (m_lookbehind_pieces.get_bit(i) && m_pieces[i].bi >= 0) {
                count++;
            }
        }
        return count;
    }

    /**
     * Get total count of protected lookbehind pieces (may not all be in memory).
     *
     * @return Number of pieces marked for lookbehind protection
     */
    int get_lookbehind_protected_count() const {
        return (int)m_lookbehind_pieces.count();
    }

    /**
     * Get memory used by available lookbehind pieces in bytes.
     *
     * @return Bytes of lookbehind data currently in memory
     */
    int64_t get_lookbehind_memory_used() const {
        return (int64_t)get_lookbehind_available_count() * m_piece_length;
    }

private:
    // Add this member variable to the class
    lt::bitfield m_lookbehind_pieces;  // Track which pieces are for lookbehind
```

### File: memory_storage.go (Go Bindings)

Create or add to the Go bindings file:

```go
package libtorrent

/*
#include "memory_storage.hpp"
#include <stdlib.h>

// C wrapper functions for lookbehind
void memory_storage_set_lookbehind_pieces(void* ms, int* pieces, int count);
void memory_storage_clear_lookbehind(void* ms);
int memory_storage_is_lookbehind_available(void* ms, int piece);
int memory_storage_get_lookbehind_available_count(void* ms);
int memory_storage_get_lookbehind_protected_count(void* ms);
long long memory_storage_get_lookbehind_memory_used(void* ms);
*/
import "C"
import (
    "unsafe"
)

// SetLookbehindPieces sets pieces to protect from eviction for backward seeking.
// Pass nil or empty slice to clear all lookbehind reservations.
func (ms *MemoryStorage) SetLookbehindPieces(pieces []int) {
    if len(pieces) == 0 {
        C.memory_storage_clear_lookbehind(ms.ptr)
        return
    }

    // Convert Go slice to C array
    cPieces := make([]C.int, len(pieces))
    for i, p := range pieces {
        cPieces[i] = C.int(p)
    }

    C.memory_storage_set_lookbehind_pieces(
        ms.ptr,
        (*C.int)(unsafe.Pointer(&cPieces[0])),
        C.int(len(pieces)),
    )
}

// ClearLookbehind removes all lookbehind piece reservations.
func (ms *MemoryStorage) ClearLookbehind() {
    C.memory_storage_clear_lookbehind(ms.ptr)
}

// IsLookbehindAvailable checks if a piece is protected AND available in memory.
func (ms *MemoryStorage) IsLookbehindAvailable(piece int) bool {
    return C.memory_storage_is_lookbehind_available(ms.ptr, C.int(piece)) != 0
}

// GetLookbehindAvailableCount returns count of protected pieces actually in memory.
func (ms *MemoryStorage) GetLookbehindAvailableCount() int {
    return int(C.memory_storage_get_lookbehind_available_count(ms.ptr))
}

// GetLookbehindProtectedCount returns total count of protected pieces.
func (ms *MemoryStorage) GetLookbehindProtectedCount() int {
    return int(C.memory_storage_get_lookbehind_protected_count(ms.ptr))
}

// GetLookbehindMemoryUsed returns bytes used by lookbehind buffer.
func (ms *MemoryStorage) GetLookbehindMemoryUsed() int64 {
    return int64(C.memory_storage_get_lookbehind_memory_used(ms.ptr))
}
```

### File: memory_storage_wrapper.cpp (C Wrappers)

Add C wrapper functions that Go can call:

```cpp
// C wrapper functions for Go bindings
extern "C" {

void memory_storage_set_lookbehind_pieces(void* ms, int* pieces, int count) {
    if (ms == nullptr) return;

    std::vector<int> piece_vec;
    if (pieces != nullptr && count > 0) {
        piece_vec.assign(pieces, pieces + count);
    }

    static_cast<memory_storage*>(ms)->set_lookbehind_pieces(piece_vec);
}

void memory_storage_clear_lookbehind(void* ms) {
    if (ms == nullptr) return;
    static_cast<memory_storage*>(ms)->clear_lookbehind();
}

int memory_storage_is_lookbehind_available(void* ms, int piece) {
    if (ms == nullptr) return 0;
    return static_cast<memory_storage*>(ms)->is_lookbehind_available(piece) ? 1 : 0;
}

int memory_storage_get_lookbehind_available_count(void* ms) {
    if (ms == nullptr) return 0;
    return static_cast<memory_storage*>(ms)->get_lookbehind_available_count();
}

int memory_storage_get_lookbehind_protected_count(void* ms) {
    if (ms == nullptr) return 0;
    return static_cast<memory_storage*>(ms)->get_lookbehind_protected_count();
}

long long memory_storage_get_lookbehind_memory_used(void* ms) {
    if (ms == nullptr) return 0;
    return static_cast<memory_storage*>(ms)->get_lookbehind_memory_used();
}

} // extern "C"
```

---

## Part 2: Elementum Daemon Changes

### File: config/config.go

Add lookbehind configuration parameters:

```go
// ============================================================================
// Add to Configuration struct
// ============================================================================

type Configuration struct {
    // ... existing fields ...

    // Lookbehind Buffer Settings
    LookbehindEnabled    bool  `json:"lookbehind_enabled"`
    LookbehindTime       int   `json:"lookbehind_time"`       // seconds to retain
    LookbehindMaxSize    int64 `json:"lookbehind_max_size"`   // max bytes for lookbehind
    AutoAdjustLookbehind bool  `json:"auto_adjust_lookbehind"`
}

// ============================================================================
// Add to Reload() function
// ============================================================================

func (c *Configuration) Reload() {
    // ... existing settings loading ...

    // Lookbehind settings
    c.LookbehindEnabled = xbmc.GetSettingBool("lookbehind_enabled", true)
    c.LookbehindTime = xbmc.GetSettingInt("lookbehind_time", 30)

    lookbehindMaxSizeMB := xbmc.GetSettingInt("lookbehind_max_size", 50)
    c.LookbehindMaxSize = int64(lookbehindMaxSizeMB) * 1024 * 1024

    c.AutoAdjustLookbehind = xbmc.GetSettingBool("auto_adjust_lookbehind", true)

    // Validate and enforce memory constraints
    c.enforceLookbehindMemoryConstraints()
}

// ============================================================================
// Add new validation function
// ============================================================================

func (c *Configuration) enforceLookbehindMemoryConstraints() {
    if !c.LookbehindEnabled {
        return
    }

    // Calculate memory available for lookbehind
    // Total - Forward Buffer - End Buffer - Overhead
    reservedMemory := int64(c.BufferSize) + c.EndBufferSize + 8*1024*1024
    availableForLookbehind := int64(c.MemorySize) - reservedMemory

    // Cap at 50% of total memory to leave room for libtorrent
    maxAllowed := int64(c.MemorySize) / 2
    if availableForLookbehind > maxAllowed {
        availableForLookbehind = maxAllowed
    }

    // Enforce cap
    if c.LookbehindMaxSize > availableForLookbehind {
        log.Warningf("Lookbehind size %d MB exceeds available %d MB, capping",
            c.LookbehindMaxSize/1024/1024,
            availableForLookbehind/1024/1024)
        c.LookbehindMaxSize = availableForLookbehind
    }

    // Disable if too small to be useful
    if c.LookbehindMaxSize < 10*1024*1024 {
        log.Warning("Insufficient memory for lookbehind (<10MB), disabling")
        c.LookbehindEnabled = false
    }
}

// ============================================================================
// Add helper function
// ============================================================================

// CalculateLookbehindSize determines actual lookbehind size based on video bitrate
func (c *Configuration) CalculateLookbehindSize(fileSize int64, durationSec float64) int64 {
    if !c.LookbehindEnabled || c.LookbehindTime == 0 {
        return 0
    }

    // Calculate bitrate from file size and duration
    var bitrateBps int64
    if durationSec > 0 {
        bitrateBps = int64(float64(fileSize) / durationSec)
    } else {
        // Fallback: assume 2.5 MB/s for 1080p content
        bitrateBps = 2500 * 1024
    }

    // Calculate needed size for configured time
    size := bitrateBps * int64(c.LookbehindTime)

    // Cap at configured maximum
    if size > c.LookbehindMaxSize {
        size = c.LookbehindMaxSize
    }

    return size
}
```

### File: bittorrent/lookbehind.go (NEW FILE)

Create a new file for the LookbehindManager:

```go
// ============================================================================
// bittorrent/lookbehind.go - Lookbehind Buffer Manager
// ============================================================================

package bittorrent

import (
    "sync"
    "time"

    "github.com/elgatito/elementum/config"
)

// LookbehindManager manages the lookbehind buffer for fast backward seeking
type LookbehindManager struct {
    // Configuration
    enabled     bool
    timeSeconds int
    maxSize     int64

    // Current state
    currentBytePos  int64
    protectedPieces []int
    sizeBytes       int64
    lastUpdate      time.Time

    // Torrent reference
    torrent     *Torrent
    pieceLength int64
    numPieces   int
    fileSize    int64
    fileOffset  int64 // Offset of file within torrent
    duration    float64

    // Thread safety
    mu sync.RWMutex
}

// NewLookbehindManager creates a new lookbehind manager
func NewLookbehindManager(t *Torrent, file *File, duration float64) *LookbehindManager {
    cfg := config.Get()

    lm := &LookbehindManager{
        enabled:     cfg.LookbehindEnabled,
        timeSeconds: cfg.LookbehindTime,
        maxSize:     cfg.LookbehindMaxSize,

        torrent:     t,
        pieceLength: t.pieceLength,
        numPieces:   t.numPieces,
        fileSize:    file.Size,
        fileOffset:  file.Offset,
        duration:    duration,

        currentBytePos:  0,
        protectedPieces: make([]int, 0),
    }

    // Calculate actual size based on video bitrate
    lm.sizeBytes = cfg.CalculateLookbehindSize(file.Size, duration)

    // Enforce 50% memory cap
    maxAllowed := t.MemorySize / 2
    if lm.sizeBytes > maxAllowed {
        lm.sizeBytes = maxAllowed
        log.Debugf("Lookbehind capped to %d MB (50%% of memory)", lm.sizeBytes/1024/1024)
    }

    log.Infof("Lookbehind initialized: %d MB for %ds (bitrate: %.2f MB/s)",
        lm.sizeBytes/1024/1024,
        lm.timeSeconds,
        float64(file.Size)/duration/1024/1024)

    return lm
}

// UpdatePosition updates protected pieces based on current byte position in file
func (lm *LookbehindManager) UpdatePosition(fileBytePos int64) {
    if !lm.enabled {
        return
    }

    lm.mu.Lock()
    defer lm.mu.Unlock()

    // Debounce: skip if updated within 100ms
    if time.Since(lm.lastUpdate) < 100*time.Millisecond {
        return
    }

    // Skip if position hasn't changed significantly
    if abs64(fileBytePos-lm.currentBytePos) < lm.pieceLength {
        return
    }

    lm.currentBytePos = fileBytePos
    lm.lastUpdate = time.Now()

    // Convert file position to torrent position
    torrentBytePos := lm.fileOffset + fileBytePos

    // Calculate piece range for lookbehind window
    currentPiece := int(torrentBytePos / lm.pieceLength)

    lookbehindStartByte := torrentBytePos - lm.sizeBytes
    if lookbehindStartByte < lm.fileOffset {
        lookbehindStartByte = lm.fileOffset
    }
    startPiece := int(lookbehindStartByte / lm.pieceLength)

    // Build protected pieces list
    lm.protectedPieces = make([]int, 0, currentPiece-startPiece)
    for i := startPiece; i < currentPiece; i++ {
        if i >= 0 && i < lm.numPieces {
            lm.protectedPieces = append(lm.protectedPieces, i)
        }
    }

    // Update libtorrent memory storage
    lm.updateReservedPieces()
}

func (lm *LookbehindManager) updateReservedPieces() {
    if lm.torrent == nil || lm.torrent.ms == nil {
        return
    }

    lm.torrent.ms.SetLookbehindPieces(lm.protectedPieces)

    if len(lm.protectedPieces) > 0 {
        log.Debugf("Lookbehind: protecting pieces %d-%d (%d pieces, %d MB)",
            lm.protectedPieces[0],
            lm.protectedPieces[len(lm.protectedPieces)-1],
            len(lm.protectedPieces),
            lm.sizeBytes/1024/1024)
    }
}

// IsAvailable checks if a piece is in lookbehind AND actually available in memory
func (lm *LookbehindManager) IsAvailable(piece int) bool {
    lm.mu.RLock()
    defer lm.mu.RUnlock()

    if !lm.enabled || lm.torrent == nil || lm.torrent.ms == nil {
        return false
    }

    return lm.torrent.ms.IsLookbehindAvailable(piece)
}

// IsInWindow checks if a piece is within the lookbehind window (may not be cached)
func (lm *LookbehindManager) IsInWindow(piece int) bool {
    lm.mu.RLock()
    defer lm.mu.RUnlock()

    if !lm.enabled || len(lm.protectedPieces) == 0 {
        return false
    }

    startPiece := lm.protectedPieces[0]
    endPiece := lm.protectedPieces[len(lm.protectedPieces)-1]

    return piece >= startPiece && piece <= endPiece
}

// GetAvailableCount returns count of protected pieces actually in memory
func (lm *LookbehindManager) GetAvailableCount() int {
    if lm.torrent == nil || lm.torrent.ms == nil {
        return 0
    }
    return lm.torrent.ms.GetLookbehindAvailableCount()
}

// Clear removes all lookbehind reservations
func (lm *LookbehindManager) Clear() {
    lm.mu.Lock()
    defer lm.mu.Unlock()

    lm.protectedPieces = make([]int, 0)
    lm.currentBytePos = 0

    if lm.torrent != nil && lm.torrent.ms != nil {
        lm.torrent.ms.ClearLookbehind()
    }

    log.Debug("Lookbehind cleared")
}

// GetStats returns current lookbehind statistics
func (lm *LookbehindManager) GetStats() LookbehindStats {
    lm.mu.RLock()
    defer lm.mu.RUnlock()

    availableCount := 0
    memoryUsed := int64(0)
    if lm.torrent != nil && lm.torrent.ms != nil {
        availableCount = lm.torrent.ms.GetLookbehindAvailableCount()
        memoryUsed = lm.torrent.ms.GetLookbehindMemoryUsed()
    }

    return LookbehindStats{
        Enabled:         lm.enabled,
        ConfiguredMB:    int(lm.sizeBytes / 1024 / 1024),
        ActualMB:        int(memoryUsed / 1024 / 1024),
        ProtectedPieces: len(lm.protectedPieces),
        AvailablePieces: availableCount,
        TimeSeconds:     lm.timeSeconds,
    }
}

// LookbehindStats contains lookbehind buffer statistics
type LookbehindStats struct {
    Enabled         bool
    ConfiguredMB    int
    ActualMB        int
    ProtectedPieces int
    AvailablePieces int
    TimeSeconds     int
}

func abs64(x int64) int64 {
    if x < 0 {
        return -x
    }
    return x
}
```

### File: bittorrent/torrent.go

Add lookbehind field and initialization:

```go
// ============================================================================
// Add to Torrent struct
// ============================================================================

type Torrent struct {
    // ... existing fields ...

    // Lookbehind buffer manager
    lookbehind *LookbehindManager
}

// ============================================================================
// Add initialization method
// ============================================================================

// InitLookbehind initializes the lookbehind manager for a file
func (t *Torrent) InitLookbehind(file *File, duration float64) {
    if config.Get().LookbehindEnabled {
        t.lookbehind = NewLookbehindManager(t, file, duration)
    }
}

// ============================================================================
// Add cleanup in Close() method
// ============================================================================

func (t *Torrent) Close() {
    // ... existing close logic ...

    // Clear lookbehind
    if t.lookbehind != nil {
        t.lookbehind.Clear()
        t.lookbehind = nil
    }
}

// ============================================================================
// Add seek event handler
// ============================================================================

// OnSeekEvent handles seek events from file system layer
func (t *Torrent) OnSeekEvent(fromBytePos, toBytePos int64) {
    if t.lookbehind == nil {
        return
    }

    fromPiece := int(fromBytePos / t.pieceLength)
    toPiece := int(toBytePos / t.pieceLength)
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
    t.lookbehind.UpdatePosition(toBytePos)
}
```

### File: bittorrent/torrentfs.go

Add seek detection and lookbehind updates:

```go
// ============================================================================
// Add to TorrentFSEntry struct
// ============================================================================

type TorrentFSEntry struct {
    // ... existing fields ...

    lastReportedPos int64 // Track position for change detection
}

// ============================================================================
// Modify Seek method
// ============================================================================

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

    // Update lookbehind on significant seeks
    if tf.torrent != nil && tf.torrent.lookbehind != nil {
        delta := newPos - oldPos
        if delta < 0 || delta > tf.torrent.pieceLength {
            // Notify torrent of seek event
            tf.torrent.OnSeekEvent(
                tf.file.Offset+oldPos,
                tf.file.Offset+newPos,
            )
        } else {
            // Regular position update
            tf.torrent.lookbehind.UpdatePosition(newPos)
        }
    }

    return tf.pos, nil
}

// ============================================================================
// Modify Read method to update lookbehind position
// ============================================================================

func (tf *TorrentFSEntry) Read(b []byte) (int, error) {
    // ... existing read logic ...

    n, err := tf.readInternal(b)

    // Update lookbehind position after successful read
    if n > 0 && tf.torrent != nil && tf.torrent.lookbehind != nil {
        tf.torrent.lookbehind.UpdatePosition(tf.pos)
    }

    return n, err
}
```

### File: bittorrent/player.go

Initialize lookbehind when starting playback:

```go
// ============================================================================
// Add to Buffer() method after file selection
// ============================================================================

func (btp *Player) Buffer() error {
    // ... existing buffer logic that selects chosenFile ...

    // Initialize lookbehind after file is chosen
    if btp.chosenFile != nil && config.Get().LookbehindEnabled {
        duration := btp.getVideoDuration()
        btp.t.InitLookbehind(btp.chosenFile, duration)
    }

    // ... rest of buffer logic ...
}

// ============================================================================
// Add duration helper
// ============================================================================

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

// ============================================================================
// Add cleanup in Close() method
// ============================================================================

func (btp *Player) Close() {
    // ... existing close logic ...

    if btp.t != nil && btp.t.lookbehind != nil {
        btp.t.lookbehind.Clear()
    }
}
```

### File: bittorrent/service.go

Add memory validation on startup:

```go
// ============================================================================
// Add to configure() method
// ============================================================================

func (s *BTService) configure() {
    // ... existing configuration ...

    // Validate memory for lookbehind
    if config.Get().LookbehindEnabled {
        lookbehindSize := config.Get().LookbehindMaxSize

        minMemory := s.config.BufferSize +
                    int(s.config.EndBufferSize) +
                    int(lookbehindSize) +
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

## Part 3: Build Instructions

### Building libtorrent-go

```bash
# Clone the repository
git clone https://github.com/ElementumOrg/libtorrent-go
cd libtorrent-go

# Apply the changes from Part 1

# Build for your platform
make all

# Or build for specific platform
make linux-x64
```

### Building Elementum Daemon

```bash
# Clone the repository
git clone https://github.com/elgatito/elementum
cd elementum

# Apply the changes from Part 2

# Update dependencies
go mod tidy

# Build
make all

# Or for specific platform
make linux-x64
```

---

## Part 4: Testing Checklist

### Unit Tests

- [ ] LookbehindManager.UpdatePosition() correctly calculates piece ranges
- [ ] LookbehindManager.IsAvailable() returns true only for cached pieces
- [ ] Memory cap is enforced at 50% of allocation
- [ ] Config validation disables lookbehind when memory < 10 MB

### Integration Tests

- [ ] Backward seek within lookbehind completes < 2 seconds
- [ ] Backward seek outside lookbehind works (slower)
- [ ] Forward seek unaffected by lookbehind
- [ ] Position updates trigger reserved piece updates
- [ ] Lookbehind clears on playback stop

### Stress Tests

- [ ] Rapid consecutive seeks don't cause deadlock
- [ ] Memory stays within allocation under all settings
- [ ] No piece eviction failures when lookbehind is full

### Edge Case Tests

- [ ] Seek at very start of file (small lookbehind window)
- [ ] Seek past end of file
- [ ] Multi-file torrent switching
- [ ] Very short video (< lookbehind time)

---

## Part 5: Configuration Reference

### Default Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `lookbehind_enabled` | true | Enable lookbehind buffer |
| `lookbehind_time` | 30 | Seconds of content to retain |
| `lookbehind_max_size` | 50 | Maximum MB for lookbehind |
| `auto_adjust_lookbehind` | true | Auto-size based on bitrate |

### Memory Budget Example

```
Total Memory:    100 MB (default memory_size)
Forward Buffer:   20 MB (default buffer_size)
Lookbehind:       50 MB (default lookbehind_max_size)
End Buffer:        4 MB (default end_buffer_size)
Overhead:          8 MB
─────────────────────────
Total Used:       82 MB
Headroom:         18 MB
```

### Performance Expectations

| Scenario | Without Lookbehind | With Lookbehind |
|----------|-------------------|-----------------|
| 10s backward seek | 10-25s freeze | <2s (if cached) |
| 30s backward seek | 15-30s freeze | <2s (if cached) |
| 60s backward seek | 20-40s freeze | <2s (if cached) |
| Beyond lookbehind | Same | Same (re-download) |

---

## Troubleshooting

### Lookbehind Not Working

1. Check if enabled: `lookbehind_enabled` setting
2. Check memory: Must have > 10 MB available after buffers
3. Check logs for "Lookbehind initialized" message

### Still Slow After Enabling

1. Verify piece is in lookbehind window (check logs)
2. Piece may have been evicted before protection was set
3. Increase `lookbehind_max_size` for longer retention

### Memory Errors

1. Reduce `lookbehind_max_size`
2. Increase `memory_size`
3. Lookbehind is capped at 50% of total memory

---

## Version History

- **v1.0** - Initial implementation with conservative defaults
