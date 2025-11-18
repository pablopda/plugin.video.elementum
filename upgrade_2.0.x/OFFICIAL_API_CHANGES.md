# libtorrent 2.0.x Official API Changes Reference

Based on the official upgrade documentation from libtorrent.org.

---

## 1. Build Requirements

- **C++14 minimum** (was C++11)
- **Boost 1.67+** (was 1.58+)

---

## 2. BitTorrent v2 Support

### 2.1 info_hash_t Type

```cpp
// OLD
sha1_hash info_hash;

// NEW
info_hash_t info_hashes;  // Contains both v1 (SHA-1) and v2 (SHA-256)
```

**Key points**:
- `info_hash_t` implicitly converts to/from `sha1_hash` (deprecated)
- Hybrid torrent's `info_hash_t` compares false to just v1 `sha1_hash`

### 2.2 Affected APIs

| Old | New |
|-----|-----|
| `add_torrent_params::info_hash` | `add_torrent_params::info_hashes` |
| `torrent_handle::info_hash()` | `torrent_handle::info_hashes()` |
| Alert `info_hash` members | Alert `info_hashes` members |

Affected alerts:
- `torrent_removed_alert`
- `torrent_deleted_alert`
- `torrent_delete_failed_alert`

### 2.3 Tracker/announce_entry Changes

**Major change for hybrid torrents** - announce once per info-hash:

```cpp
for (lt::announce_entry const& ae : h.trackers()) {
    for (lt::announce_endpoint const& aep : ae.endpoints) {
        int version = 1;
        for (lt::announce_infohash const& ai : aep.info_hashes) {
            // ai contains results for V1 or V2
            // indexed by protocol_version enum (V1=0, V2=1)
            std::cout << "[V" << version << "] " << ae.url
                << " fails: " << ai.fails
                << " msg: " << ai.message << "\n";
            ++version;
        }
    }
}
```

Structure:
```
announce_entry
└── endpoints[] (announce_endpoint)
    └── info_hashes[2] (announce_infohash)
        ├── [0] = V1 results
        └── [1] = V2 results
```

---

## 3. Merkle Tree Changes

### 3.1 Removed
- `add_torrent_params::merkle_tree`
- `create_torrent` merkle flag
- `torrent_info::set_merkle_tree()` / `merkle_tree()`

### 3.2 Added
- `add_torrent_params::verified_leaf_hashes`
- `add_torrent_params::merkle_trees`

---

## 4. create_torrent Changes

### 4.1 Default Behavior
- Creates **hybrid torrents** by default (v1 + v2 compatible)

### 4.2 Flags
- `v1_only` - Create v1-only torrent
- `v2_only` - Create v2-only torrent
- `optimize_alignment` - No longer relevant (always on for v2)
- `mutable_torrent_support` - Always on

### 4.3 Removed Parameters
- `pad_file_limit`
- `alignment`

### 4.4 New Methods
```cpp
// Set v2 piece hash (SHA-256 merkle root)
void set_hash2(file_index_t file, piece_index_t::diff_type piece, sha256_hash const& h);

// Get file root (replaces file_hash)
sha256_hash file_root(file_index_t i) const;
```

---

## 5. socket_type_t Enum

New enum class replacing plain int:

```cpp
enum class socket_type_t {
    tcp,
    socks5,
    http,
    utp,        // Note: 'udp' is deprecated, use 'utp'
    i2p,
    tcp_ssl,
    socks5_ssl,
    http_ssl,
    utp_ssl
};
```

Used in alerts:
- `peer_connect_alert`
- `peer_disconnected_alert`
- `incoming_connection_alert`
- `listen_failed_alert`
- `listen_succeeded_alert`

---

## 6. DHT Settings Unified

### 6.1 Deprecated
```cpp
lt::dht::dht_settings dht;
dht.max_peers_reply = 100;
session.set_dht_settings(dht);
```

### 6.2 New Way
```cpp
settings_pack settings;
settings.set_int(settings_pack::dht_max_peers_reply, 100);
// All dht_* settings now in settings_pack
```

---

## 7. stats_alert Deprecated

### 7.1 Old Way
```cpp
// Subscribe to stats_alert
// Process stats_alert for each torrent
```

### 7.2 New Way
```cpp
// Call this to request updates
session.post_torrent_updates();

// Handle state_update_alert
// Contains torrent_status for ALL torrents with updates
```

Benefits: Much better scaling

---

## 8. Session State Saving/Restoring

### 8.1 Deprecated
```cpp
session ses;
// ...
entry state;
ses.save_state(state);
// ...
ses.load_state(bdecode(state));
```

### 8.2 New Way
```cpp
// Load state
std::vector<char> buf = read_file("session_state");
session_params params = read_session_params(buf);

// Create session with state
session ses(params);

// Save state
session_params current = ses.session_state();
std::vector<char> out = write_session_params(current);
write_file("session_state", out);
```

