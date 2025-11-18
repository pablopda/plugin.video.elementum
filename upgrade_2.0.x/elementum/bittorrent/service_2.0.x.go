// service_2.0.x.go - Service layer updates for libtorrent 2.0.x
//
// This file contains the updated BTService implementation for 2.0.x.
// Key changes:
// - Session creation with session_params
// - Storage index tracking for lookbehind access
// - State saving with write_session_params

package bittorrent

import (
	"sync"

	lt "github.com/ElementumOrg/libtorrent-go"
)

// BTService is the main BitTorrent service
type BTService struct {
	// Session and configuration
	Session  *lt.Session
	config   *ServiceConfig

	// Memory disk I/O accessor (2.0.x)
	memoryDiskIO *lt.MemoryDiskIO

	// Torrent management
	mu       sync.RWMutex
	torrents map[string]*Torrent // info_hash_v1 -> Torrent

	// Storage index tracking (2.0.x)
	// Maps torrent info hash to storage_index_t for lookbehind access
	storageIndices map[string]lt.StorageIndex
}

// ServiceConfig holds BTService configuration
type ServiceConfig struct {
	DownloadPath     string
	TorrentsPath     string
	MemorySize       int64
	ConnectionsLimit int
	// Add other config fields as needed
}

// NewBTService creates a new BitTorrent service
func NewBTService(config *ServiceConfig) (*BTService, error) {
	service := &BTService{
		config:         config,
		torrents:       make(map[string]*Torrent),
		storageIndices: make(map[string]lt.StorageIndex),
	}

	if err := service.initSession(); err != nil {
		return nil, err
	}

	return service, nil
}

// initSession initializes the libtorrent session (2.0.x way)
func (s *BTService) initSession() error {
	// Create settings pack
	settings := lt.NewSettingsPack()
	s.configureSettings(settings)

	// Create session params (2.0.x)
	params := lt.NewSessionParams()
	params.SetSettings(settings)

	// Configure memory disk I/O at session level
	if s.config.MemorySize > 0 {
		params.SetMemoryDiskIO(s.config.MemorySize)
	}

	// Create session with params
	session, err := lt.CreateSessionWithParams(params)
	if err != nil {
		return err
	}
	s.Session = session

	// Create memory disk I/O accessor
	s.memoryDiskIO = lt.NewMemoryDiskIO(session)

	return nil
}

// configureSettings applies settings to the settings pack
func (s *BTService) configureSettings(settings *lt.SettingsPack) {
	// Basic settings
	settings.SetInt("connections_limit", s.config.ConnectionsLimit)
	settings.SetStr("user_agent", "Elementum/2.0")

	// DHT settings (now in settings_pack, not separate dht_settings)
	settings.SetBool("enable_dht", true)
	settings.SetInt("dht_max_peers_reply", 100)
	settings.SetInt("dht_search_branching", 10)

	// Performance settings for streaming
	settings.ConfigureForStreaming()

	// 2.0.x specific settings
	settings.SetInt("aio_threads", 4)
	settings.SetInt("hashing_threads", 2)

	// Removed settings in 2.0.x (don't set these):
	// - cache_size (OS handles caching with mmap)
	// - cache_expiry
	// - use_read_cache
	// - use_write_cache
}

// AddTorrent adds a torrent to the service (2.0.x version)
func (s *BTService) AddTorrent(uri string, savePath string) (*Torrent, error) {
	// Create add_torrent_params
	params := lt.NewAddTorrentParams()
	params.SavePath = savePath

	// Parse magnet or torrent file
	// Note: 2.0.x removed url field, use parse_magnet_uri directly
	if isMagnet(uri) {
		parsedParams, err := lt.ParseMagnetUri(uri)
		if err != nil {
			return nil, err
		}
		params = parsedParams
		params.SavePath = savePath
	} else {
		// Load torrent file
		ti, err := lt.NewTorrentInfo(uri)
		if err != nil {
			return nil, err
		}
		params.SetTorrentInfo(ti)
	}

	// Add torrent to session
	// In 2.0.x, we need to track the storage_index_t returned
	handle, err := s.Session.AddTorrent(params)
	if err != nil {
		return nil, err
	}

	// Get info hashes (2.0.x)
	infoHashes := handle.GetInfoHashes()
	infoHashV1 := infoHashes.V1Hex()

	// Track storage index for lookbehind access
	storageIdx := s.Session.GetStorageIndex(infoHashV1)
	s.memoryDiskIO.RegisterTorrent(infoHashV1, lt.StorageIndex(storageIdx))

	// Create Torrent wrapper
	torrent := &Torrent{
		Handle:       handle,
		InfoHashV1:   infoHashV1,
		StorageIndex: lt.StorageIndex(storageIdx),
		service:      s,
	}

	s.mu.Lock()
	s.torrents[infoHashV1] = torrent
	s.storageIndices[infoHashV1] = lt.StorageIndex(storageIdx)
	s.mu.Unlock()

	return torrent, nil
}

// RemoveTorrent removes a torrent from the service
func (s *BTService) RemoveTorrent(infoHashV1 string, deleteFiles bool) error {
	s.mu.Lock()
	torrent, ok := s.torrents[infoHashV1]
	if !ok {
		s.mu.Unlock()
		return nil
	}
	delete(s.torrents, infoHashV1)
	delete(s.storageIndices, infoHashV1)
	s.mu.Unlock()

	// Unregister from memory disk I/O
	s.memoryDiskIO.UnregisterTorrent(infoHashV1)

	// Remove from session
	flags := 0
	if deleteFiles {
		flags = 1 // session::delete_files
	}
	s.Session.RemoveTorrent(torrent.Handle, flags)

	return nil
}

// GetTorrent returns a torrent by info hash
func (s *BTService) GetTorrent(infoHashV1 string) *Torrent {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.torrents[infoHashV1]
}

// SaveSessionState saves the session state (2.0.x way)
func (s *BTService) SaveSessionState() ([]byte, error) {
	// Uses write_session_params instead of save_state
	return s.Session.SaveSessionState()
}

// Close shuts down the service
func (s *BTService) Close() {
	if s.Session != nil {
		// Session destructor handles cleanup
		lt.DeleteSession(s.Session)
		s.Session = nil
	}
}

// PostTorrentUpdates requests status updates (replaces stats_alert)
func (s *BTService) PostTorrentUpdates() {
	s.Session.PostTorrentUpdates()
}

// Helper functions

func isMagnet(uri string) bool {
	return len(uri) > 8 && uri[:8] == "magnet:?"
}
