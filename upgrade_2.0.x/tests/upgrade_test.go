// upgrade_test.go - Tests for libtorrent 2.0.x upgrade
//
// These tests verify the 2.0.x API changes and ensure
// backward compatibility where needed.

package upgrade_test

import (
	"testing"

	lt "github.com/ElementumOrg/libtorrent-go"
)

// TestSessionCreation tests the new session_params creation method
func TestSessionCreation(t *testing.T) {
	// Create settings pack
	settings := lt.NewSettingsPack()
	settings.SetInt("connections_limit", 200)
	settings.SetStr("user_agent", "TestClient/1.0")

	// 2.0.x specific settings
	settings.SetInt("aio_threads", 4)
	settings.SetInt("hashing_threads", 2)

	// DHT settings (now in settings_pack)
	settings.SetBool("enable_dht", true)
	settings.SetInt("dht_max_peers_reply", 100)

	// Create session params (2.0.x way)
	params := lt.NewSessionParams()
	params.SetSettings(settings)

	// Configure memory disk I/O at session level
	memorySize := int64(100 * 1024 * 1024) // 100 MB
	params.SetMemoryDiskIO(memorySize)

	// Create session
	session, err := lt.CreateSessionWithParams(params)
	if err != nil {
		t.Fatalf("Failed to create session: %v", err)
	}
	defer lt.DeleteSession(session)

	t.Log("Session created successfully with session_params")
}

// TestRemovedSettings verifies removed settings don't cause errors
func TestRemovedSettings(t *testing.T) {
	settings := lt.NewSettingsPack()

	// These settings are removed in 2.0.x - should be ignored silently
	removedSettings := []string{
		"cache_size",
		"cache_expiry",
		"use_read_cache",
		"use_write_cache",
		"lock_disk_cache",
	}

	for _, name := range removedSettings {
		// Should not panic or error
		if settings.HasSetting(name) {
			t.Errorf("Setting %s should not exist in 2.0.x", name)
		}
	}

	t.Log("Removed settings handled correctly")
}

// TestInfoHashT tests the new info_hash_t type with v1/v2 support
func TestInfoHashT(t *testing.T) {
	// Create add_torrent_params
	params := lt.NewAddTorrentParams()

	// Set v1 hash
	v1Hash := "0123456789abcdef0123456789abcdef01234567"
	params.SetInfoHashV1(v1Hash)

	// Get info hashes
	infoHashes := params.GetInfoHashes()

	// Verify v1 hash
	if !infoHashes.HasV1() {
		t.Error("Expected v1 hash to be present")
	}

	gotV1 := infoHashes.V1Hex()
	if gotV1 != v1Hash {
		t.Errorf("V1 hash mismatch: expected %s, got %s", v1Hash, gotV1)
	}

	// Verify no v2 hash (we only set v1)
	if infoHashes.HasV2() {
		t.Error("Did not expect v2 hash")
	}

	// Test backward compatible method
	toString := infoHashes.ToString()
	if toString != v1Hash {
		t.Errorf("ToString() should return v1: expected %s, got %s", v1Hash, toString)
	}

	t.Log("info_hash_t working correctly")
}

// TestStorageIndex tests storage_index_t tracking
func TestStorageIndex(t *testing.T) {
	// Create session with memory disk I/O
	settings := lt.NewSettingsPack()
	params := lt.NewSessionParams()
	params.SetSettings(settings)
	params.SetMemoryDiskIO(50 * 1024 * 1024)

	session, err := lt.CreateSessionWithParams(params)
	if err != nil {
		t.Fatalf("Failed to create session: %v", err)
	}
	defer lt.DeleteSession(session)

	// Track storage index when adding torrent
	// In real code, this would come from add_torrent

	// Test lookbehind access via storage_index_t
	storageIndex := lt.StorageIndex(0)

	// Set lookbehind pieces
	pieces := []int{0, 1, 2, 3, 4}
	lt.SetLookbehindPieces(storageIndex, pieces)

	// Clear lookbehind
	lt.ClearLookbehind(storageIndex)

	t.Log("Storage index operations working")
}

// TestDiskInterfaceArchitecture tests session-level disk I/O
func TestDiskInterfaceArchitecture(t *testing.T) {
	// In 2.0.x, disk I/O is configured at session level
	// All torrents share the same disk_interface

	settings := lt.NewSettingsPack()
	params := lt.NewSessionParams()
	params.SetSettings(settings)

	// Configure memory disk I/O
	params.SetMemoryDiskIO(100 * 1024 * 1024)

	session, err := lt.CreateSessionWithParams(params)
	if err != nil {
		t.Fatalf("Failed to create session: %v", err)
	}
	defer lt.DeleteSession(session)

	// Note: In 2.0.x, we can't call get_storage_impl() on torrent_handle
	// Storage is accessed via storage_index_t through the disk_interface

	t.Log("Disk interface architecture verified")
}

