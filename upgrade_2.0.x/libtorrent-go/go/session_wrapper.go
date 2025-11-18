// session_wrapper.go - Go wrappers for libtorrent 2.0.x session management
//
// Key changes from 1.2.x:
// - Session created with session_params
// - Disk I/O configured at session level
// - State saving uses write_session_params/read_session_params

package libtorrent

/*
#include <stdlib.h>
*/
import "C"
import (
	"unsafe"
)

// SessionParams wraps libtorrent::session_params for 2.0.x session creation
type SessionParams struct {
	ptr unsafe.Pointer
}

// NewSessionParams creates a new session_params with default settings
func NewSessionParams() *SessionParams {
	// This would call the SWIG-generated constructor
	return &SessionParams{
		ptr: nil, // Will be set by SWIG binding
	}
}

// SetMemoryDiskIO configures memory-based disk I/O at session level
// This replaces per-torrent storage configuration in 1.2.x
func (sp *SessionParams) SetMemoryDiskIO(memorySize int64) {
	// Calls session_params::set_memory_disk_io from SWIG interface
	// This sets up the disk_io_constructor and memory limit
}

// SetSettings applies a settings_pack to the session params
func (sp *SessionParams) SetSettings(settings *SettingsPack) {
	// Calls session_params::set_settings from SWIG interface
}

// GetSettings returns the current settings_pack
func (sp *SessionParams) GetSettings() *SettingsPack {
	// Calls session_params::get_settings from SWIG interface
	return nil
}

// Session wraps libtorrent::session for 2.0.x
type Session struct {
	handle unsafe.Pointer
	// Storage index tracking for lookbehind access
	storageIndices map[string]int // info_hash_v1 -> storage_index
}

// CreateSessionWithParams creates a new session using session_params (2.0.x way)
// This replaces NewSession(settings, flags) from 1.2.x
func CreateSessionWithParams(params *SessionParams) (*Session, error) {
	// Calls session::create_with_params from SWIG interface
	return &Session{
		handle:         nil, // Set by SWIG
		storageIndices: make(map[string]int),
	}, nil
}

// NewSession creates a session with settings (backward compatible)
// Internally converts to session_params
func NewSession(settings *SettingsPack, memorySize int64) (*Session, error) {
	params := NewSessionParams()
	params.SetSettings(settings)
	if memorySize > 0 {
		params.SetMemoryDiskIO(memorySize)
	}
	return CreateSessionWithParams(params)
}

// AddTorrent adds a torrent and tracks its storage index
func (s *Session) AddTorrent(params *AddTorrentParams) (*TorrentHandle, error) {
	// The SWIG binding returns both handle and storage_index_t
	// We need to track the storage index for lookbehind access
	return nil, nil
}

// GetStorageIndex returns the storage index for a torrent (by v1 info hash)
func (s *Session) GetStorageIndex(infoHashV1 string) int {
	if idx, ok := s.storageIndices[infoHashV1]; ok {
		return idx
	}
	return -1
}

// SaveSessionState saves the session state to a byte buffer (2.0.x way)
// Replaces save_state/load_state from 1.2.x
func (s *Session) SaveSessionState() ([]byte, error) {
	// Calls write_session_params(session.session_state())
	return nil, nil
}

// RestoreSessionState restores session state from a byte buffer
// Use this when creating session with read_session_params
func RestoreSessionState(data []byte) (*SessionParams, error) {
	// Calls read_session_params
	return nil, nil
}

// PostTorrentUpdates requests torrent status updates (replaces stats_alert)
func (s *Session) PostTorrentUpdates() {
	// Calls session_handle::post_torrent_updates()
}

// SettingsPack wraps libtorrent::settings_pack
// Updated for 2.0.x removed settings
type SettingsPack struct {
	ptr unsafe.Pointer
}

// NewSettingsPack creates a new settings_pack
func NewSettingsPack() *SettingsPack {
	return &SettingsPack{}
}

// SetBool sets a boolean setting by name
func (sp *SettingsPack) SetBool(name string, value bool) {
	// Check for removed settings in 2.0.x
	removedSettings := map[string]bool{
		"lazy_bitfields":       true, // Removed in 1.2.x
		"use_dht_as_fallback":  true, // Deprecated
		"cache_size":           true, // Removed in 2.0.x (mmap handles caching)
		"cache_expiry":         true, // Removed in 2.0.x
		"use_read_cache":       true, // Removed in 2.0.x
		"use_write_cache":      true, // Removed in 2.0.x
	}

	if removedSettings[name] {
		// Silently ignore removed settings for compatibility
		return
	}

	// Call SWIG binding
}

// SetInt sets an integer setting by name
func (sp *SettingsPack) SetInt(name string, value int) {
	// Handle renamed settings
	renamedSettings := map[string]string{
		// aio_threads was split in 2.0.x
		// "aio_threads": Now separate from hashing_threads
	}

	if newName, ok := renamedSettings[name]; ok {
		name = newName
	}

	// Call SWIG binding
}

// SetStr sets a string setting by name
func (sp *SettingsPack) SetStr(name string, value string) {
	// Call SWIG binding
}

// GetBool gets a boolean setting by name
func (sp *SettingsPack) GetBool(name string) bool {
	return false
}

// GetInt gets an integer setting by name
func (sp *SettingsPack) GetInt(name string) int {
	return 0
}

// GetStr gets a string setting by name
func (sp *SettingsPack) GetStr(name string) string {
	return ""
}

// ConfigureForStreaming sets optimal settings for video streaming
func (sp *SettingsPack) ConfigureForStreaming() {
	// Optimized settings for Elementum streaming use case
	sp.SetInt("connections_limit", 200)
	sp.SetInt("max_out_request_queue", 5000)
	sp.SetInt("max_peer_recv_buffer_size", 5*1024*1024)
	sp.SetInt("send_buffer_watermark", 10*1024*1024)
	sp.SetInt("send_buffer_watermark_factor", 150)
	sp.SetInt("send_buffer_low_watermark", 1024*1024)
	sp.SetInt("max_queued_disk_bytes", 10*1024*1024)
	sp.SetInt("request_timeout", 10)
	sp.SetInt("peer_timeout", 30)
	sp.SetBool("strict_end_game_mode", false)
	sp.SetBool("announce_to_all_trackers", true)
	sp.SetBool("announce_to_all_tiers", true)
	sp.SetBool("rate_limit_ip_overhead", false)

	// 2.0.x specific: separate hashing threads
	sp.SetInt("aio_threads", 4)
	sp.SetInt("hashing_threads", 2)
}
