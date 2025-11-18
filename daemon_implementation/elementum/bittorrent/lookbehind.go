// Package bittorrent provides BitTorrent functionality for Elementum
package bittorrent

import (
	"sync"
	"time"

	lt "github.com/ElementumOrg/libtorrent-go"
	"github.com/elgatito/elementum/config"
)

// LookbehindManager manages the lookbehind buffer for fast backward seeking.
// It protects recently played pieces from eviction to enable instant backward seeks.
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
	fileOffset  int64
	duration    float64

	// Memory storage reference
	ms lt.MemoryStorage

	// Thread safety
	mu sync.RWMutex
}

// NewLookbehindManager creates a new lookbehind manager for a torrent file.
// It calculates the appropriate buffer size based on video bitrate and configuration.
func NewLookbehindManager(t *Torrent, fileSize, fileOffset int64, duration float64) *LookbehindManager {
	cfg := config.Get()

	if !cfg.LookbehindEnabled {
		return nil
	}

	lm := &LookbehindManager{
		enabled:     cfg.LookbehindEnabled,
		timeSeconds: cfg.LookbehindTime,
		maxSize:     cfg.LookbehindMaxSize,

		torrent:     t,
		pieceLength: t.ti.PieceLength(),
		numPieces:   t.ti.NumPieces(),
		fileSize:    fileSize,
		fileOffset:  fileOffset,
		duration:    duration,
		ms:          t.ms,

		currentBytePos:  0,
		protectedPieces: make([]int, 0),
	}

	// Calculate actual size based on video bitrate
	lm.sizeBytes = lm.calculateSize(fileSize, duration)

	// Enforce 50% memory cap to leave room for forward buffer
	maxAllowed := t.MemorySize / 2
	if lm.sizeBytes > maxAllowed {
		lm.sizeBytes = maxAllowed
		log.Debugf("Lookbehind capped to %d MB (50%% of memory)", lm.sizeBytes/1024/1024)
	}

	if duration > 0 {
		log.Infof("Lookbehind initialized: %d MB for %ds (bitrate: %.2f MB/s)",
			lm.sizeBytes/1024/1024,
			lm.timeSeconds,
			float64(fileSize)/duration/1024/1024)
	} else {
		log.Infof("Lookbehind initialized: %d MB for %ds",
			lm.sizeBytes/1024/1024,
			lm.timeSeconds)
	}

	return lm
}

// calculateSize determines the lookbehind buffer size based on video bitrate
func (lm *LookbehindManager) calculateSize(fileSize int64, duration float64) int64 {
	if lm.timeSeconds == 0 {
		return 0
	}

	// Calculate bitrate from file size and duration
	var bitrateBps int64
	if duration > 0 {
		bitrateBps = int64(float64(fileSize) / duration)
	} else {
		// Fallback: assume 2.5 MB/s for 1080p content
		bitrateBps = 2500 * 1024
	}

	// Calculate needed size for configured time
	size := bitrateBps * int64(lm.timeSeconds)

	// Cap at configured maximum
	if size > lm.maxSize {
		size = lm.maxSize
	}

	// Minimum useful size
	if size < 10*1024*1024 {
		size = 10 * 1024 * 1024
	}

	return size
}

// UpdatePosition updates protected pieces based on current byte position in file.
// Call this whenever the playback position changes.
func (lm *LookbehindManager) UpdatePosition(fileBytePos int64) {
	if !lm.enabled || lm.ms == nil {
		return
	}

	lm.mu.Lock()
	defer lm.mu.Unlock()

	// Debounce: skip if updated within 100ms
	if time.Since(lm.lastUpdate) < 100*time.Millisecond {
		return
	}

	// Skip if position hasn't changed significantly (1 piece worth)
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

// updateReservedPieces sends the protected pieces list to libtorrent memory storage
func (lm *LookbehindManager) updateReservedPieces() {
	if lm.ms == nil {
		return
	}

	lm.ms.SetLookbehindPieces(lm.protectedPieces)

	if len(lm.protectedPieces) > 0 {
		log.Debugf("Lookbehind: protecting pieces %d-%d (%d pieces, %d MB)",
			lm.protectedPieces[0],
			lm.protectedPieces[len(lm.protectedPieces)-1],
			len(lm.protectedPieces),
			int64(len(lm.protectedPieces))*lm.pieceLength/1024/1024)
	}
}

// IsAvailable checks if a piece is in lookbehind AND actually available in memory.
// Use this to determine if a backward seek will be fast.
func (lm *LookbehindManager) IsAvailable(piece int) bool {
	lm.mu.RLock()
	defer lm.mu.RUnlock()

	if !lm.enabled || lm.ms == nil {
		return false
	}

	return lm.ms.IsLookbehindAvailable(piece)
}

// IsInWindow checks if a piece is within the lookbehind window (may not be cached yet).
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

// GetAvailableCount returns count of protected pieces actually in memory.
func (lm *LookbehindManager) GetAvailableCount() int {
	if lm.ms == nil {
		return 0
	}
	return lm.ms.GetLookbehindAvailableCount()
}

// GetProtectedCount returns count of pieces marked for protection.
func (lm *LookbehindManager) GetProtectedCount() int {
	lm.mu.RLock()
	defer lm.mu.RUnlock()
	return len(lm.protectedPieces)
}

// Clear removes all lookbehind reservations.
// Call when stopping playback or switching files.
func (lm *LookbehindManager) Clear() {
	lm.mu.Lock()
	defer lm.mu.Unlock()

	lm.protectedPieces = make([]int, 0)
	lm.currentBytePos = 0

	if lm.ms != nil {
		lm.ms.ClearLookbehind()
	}

	log.Debug("Lookbehind buffer cleared")
}

// GetStats returns current lookbehind statistics for monitoring.
func (lm *LookbehindManager) GetStats() LookbehindStats {
	lm.mu.RLock()
	defer lm.mu.RUnlock()

	availableCount := 0
	protectedCount := 0
	memoryUsed := int64(0)

	if lm.ms != nil {
		availableCount = lm.ms.GetLookbehindAvailableCount()
		protectedCount = lm.ms.GetLookbehindProtectedCount()
		memoryUsed = lm.ms.GetLookbehindMemoryUsed()
	}

	return LookbehindStats{
		Enabled:         lm.enabled,
		ConfiguredMB:    int(lm.sizeBytes / 1024 / 1024),
		ActualMB:        int(memoryUsed / 1024 / 1024),
		ProtectedPieces: protectedCount,
		AvailablePieces: availableCount,
		TimeSeconds:     lm.timeSeconds,
		CurrentPiece:    int(lm.currentBytePos / lm.pieceLength),
	}
}

// LookbehindStats contains lookbehind buffer statistics for monitoring
type LookbehindStats struct {
	Enabled         bool  `json:"enabled"`
	ConfiguredMB    int   `json:"configured_mb"`
	ActualMB        int   `json:"actual_mb"`
	ProtectedPieces int   `json:"protected_pieces"`
	AvailablePieces int   `json:"available_pieces"`
	TimeSeconds     int   `json:"time_seconds"`
	CurrentPiece    int   `json:"current_piece"`
}

// abs64 returns absolute value of int64
func abs64(x int64) int64 {
	if x < 0 {
		return -x
	}
	return x
}
