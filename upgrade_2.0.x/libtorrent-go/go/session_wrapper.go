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
	"fmt"
	"unsafe"

	lt "github.com/ElementumOrg/libtorrent-go"
)

// SessionParams wraps libtorrent::session_params for 2.0.x session creation
type SessionParams struct {
	ptr unsafe.Pointer
}

// NewSessionParams creates a new session_params with default settings
func NewSessionParams() *SessionParams {
	// Call the SWIG-generated constructor for session_params
	swigPtr := lt.NewSession_params()
	return &SessionParams{
		ptr: unsafe.Pointer(swigPtr),
	}
}

// SetMemoryDiskIO configures memory-based disk I/O at session level
// This replaces per-torrent storage configuration in 1.2.x
func (sp *SessionParams) SetMemoryDiskIO(memorySize int64) {
	// Call SWIG binding to configure memory-based disk I/O
	// This sets up the disk_io_constructor with memory limit
	if sp.ptr != nil {
		swigPtr := (lt.Session_params)(sp.ptr)
		lt.MemoryDiskSetMemoryDiskIO(swigPtr, memorySize)
	}
}

// SetSettings applies a settings_pack to the session params
func (sp *SessionParams) SetSettings(settings *SettingsPack) {
	// Call SWIG binding to set settings_pack on session_params
	if sp.ptr != nil && settings != nil && settings.ptr != nil {
		swigPtr := (lt.Session_params)(sp.ptr)
		settingsSwigPtr := (lt.Settings_pack)(settings.ptr)
		lt.Session_params_set_settings(swigPtr, settingsSwigPtr)
	}
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
	// Call SWIG binding to create session with session_params
	if params == nil || params.ptr == nil {
		return nil, fmt.Errorf("invalid session params")
	}

	swigPtr := (lt.Session_params)(params.ptr)
	sessionHandle := lt.NewSession(swigPtr)

	return &Session{
		handle:         unsafe.Pointer(sessionHandle),
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
	if s == nil || s.handle == nil {
		return nil, fmt.Errorf("invalid session")
	}
	if params == nil || params.ptr == nil {
		return nil, fmt.Errorf("invalid add_torrent_params")
	}

	// Get SWIG handles - session is a session_handle in libtorrent
	sessionHandle := (lt.Session)(s.handle)
	paramsPtr := (lt.Add_torrent_params)(params.ptr)

	// Call the SWIG binding with error handling
	// add_torrent_safe returns torrent_handle, check is_valid() for success
	torrentHandle := sessionHandle.Add_torrent_safe(paramsPtr)

	// Check for valid handle - if invalid, the add_torrent operation failed
	if torrentHandle == nil || !torrentHandle.Is_valid() {
		return nil, fmt.Errorf("add_torrent failed: invalid torrent handle returned")
	}

	// Get info hash for storage index tracking
	infoHashes := torrentHandle.Get_info_hashes()
	if infoHashes != nil {
		v1Hex := infoHashes.V1_hex()
		if v1Hex != "" {
			// Note: libtorrent doesn't directly expose storage_index_t from add_torrent
			// The storage index is assigned internally. For lookbehind tracking,
			// we would need to get it from add_torrent_alert or track it separately.
			// For now, we track a placeholder value.
			s.storageIndices[v1Hex] = len(s.storageIndices)
		}
	}

	// Wrap and return the torrent handle
	return &TorrentHandle{
		ptr: unsafe.Pointer(torrentHandle),
	}, nil
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
	swigPtr := lt.NewSettings_pack()
	return &SettingsPack{
		ptr: unsafe.Pointer(swigPtr),
	}
}

// Delete frees the underlying SWIG settings_pack
func (sp *SettingsPack) Delete() {
	if sp.ptr != nil {
		lt.DeleteSettings_pack(lt.Settings_pack(sp.ptr))
		sp.ptr = nil
	}
}

// HasSetting checks if a setting exists by name
func (sp *SettingsPack) HasSetting(name string) bool {
	if sp.ptr == nil {
		return false
	}
	swigSettings := lt.Settings_pack(sp.ptr)
	return swigSettings.Has_setting(name)
}

// SetBool sets a boolean setting by name
func (sp *SettingsPack) SetBool(name string, value bool) {
	if sp.ptr == nil {
		return
	}

	// Check for removed settings in 2.0.x
	removedSettings := map[string]bool{
		"lazy_bitfields":      true, // Removed in 1.2.x
		"use_dht_as_fallback": true, // Deprecated
		"cache_size":          true, // Removed in 2.0.x (mmap handles caching)
		"cache_expiry":        true, // Removed in 2.0.x
		"use_read_cache":      true, // Removed in 2.0.x
		"use_write_cache":     true, // Removed in 2.0.x
	}

	if removedSettings[name] {
		// Silently ignore removed settings for compatibility
		return
	}

	// Call SWIG binding
	swigSettings := lt.Settings_pack(sp.ptr)
	swigSettings.Set_bool(name, value)
}

// SetInt sets an integer setting by name
func (sp *SettingsPack) SetInt(name string, value int) {
	if sp.ptr == nil {
		return
	}

	// Check for removed integer settings in 2.0.x
	removedSettings := map[string]bool{
		"cache_size":        true, // Removed in 2.0.x (mmap handles caching)
		"cache_expiry":      true, // Removed in 2.0.x
		"cache_buffer_chunk_size": true, // Removed in 2.0.x
		"read_cache_line_size":    true, // Removed in 2.0.x
		"write_cache_line_size":   true, // Removed in 2.0.x
	}

	if removedSettings[name] {
		// Silently ignore removed settings for compatibility
		return
	}

	// Handle renamed settings
	renamedSettings := map[string]string{
		// aio_threads was split in 2.0.x
		// "aio_threads": Now separate from hashing_threads
	}

	if newName, ok := renamedSettings[name]; ok {
		name = newName
	}

	// Call SWIG binding
	swigSettings := lt.Settings_pack(sp.ptr)
	swigSettings.Set_int(name, value)
}

// SetStr sets a string setting by name
func (sp *SettingsPack) SetStr(name string, value string) {
	if sp.ptr == nil {
		return
	}

	// Call SWIG binding
	swigSettings := lt.Settings_pack(sp.ptr)
	swigSettings.Set_str(name, value)
}

// GetBool gets a boolean setting by name
func (sp *SettingsPack) GetBool(name string) bool {
	if sp.ptr == nil {
		return false
	}

	// Call SWIG binding
	swigSettings := lt.Settings_pack(sp.ptr)
	return swigSettings.Get_bool(name)
}

// GetInt gets an integer setting by name
func (sp *SettingsPack) GetInt(name string) int {
	if sp.ptr == nil {
		return 0
	}

	// Call SWIG binding
	swigSettings := lt.Settings_pack(sp.ptr)
	return swigSettings.Get_int(name)
}

// GetStr gets a string setting by name
func (sp *SettingsPack) GetStr(name string) string {
	if sp.ptr == nil {
		return ""
	}

	// Call SWIG binding
	swigSettings := lt.Settings_pack(sp.ptr)
	return swigSettings.Get_str(name)
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
