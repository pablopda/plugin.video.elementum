// torrent_2.0.x.go - Torrent wrapper updates for libtorrent 2.0.x
//
// This file contains the updated Torrent implementation for 2.0.x.
// Key changes:
// - info_hash() -> info_hashes() with v1/v2 support
// - get_storage_impl() removed, use storage_index_t
// - Lookbehind access through session-level disk_interface

package bittorrent

import (
	lt "github.com/ElementumOrg/libtorrent-go"
)

// Torrent wraps a libtorrent torrent_handle with Elementum functionality
type Torrent struct {
	Handle       *lt.TorrentHandle
	InfoHashV1   string
	StorageIndex lt.StorageIndex
	service      *BTService

	// Playback state
	IsPlaying    bool
	ReaderOffset int64
	ReaderPiece  int
}

// GetInfoHashes returns the info_hash_t for this torrent (2.0.x)
func (t *Torrent) GetInfoHashes() *lt.InfoHashT {
	return t.Handle.GetInfoHashes()
}

// GetInfoHashV1 returns the v1 info hash as hex string
func (t *Torrent) GetInfoHashV1() string {
	return t.InfoHashV1
}

// GetInfoHashBest returns the best available hash (prefers v2)
func (t *Torrent) GetInfoHashBest() string {
	return t.Handle.InfoHashBestString()
}

// IsHybrid returns true if this is a hybrid v1/v2 torrent
func (t *Torrent) IsHybrid() bool {
	return t.Handle.HasV1() && t.Handle.HasV2()
}

// HasV2 returns true if this torrent has a v2 hash
func (t *Torrent) HasV2() bool {
	return t.Handle.HasV2()
}

// GetStatus returns the torrent status
func (t *Torrent) GetStatus() *lt.TorrentStatus {
	return t.Handle.Status()
}

// Piece operations with strong types (piece_index_t)

// SetPiecePriority sets priority for a piece
func (t *Torrent) SetPiecePriority(piece int, priority int) {
	t.Handle.SetPiecePriorityInt(piece, priority)
}

// GetPiecePriority gets priority for a piece
func (t *Torrent) GetPiecePriority(piece int) int {
	return t.Handle.PiecePriorityInt(piece)
}

// SetPieceDeadline sets deadline for a piece
func (t *Torrent) SetPieceDeadline(piece int, deadline int) {
	t.Handle.SetPieceDeadlineInt(piece, deadline)
}

// ResetPieceDeadline resets deadline for a piece
func (t *Torrent) ResetPieceDeadline(piece int) {
	t.Handle.ResetPieceDeadlineInt(piece)
}

// ClearPieceDeadlines clears all piece deadlines
func (t *Torrent) ClearPieceDeadlines() {
	t.Handle.ClearPieceDeadlines()
}

// File operations with strong types (file_index_t)

// SetFilePriority sets priority for a file
func (t *Torrent) SetFilePriority(file int, priority int) {
	t.Handle.SetFilePriorityInt(file, priority)
}

// GetFilePriority gets priority for a file
func (t *Torrent) GetFilePriority(file int) int {
	return t.Handle.FilePriorityInt(file)
}

// Lookbehind buffer operations (2.0.x - via session-level disk_interface)

// SetLookbehindPieces sets pieces to protect in lookbehind buffer
func (t *Torrent) SetLookbehindPieces(pieces []int) {
	lt.SetLookbehindPieces(t.StorageIndex, pieces)
}

// ClearLookbehind clears all protected pieces
func (t *Torrent) ClearLookbehind() {
	lt.ClearLookbehind(t.StorageIndex)
}

// IsLookbehindAvailable checks if piece is in lookbehind buffer
func (t *Torrent) IsLookbehindAvailable(piece int) bool {
	return lt.IsLookbehindAvailable(t.StorageIndex, piece)
}

// GetLookbehindStats returns lookbehind buffer statistics
func (t *Torrent) GetLookbehindStats() lt.LookbehindStats {
	return lt.GetLookbehindStats(t.StorageIndex)
}

// Timing helpers (chrono -> int64 seconds)

// GetActiveTime returns active time in seconds
func (t *Torrent) GetActiveTime() int64 {
	return t.GetStatus().GetActiveTimeSeconds()
}

// GetFinishedTime returns finished time in seconds
func (t *Torrent) GetFinishedTime() int64 {
	return t.GetStatus().GetFinishedTimeSeconds()
}

// GetSeedingTime returns seeding time in seconds
func (t *Torrent) GetSeedingTime() int64 {
	return t.GetStatus().GetSeedingTimeSeconds()
}

// Tracker operations (updated for hybrid torrent support)

// TrackerInfo holds announce results for a tracker
type TrackerInfo struct {
	URL       string
	Tier      int
	V1Fails   int
	V1Message string
	V2Fails   int
	V2Message string
}

// GetTrackers returns tracker information (updated for 2.0.x hybrid support)
func (t *Torrent) GetTrackers() []TrackerInfo {
	var trackers []TrackerInfo

	// In 2.0.x, announce_entry structure changed for hybrid torrents
	// Each tracker has results for both v1 and v2 announcements
	entries := t.Handle.Trackers()
	for i := 0; i < entries.Size(); i++ {
		entry := entries.Get(i)
		info := TrackerInfo{
			URL:  entry.GetUrl(),
			Tier: entry.GetTier(),
		}

		// Get endpoints and their v1/v2 announce results
		endpoints := entry.Endpoints()
		if endpoints.Size() > 0 {
			ep := endpoints.Get(0)

			// V1 announce info
			v1Info := ep.GetV1Info()
			info.V1Fails = v1Info.GetFails()
			info.V1Message = v1Info.GetMessage()

			// V2 announce info (for hybrid torrents)
			if t.HasV2() {
				v2Info := ep.GetV2Info()
				info.V2Fails = v2Info.GetFails()
				info.V2Message = v2Info.GetMessage()
			}
		}

		trackers = append(trackers, info)
	}

	return trackers
}

// Resume data operations

// SaveResumeData requests resume data save
func (t *Torrent) SaveResumeData() {
	t.Handle.SaveResumeData()
}

// Control operations

// Pause pauses the torrent
func (t *Torrent) Pause() {
	t.Handle.Pause()
}

// Resume resumes the torrent
func (t *Torrent) Resume() {
	t.Handle.Resume()
}

// ForceRecheck forces a recheck of all pieces
func (t *Torrent) ForceRecheck() {
	t.Handle.ForceRecheck()
}

// ForceReannounce forces tracker reannounce
func (t *Torrent) ForceReannounce() {
	t.Handle.ForceReannounce()
}

// SetSequentialDownload enables/disables sequential download
func (t *Torrent) SetSequentialDownload(sequential bool) {
	t.Handle.SetSequentialDownload(sequential)
}

// Backward compatibility helpers

// GetMemoryStorage returns a compatibility shim for 1.2.x code
// Deprecated: Use SetLookbehindPieces etc. directly
func (t *Torrent) GetMemoryStorage() *lt.TorrentStorage {
	return lt.NewTorrentStorage(t.InfoHashV1, t.StorageIndex)
}