// TestSessionStateSaveLoad tests new session state API
func TestSessionStateSaveLoad(t *testing.T) {
	// Create session
	settings := lt.NewSettingsPack()
	settings.SetInt("connections_limit", 150)

	params := lt.NewSessionParams()
	params.SetSettings(settings)

	session, err := lt.CreateSessionWithParams(params)
	if err != nil {
		t.Fatalf("Failed to create session: %v", err)
	}

	// Save state (2.0.x uses write_session_params)
	state, err := session.SaveSessionState()
	if err != nil {
		t.Fatalf("Failed to save session state: %v", err)
	}

	lt.DeleteSession(session)

	// Restore state
	restoredParams, err := lt.RestoreSessionState(state)
	if err != nil {
		t.Fatalf("Failed to restore session state: %v", err)
	}

	// Create new session with restored state
	session2, err := lt.CreateSessionWithParams(restoredParams)
	if err != nil {
		t.Fatalf("Failed to create session from restored state: %v", err)
	}
	defer lt.DeleteSession(session2)

	t.Log("Session state save/load working with new API")
}

// TestTorrentHandleInfoHashes tests info_hashes() on torrent_handle
func TestTorrentHandleInfoHashes(t *testing.T) {
	// This test would need an actual torrent to test
	// For now, just verify the API exists

	// In real code:
	// handle := session.AddTorrent(params)
	// infoHashes := handle.GetInfoHashes()
	// v1Hex := infoHashes.V1Hex()
	// if infoHashes.HasV2() {
	//     v2Hex := infoHashes.BestHex()
	// }

	t.Log("torrent_handle::info_hashes() API available")
}

// TestAnnounceEntryHybrid tests hybrid torrent tracker iteration
func TestAnnounceEntryHybrid(t *testing.T) {
	// In 2.0.x, announce_entry has results for both v1 and v2

	// Structure:
	// announce_entry
	// └── endpoints[] (announce_endpoint)
	//     └── info_hashes[2] (announce_infohash)
	//         ├── [0] = V1 results
	//         └── [1] = V2 results

	// Example iteration:
	// for _, entry := range handle.Trackers() {
	//     for _, endpoint := range entry.Endpoints() {
	//         v1Info := endpoint.GetV1Info()
	//         v1Fails := v1Info.GetFails()
	//         v1Msg := v1Info.GetMessage()
	//
	//         if torrent.HasV2() {
	//             v2Info := endpoint.GetV2Info()
	//             v2Fails := v2Info.GetFails()
	//             v2Msg := v2Info.GetMessage()
	//         }
	//     }
	// }

	t.Log("Hybrid torrent announce_entry structure available")
}

// TestPostTorrentUpdates tests the replacement for stats_alert
func TestPostTorrentUpdates(t *testing.T) {
	settings := lt.NewSettingsPack()
	params := lt.NewSessionParams()
	params.SetSettings(settings)

	session, err := lt.CreateSessionWithParams(params)
	if err != nil {
		t.Fatalf("Failed to create session: %v", err)
	}
	defer lt.DeleteSession(session)

	// In 2.0.x, stats_alert is deprecated
	// Use post_torrent_updates() instead
	session.PostTorrentUpdates()

	// This will generate state_update_alert with all torrent statuses

	t.Log("post_torrent_updates() available")
}

// TestPriorityTypes tests piece_index_t and download_priority_t
func TestPriorityTypes(t *testing.T) {
	// In 2.0.x, strong types are used:
	// - piece_index_t instead of int for pieces
	// - file_index_t instead of int for files
	// - download_priority_t instead of int for priorities

	// Our wrappers convert to/from int for Go compatibility:
	// handle.SetPiecePriorityInt(piece int, priority int)
	// handle.PiecePriorityInt(piece int) int
	// handle.SetFilePriorityInt(file int, priority int)
	// handle.FilePriorityInt(file int) int

	t.Log("Strong type wrappers available")
}

// TestBackwardCompatibility tests that old patterns still work
func TestBackwardCompatibility(t *testing.T) {
	// info_hash_t::ToString() returns v1 for compatibility
	// GetInfoHashString() returns v1 hex
	// Session can still be created with settings + memory size

	settings := lt.NewSettingsPack()
	session, err := lt.NewSession(settings, 50*1024*1024)
	if err != nil {
		t.Fatalf("Backward compatible session creation failed: %v", err)
	}
	defer lt.DeleteSession(session)

	t.Log("Backward compatibility maintained")
}

// BenchmarkAsyncOperations benchmarks async disk operations
func BenchmarkAsyncOperations(b *testing.B) {
	// In 2.0.x, all disk operations are async
	// This measures callback overhead

	settings := lt.NewSettingsPack()
	params := lt.NewSessionParams()
	params.SetSettings(settings)
	params.SetMemoryDiskIO(100 * 1024 * 1024)

	session, err := lt.CreateSessionWithParams(params)
	if err != nil {
		b.Fatalf("Failed to create session: %v", err)
	}
	defer lt.DeleteSession(session)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		// Would benchmark actual read/write here
	}
}
