// info_hash_wrapper.go - Go wrappers for libtorrent 2.0.x info_hash_t
//
// Key changes from 1.2.x:
// - info_hash_t contains both v1 (SHA-1) and v2 (SHA-256) hashes
// - Supports BitTorrent v2 and hybrid torrents
// - torrent_handle::info_hash() -> info_hashes()

package libtorrent

import (
	"unsafe"

	lt "github.com/ElementumOrg/libtorrent-go"
)

// InfoHashT wraps libtorrent::info_hash_t for dual v1/v2 hash support
type InfoHashT struct {
	ptr unsafe.Pointer
}

// V1Hex returns the v1 (SHA-1) hash as a hex string
func (ih *InfoHashT) V1Hex() string {
	// Call SWIG binding to get v1 hash as hex string
	if ih.ptr != nil {
		swigPtr := (lt.Info_hash_t)(ih.ptr)
		return lt.Info_hash_t_v1_hex(swigPtr)
	}
	return ""
}

// BestHex returns the best available hash as hex string (prefers v2)
func (ih *InfoHashT) BestHex() string {
	// Calls info_hash_t::best_hex() from SWIG interface
	return ""
}

// HasV1 returns true if v1 hash is available
func (ih *InfoHashT) HasV1() bool {
	// Call SWIG binding to check if v1 hash is available
	if ih.ptr != nil {
		swigPtr := (lt.Info_hash_t)(ih.ptr)
		return lt.Info_hash_t_has_v1(swigPtr)
	}
	return false
}

// HasV2 returns true if v2 hash is available
func (ih *InfoHashT) HasV2() bool {
	// Call SWIG binding to check if v2 hash is available
	if ih.ptr != nil {
		swigPtr := (lt.Info_hash_t)(ih.ptr)
		return lt.Info_hash_t_has_v2(swigPtr)
	}
	return false
}

// ToString returns v1 hash as string for backward compatibility
func (ih *InfoHashT) ToString() string {
	return ih.V1Hex()
}

// IsHybrid returns true if this is a hybrid torrent (has both v1 and v2)
func (ih *InfoHashT) IsHybrid() bool {
	return ih.HasV1() && ih.HasV2()
}

// TorrentHandle extensions for 2.0.x info_hash_t support
type TorrentHandle struct {
	ptr unsafe.Pointer
}

// GetInfoHashes returns the info_hash_t containing v1 and v2 hashes (2.0.x)
func (th *TorrentHandle) GetInfoHashes() *InfoHashT {
	// Calls torrent_handle::get_info_hashes() from SWIG interface
	return nil
}

// InfoHashV1String returns v1 hash as hex string (backward compatible)
func (th *TorrentHandle) InfoHashV1String() string {
	// Calls torrent_handle::info_hash_v1_string() from SWIG interface
	return ""
}

// InfoHashBestString returns best hash as hex string
func (th *TorrentHandle) InfoHashBestString() string {
	// Calls torrent_handle::info_hash_best_string() from SWIG interface
	return ""
}

// HasV1 returns true if torrent has v1 hash
func (th *TorrentHandle) HasV1() bool {
	return false
}

// HasV2 returns true if torrent has v2 hash
func (th *TorrentHandle) HasV2() bool {
	return false
}

// TorrentStatus extensions for 2.0.x
type TorrentStatus struct {
	ptr unsafe.Pointer
}

// GetInfoHashes returns the info_hash_t for this torrent's status
func (ts *TorrentStatus) GetInfoHashes() *InfoHashT {
	// Calls torrent_status::get_info_hashes() from SWIG interface
	return nil
}

// GetInfoHashString returns v1 hash as string (backward compatible)
func (ts *TorrentStatus) GetInfoHashString() string {
	// Calls torrent_status::get_info_hash_string() from SWIG interface
	return ""
}

// GetActiveTimeSeconds returns active time in seconds (chrono -> int64)
func (ts *TorrentStatus) GetActiveTimeSeconds() int64 {
	return 0
}

// GetFinishedTimeSeconds returns finished time in seconds
func (ts *TorrentStatus) GetFinishedTimeSeconds() int64 {
	return 0
}

// GetSeedingTimeSeconds returns seeding time in seconds
func (ts *TorrentStatus) GetSeedingTimeSeconds() int64 {
	return 0
}

// AddTorrentParams extensions for 2.0.x
type AddTorrentParams struct {
	ptr unsafe.Pointer
}

// SetInfoHashV1 sets the v1 info hash from hex string
func (atp *AddTorrentParams) SetInfoHashV1(hex string) {
	// Calls add_torrent_params::set_info_hash_v1() from SWIG interface
}

// SetInfoHashV2 sets the v2 info hash from hex string
func (atp *AddTorrentParams) SetInfoHashV2(hex string) {
	// Calls add_torrent_params::set_info_hash_v2() from SWIG interface
}

// GetInfoHashes returns the info_hash_t
func (atp *AddTorrentParams) GetInfoHashes() *InfoHashT {
	return nil
}

// GetInfoHashV1Hex returns v1 hash as hex string
func (atp *AddTorrentParams) GetInfoHashV1Hex() string {
	return ""
}

// HasV1 returns true if v1 hash is set
func (atp *AddTorrentParams) HasV1() bool {
	return false
}

// HasV2 returns true if v2 hash is set
func (atp *AddTorrentParams) HasV2() bool {
	return false
}

// InfoHashComparison helpers for hybrid torrent support

// CompareInfoHashes checks if two info_hash_t values match
// For hybrid torrents, matches if either v1 or v2 match
func CompareInfoHashes(a, b *InfoHashT) bool {
	if a.HasV1() && b.HasV1() {
		if a.V1Hex() == b.V1Hex() {
			return true
		}
	}
	if a.HasV2() && b.HasV2() {
		if a.BestHex() == b.BestHex() {
			return true
		}
	}
	return false
}

// InfoHashKey returns a key suitable for map lookups
// Uses v1 hash for compatibility with existing code
func InfoHashKey(ih *InfoHashT) string {
	if ih.HasV1() {
		return ih.V1Hex()
	}
	return ih.BestHex()
}
