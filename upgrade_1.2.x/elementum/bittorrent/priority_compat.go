/*
 * priority_compat.go - Compatibility helpers for 1.2.x priority types
 *
 * These functions provide backward compatibility for priority operations
 * when upgrading from libtorrent 1.1.x to 1.2.x.
 */

package bittorrent

import (
	lt "github.com/ElementumOrg/libtorrent-go"
)

// Priority constants matching libtorrent 1.2.x
const (
	PriorityDontDownload = 0
	PriorityLow          = 1
	PriorityDefault      = 4
	PriorityTop          = 7
)

// SetPiecePriority sets piece priority using int (backward compatible)
// Use this instead of direct t.th.PiecePriority(piece, priority)
func (t *Torrent) SetPiecePriority(piece int, priority int) {
	// In 1.2.x, use the int-based wrapper
	t.th.SetPiecePriorityInt(piece, priority)
}

// GetPiecePriority gets piece priority as int (backward compatible)
// Use this instead of direct t.th.PiecePriority(piece).(int)
func (t *Torrent) GetPiecePriority(piece int) int {
	// In 1.2.x, use the int-based wrapper
	return t.th.GetPiecePriorityInt(piece)
}

// SetFilePriority sets file priority using int (backward compatible)
// Use this instead of direct t.th.FilePriority(file, priority)
func (t *Torrent) SetFilePriority(file int, priority int) {
	// In 1.2.x, use the int-based wrapper
	t.th.SetFilePriorityInt(file, priority)
}

// GetFilePriority gets file priority as int (backward compatible)
func (t *Torrent) GetFilePriority(file int) int {
	return t.th.GetFilePriorityInt(file)
}

// GetActiveTime returns active time in seconds (backward compatible)
// In 1.2.x, this field changed to chrono::duration
func GetActiveTime(ts lt.TorrentStatus) int64 {
	return ts.GetActiveTimeSeconds()
}

// GetFinishedTime returns finished time in seconds (backward compatible)
func GetFinishedTime(ts lt.TorrentStatus) int64 {
	return ts.GetFinishedTimeSeconds()
}

// GetSeedingTime returns seeding time in seconds (backward compatible)
func GetSeedingTime(ts lt.TorrentStatus) int64 {
	return ts.GetSeedingTimeSeconds()
}
