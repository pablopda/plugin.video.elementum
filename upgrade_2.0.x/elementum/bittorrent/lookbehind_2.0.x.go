// lookbehind_2.0.x.go - Lookbehind buffer manager for libtorrent 2.0.x
//
// Key changes from 1.2.x:
// - Access via storage_index_t instead of get_storage_impl()
// - All operations go through session-level disk_interface

package bittorrent

import (
	"sync"

	lt "github.com/ElementumOrg/libtorrent-go"
)

// LookbehindManager manages the lookbehind buffer for video streaming
type LookbehindManager struct {
	torrent *Torrent
	config  *LookbehindConfig

	mu              sync.RWMutex
	currentPiece    int
	protectedPieces []int
	isEnabled       bool
}

// LookbehindConfig holds lookbehind buffer configuration
type LookbehindConfig struct {
	// Number of pieces to keep behind current position
	BufferSize int

	// Minimum buffer before enabling lookbehind
	MinBuffer int

	// Whether to enable lookbehind at all
	Enabled bool
}

// DefaultLookbehindConfig returns default configuration
func DefaultLookbehindConfig() *LookbehindConfig {
	return &LookbehindConfig{
		BufferSize: 10,
		MinBuffer:  5,
		Enabled:    true,
	}
}

// NewLookbehindManager creates a new lookbehind manager
func NewLookbehindManager(torrent *Torrent, config *LookbehindConfig) *LookbehindManager {
	if config == nil {
		config = DefaultLookbehindConfig()
	}

	return &LookbehindManager{
		torrent:         torrent,
		config:          config,
		protectedPieces: make([]int, 0, config.BufferSize),
		isEnabled:       config.Enabled,
	}
}

// updatePositionLocked is the internal version called with lock already held
func (lm *LookbehindManager) updatePositionLocked(currentPiece int) {
	if currentPiece == lm.currentPiece {
		return
	}

	lm.currentPiece = currentPiece

	// Calculate pieces to protect (behind current position)
	startPiece := currentPiece - lm.config.BufferSize
	if startPiece < 0 {
		startPiece = 0
	}

	// Build list of pieces to protect
	lm.protectedPieces = lm.protectedPieces[:0]
	for piece := startPiece; piece < currentPiece; piece++ {
		lm.protectedPieces = append(lm.protectedPieces, piece)
	}

	// Update storage via disk_interface (2.0.x)
	lm.torrent.SetLookbehindPieces(lm.protectedPieces)
}

// UpdatePosition updates the lookbehind buffer based on current playback position
func (lm *LookbehindManager) UpdatePosition(currentPiece int) {
	if !lm.isEnabled {
		return
	}

	lm.mu.Lock()
	defer lm.mu.Unlock()

	lm.updatePositionLocked(currentPiece)
}

// Clear clears the lookbehind buffer
func (lm *LookbehindManager) Clear() {
	lm.mu.Lock()
	defer lm.mu.Unlock()

	lm.protectedPieces = lm.protectedPieces[:0]
	lm.currentPiece = 0
	lm.torrent.ClearLookbehind()
}

// IsAvailable checks if a piece is available in the lookbehind buffer
func (lm *LookbehindManager) IsAvailable(piece int) bool {
	return lm.torrent.IsLookbehindAvailable(piece)
}

// GetStats returns lookbehind buffer statistics
func (lm *LookbehindManager) GetStats() lt.LookbehindStats {
	return lm.torrent.GetLookbehindStats()
}

// GetProtectedPieces returns the list of currently protected pieces
func (lm *LookbehindManager) GetProtectedPieces() []int {
	lm.mu.RLock()
	defer lm.mu.RUnlock()

	result := make([]int, len(lm.protectedPieces))
	copy(result, lm.protectedPieces)
	return result
}

// SetEnabled enables or disables lookbehind buffer
func (lm *LookbehindManager) SetEnabled(enabled bool) {
	lm.mu.Lock()
	defer lm.mu.Unlock()

	if lm.isEnabled == enabled {
		return
	}

	lm.isEnabled = enabled
	if !enabled {
		lm.torrent.ClearLookbehind()
	}
}

// IsEnabled returns whether lookbehind is enabled
func (lm *LookbehindManager) IsEnabled() bool {
	lm.mu.RLock()
	defer lm.mu.RUnlock()
	return lm.isEnabled
}

// SetBufferSize updates the buffer size
func (lm *LookbehindManager) SetBufferSize(size int) {
	lm.mu.Lock()
	defer lm.mu.Unlock()

	lm.config.BufferSize = size
	// Re-calculate protected pieces with new size
	if len(lm.protectedPieces) > 0 {
		lm.updatePositionLocked(lm.currentPiece)
	}
}

// GetBufferSize returns the current buffer size
func (lm *LookbehindManager) GetBufferSize() int {
	lm.mu.RLock()
	defer lm.mu.RUnlock()
	return lm.config.BufferSize
}
