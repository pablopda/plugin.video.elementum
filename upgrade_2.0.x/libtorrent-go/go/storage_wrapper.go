// storage_wrapper.go - Go wrappers for libtorrent 2.0.x disk_interface
//
// Key changes from 1.2.x:
// - storage_interface (per-torrent) -> disk_interface (session-level)
// - Access via storage_index_t instead of get_storage_impl()
// - All operations are async with callbacks

package libtorrent

import (
	"sync"

	lt "github.com/ElementumOrg/libtorrent-go"
)

// StorageIndex represents libtorrent::storage_index_t
// This is used to identify a torrent's storage within the session-level disk_interface
type StorageIndex int

// InvalidStorageIndex indicates no valid storage
const InvalidStorageIndex StorageIndex = -1

// MemoryDiskIO provides access to session-level memory disk I/O
// This replaces per-torrent memory_storage access in 1.2.x
type MemoryDiskIO struct {
	// Session that owns this disk I/O
	session *Session

	// Track storage indices for all torrents
	mu      sync.RWMutex
	indices map[string]StorageIndex // info_hash_v1 -> storage_index
}

// NewMemoryDiskIO creates a memory disk I/O accessor
func NewMemoryDiskIO(session *Session) *MemoryDiskIO {
	return &MemoryDiskIO{
		session: session,
		indices: make(map[string]StorageIndex),
	}
}

// RegisterTorrent associates a storage index with an info hash
func (md *MemoryDiskIO) RegisterTorrent(infoHashV1 string, idx StorageIndex) {
	md.mu.Lock()
	defer md.mu.Unlock()
	md.indices[infoHashV1] = idx
}

// UnregisterTorrent removes a torrent's storage index
func (md *MemoryDiskIO) UnregisterTorrent(infoHashV1 string) {
	md.mu.Lock()
	defer md.mu.Unlock()
	delete(md.indices, infoHashV1)
}

// GetStorageIndex returns the storage index for a torrent
func (md *MemoryDiskIO) GetStorageIndex(infoHashV1 string) StorageIndex {
	md.mu.RLock()
	defer md.mu.RUnlock()
	if idx, ok := md.indices[infoHashV1]; ok {
		return idx
	}
	return InvalidStorageIndex
}

// Lookbehind buffer operations
// These call into the global memory_disk_io instance via SWIG wrappers

// SetLookbehindPieces sets the pieces to protect in lookbehind buffer
func SetLookbehindPieces(storageIndex StorageIndex, pieces []int) {
	if storageIndex == InvalidStorageIndex {
		return
	}
	// Convert Go slice to SWIG vector and call memory_disk_set_lookbehind
	pieceVector := lt.NewStdVectorInt()
	defer lt.DeleteStdVectorInt(pieceVector)
	for _, p := range pieces {
		pieceVector.Add(p)
	}
	lt.MemoryDiskSetLookbehind(int(storageIndex), pieceVector)
}

// ClearLookbehind clears all protected pieces for a torrent
func ClearLookbehind(storageIndex StorageIndex) {
	if storageIndex == InvalidStorageIndex {
		return
	}
	// Call SWIG binding to clear lookbehind buffer
	lt.MemoryDiskClearLookbehind(int(storageIndex))
}

// IsLookbehindAvailable checks if a piece is available in lookbehind buffer
func IsLookbehindAvailable(storageIndex StorageIndex, piece int) bool {
	if storageIndex == InvalidStorageIndex {
		return false
	}
	// Call SWIG binding to check if piece is in lookbehind buffer
	return lt.MemoryDiskIsLookbehindAvailable(int(storageIndex), piece)
}

// LookbehindStats holds lookbehind buffer statistics
type LookbehindStats struct {
	Available      int   // Number of pieces available
	ProtectedCount int   // Number of pieces protected
	MemoryUsed     int64 // Memory used in bytes
}

// GetLookbehindStats returns statistics for a torrent's lookbehind buffer
func GetLookbehindStats(storageIndex StorageIndex) LookbehindStats {
	if storageIndex == InvalidStorageIndex {
		return LookbehindStats{}
	}

	// Call SWIG binding to get lookbehind statistics
	swigStats := lt.MemoryDiskGetLookbehindStats(int(storageIndex))
	defer lt.DeleteLookbehindStats(swigStats)

	return LookbehindStats{
		Available:      int(swigStats.GetAvailable()),
		ProtectedCount: int(swigStats.GetProtectedCount()),
		MemoryUsed:     swigStats.GetMemoryUsed(),
	}
}

// TorrentStorage provides a torrent-specific interface to storage operations
// This is a convenience wrapper that holds the storage index
type TorrentStorage struct {
	storageIndex StorageIndex
	infoHashV1   string
}

// NewTorrentStorage creates a storage accessor for a specific torrent
func NewTorrentStorage(infoHashV1 string, idx StorageIndex) *TorrentStorage {
	return &TorrentStorage{
		storageIndex: idx,
		infoHashV1:   infoHashV1,
	}
}

// SetLookbehindPieces sets lookbehind pieces for this torrent
func (ts *TorrentStorage) SetLookbehindPieces(pieces []int) {
	SetLookbehindPieces(ts.storageIndex, pieces)
}

// ClearLookbehind clears lookbehind for this torrent
func (ts *TorrentStorage) ClearLookbehind() {
	ClearLookbehind(ts.storageIndex)
}

// IsLookbehindAvailable checks if piece is in lookbehind
func (ts *TorrentStorage) IsLookbehindAvailable(piece int) bool {
	return IsLookbehindAvailable(ts.storageIndex, piece)
}

// GetStats returns lookbehind stats for this torrent
func (ts *TorrentStorage) GetStats() LookbehindStats {
	return GetLookbehindStats(ts.storageIndex)
}

// StorageIndex returns the storage index
func (ts *TorrentStorage) StorageIndex() StorageIndex {
	return ts.storageIndex
}

// Migration helpers for updating from 1.2.x code

// GetMemoryStorage is a compatibility shim
// In 1.2.x: th.GetMemoryStorage() returned per-torrent storage
// In 2.0.x: Returns a TorrentStorage that accesses session-level disk_interface
//
// Deprecated: Use NewTorrentStorage with storage index instead
func GetMemoryStorage(th *TorrentHandle, session *Session) *TorrentStorage {
	infoHashV1 := th.InfoHashV1String()
	idx := session.GetStorageIndex(infoHashV1)
	return NewTorrentStorage(infoHashV1, StorageIndex(idx))
}