### 8.3 Deprecated Constructors
Most session constructors deprecated. Use:
```cpp
session(session_params);
// session_params can be implicitly constructed from settings_pack
```

---

## 9. userdata is client_data_t

### 9.1 Old
```cpp
add_torrent_params p;
p.userdata = (void*)my_data;
// ...
void* data = /* from alert */;
MyType* my = (MyType*)data;
```

### 9.2 New
```cpp
add_torrent_params p;
p.userdata = my_data;  // Type-safe assignment
// ...
client_data_t data = /* from alert */;
MyType* my = static_cast<MyType*>(data);  // Returns nullptr if type mismatch
```

**Important**: Type must be identical including CV-qualifiers

Can now get userdata from torrent_handle:
```cpp
torrent_handle h = /* ... */;
client_data_t data = h.userdata();
```

---

## 10. URL Torrent Adding Removed

All three URL features removed:

### 10.1 HTTP URL Download - REMOVED
```cpp
// OLD (no longer works)
add_torrent_params p;
p.url = "http://example.com/file.torrent";
```

**Migration**: Download .torrent files yourself before adding

### 10.2 Magnet Link via URL - REMOVED
```cpp
// OLD (no longer works)
p.url = "magnet:?xt=urn:btih:...";
```

**Migration**: Use parse_magnet_uri()
```cpp
add_torrent_params p = parse_magnet_uri("magnet:?...");
p.save_path = "/downloads";
session.add_torrent(p);
```

### 10.3 file:// URLs - REMOVED
```cpp
// OLD (no longer works)
p.url = "file:///path/to/file.torrent";
```

**Migration**: Load files yourself

---

## 11. Disk I/O Overhaul

### 11.1 Architecture Change

| Aspect | 1.2.x | 2.0.x |
|--------|-------|-------|
| Customization | Per-torrent `storage_interface` | Session-level `disk_interface` |
| Default I/O | Custom disk cache | Memory-mapped files |
| Threading | Shared file_pool | Part of disk_interface |

### 11.2 Removed from add_torrent_params
- `storage_constructor` member

### 11.3 Removed from torrent_handle
- `get_storage_impl()`

### 11.4 Custom Storage Migration
```cpp
// OLD (1.2.x)
add_torrent_params p;
p.storage = my_storage_constructor;
session.add_torrent(p);

// NEW (2.0.x)
session_params sp;
sp.disk_io_constructor = my_disk_constructor;
session ses(sp);
// All torrents use the same disk I/O
```

### 11.5 disk_interface Requirements
Must implement:
- `new_torrent()` / `remove_torrent()`
- `async_read()` / `async_write()`
- `async_hash()` / `async_hash2()`
- Many other async methods
- `buffer_allocator_interface` for buffer management

---

## 12. Thread Settings Split

### 12.1 Old
```cpp
settings.set_int(settings_pack::aio_threads, 8);
// Every 4th thread was for hashing
```

### 12.2 New
```cpp
settings.set_int(settings_pack::aio_threads, 4);      // Disk I/O threads
settings.set_int(settings_pack::hashing_threads, 2);  // Dedicated hash threads
```

---

## 13. Cache Settings Removed

### 13.1 Removed Settings
- `cache_size` - OS handles caching with mmap

### 13.2 Removed Functions
- `session::get_cache_info()`
- `session::get_cache_status()`

---

## 14. RSS Support Remnants Removed

- `rss_notification` alert category flag removed
- `add_torrent_params::uuid` member removed

---

## 15. Plugin API Changes

### 15.1 on_unknown_torrent
```cpp
// OLD
virtual torrent_handle on_unknown_torrent(sha1_hash const& ih, ...);

// NEW
virtual torrent_handle on_unknown_torrent(info_hash_t const& ih, ...);
```

### 15.2 State Saving
```cpp
// OLD
virtual void save_state(entry& e);
virtual void load_state(bdecode_node const& n);

// NEW
virtual void save_state(std::map<std::string, std::string>& state);
virtual void load_state(std::map<std::string, std::string> const& state);
```

---

## Summary: Breaking Changes for Elementum

### Must Fix
1. `add_torrent_params::storage` → Use `session_params::disk_io_constructor`
2. `torrent_handle::get_storage_impl()` → Removed, use disk_interface
3. `info_hash()` → `info_hashes()` everywhere
4. Session constructor → Use `session_params`
5. `stats_alert` → Use `post_torrent_updates()`
6. `cache_size` setting → Remove
7. DHT settings → Move to settings_pack

### Should Update
1. Tracker/announce iteration for hybrid torrents
2. C++14 build flags
3. Boost version check
4. `hashing_threads` separate from `aio_threads`
5. `socket_type_t` enum for socket types
6. `client_data_t` for userdata

### Nice to Have
1. BitTorrent v2 torrent creation
2. Hybrid torrent support in UI
3. Per-file merkle tree support
