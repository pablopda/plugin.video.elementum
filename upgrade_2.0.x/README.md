# libtorrent 2.0.x Upgrade Implementation

## Overview

This directory contains the implementation for upgrading from libtorrent 1.2.x to 2.0.x.

**Key Change**: Complete storage architecture rewrite from `storage_interface` to `disk_interface`.

## Directory Structure

```
upgrade_2.0.x/
├── MIGRATION_PLAN.md                    # Comprehensive migration plan (~700 lines)
├── OFFICIAL_API_CHANGES.md              # Official API changes reference
├── BUILD_CONFIG.md                      # Build configuration guide
├── README.md                            # This file
├── libtorrent-go/
│   ├── memory_disk_io.hpp               # Core disk_interface implementation (~680 lines)
│   ├── interfaces/
│   │   ├── session.i                    # Session with session_params
│   │   ├── session_params.i             # session_params SWIG
│   │   ├── info_hash.i                  # info_hash_t SWIG
│   │   ├── disk_interface.i             # disk_interface wrappers
│   │   ├── add_torrent_params.i         # Updated for info_hashes
│   │   └── torrent_handle.i             # Updated for 2.0.x API
│   └── go/
│       ├── session_wrapper.go           # Session creation helpers
│       ├── info_hash_wrapper.go         # Info hash v1/v2 helpers
│       └── storage_wrapper.go           # Storage index management
├── elementum/
│   └── bittorrent/
│       ├── service_2.0.x.go             # BTService updates
│       ├── torrent_2.0.x.go             # Torrent wrapper updates
│       └── lookbehind_2.0.x.go          # Lookbehind manager updates
└── tests/
    └── upgrade_test.go                  # Upgrade tests
```

## Architecture Change Summary

### Before (1.2.x)
```cpp
// Per-torrent storage
add_torrent_params p;
p.storage = memory_storage_constructor;
session.add_torrent(p);

// Direct access
torrent_handle.get_storage_impl();
```

### After (2.0.x)
```cpp
// Session-level disk I/O
session_params params;
params.disk_io_constructor = memory_disk_constructor;
session s(std::move(params));

// All torrents use same disk I/O
session.add_torrent(p);

// Access via storage_index_t
storage_index_t idx = /* from add_torrent */;
memory_disk_io->async_read(idx, request, callback);
```

## Key Components

### 1. memory_disk_io (memory_disk_io.hpp)

The main disk interface implementation:

- **memory_storage**: Data holder for one torrent
- **memory_disk_io**: Session-level handler implementing disk_interface
- **Factory function**: `memory_disk_constructor`

Key methods:
```cpp
storage_holder new_torrent(storage_params const&, shared_ptr<void> const&);
void remove_torrent(storage_index_t);
void async_read(storage_index_t, peer_request const&, function<...> handler);
bool async_write(storage_index_t, peer_request const&, char const*, ...);
void async_hash(storage_index_t, piece_index_t, span<sha256_hash>, ...);
```

### 2. Lookbehind Buffer Integration

Lookbehind is accessed through wrapper functions:
```cpp
memory_disk_set_lookbehind(storage_index, pieces);
memory_disk_clear_lookbehind(storage_index);
memory_disk_is_lookbehind_available(storage_index, piece);
memory_disk_get_lookbehind_stats(storage_index, ...);
```

### 3. BitTorrent v2 Support

- `info_hash_t` contains both v1 (SHA-1) and v2 (SHA-256) hashes
- `async_hash2` computes SHA-256 block hashes
- Support for hybrid torrents

## Usage in Go

### Session Creation
```go
// Create session params
params := lt.NewSessionParams()

// Configure settings
settings := lt.NewSettingsPack()
settings.SetInt("connections_limit", 200)
params.SetSettings(settings)

// Enable memory disk I/O
params.SetMemoryDiskIO(100 * 1024 * 1024)  // 100 MB

// Create session
session := lt.CreateSessionWithParams(params)
```

### Info Hash Access
```go
// Get info hashes (supports both v1 and v2)
infoHashes := handle.GetInfoHashes()

// v1 hash (backward compatible)
hashV1 := infoHashes.V1Hex()

// Check hash types
if infoHashes.HasV2() {
    hashV2 := infoHashes.BestHex()
}
```

### Lookbehind Buffer
```go
// Set lookbehind pieces (need storage_index_t)
lt.MemoryDiskSetLookbehind(storageIndex, pieces)

// Check availability
available := lt.MemoryDiskIsLookbehindAvailable(storageIndex, piece)

// Get stats
var avail, protected int
var memory int64
lt.MemoryDiskGetLookbehindStats(storageIndex, &avail, &protected, &memory)
```

## Build Requirements

- **C++14** (was C++11 in 1.2.x)
- **Boost 1.67+** (for Asio io_context)
- **cmake** preferred

Update Makefile:
```makefile
LIBTORRENT_VERSION = v2.0.11
CXXFLAGS += -std=c++14
```

## Migration Path

1. **Complete 1.2.x upgrade first** (prerequisite)
2. **Phase 1**: Build system and core types (Week 1)
3. **Phase 2**: memory_disk_io implementation (Week 2)
4. **Phase 3**: Elementum code updates (Week 3)
5. **Phase 4**: Testing and validation (Week 4)

## Key Differences from 1.2.x Upgrade

| Aspect | 1.2.x Upgrade | 2.0.x Upgrade |
|--------|---------------|---------------|
| Storage model | Same (per-torrent) | Different (session-level) |
| Operations | Synchronous | Asynchronous |
| Complexity | Moderate | High |
| Code reuse | ~80% | ~40% |

## Open Questions

1. **Storage index tracking**: How to get storage_index_t for lookbehind?
   - Option A: Return from add_torrent
   - Option B: Look up by info_hash
   - Option C: Store in Torrent struct

2. **Multi-torrent memory**: Share buffer pool or per-torrent limits?

3. **Callback threading**: Ensure Go can handle async callbacks

## Testing Strategy

### Unit Tests
- memory_disk_io creation
- Async read/write operations
- Hash computation (v1 and v2)
- Storage index management
- Lookbehind buffer

### Integration Tests
- Full torrent lifecycle
- Multiple torrents
- Hybrid v1/v2 torrents
- Resume data

### Performance Tests
- Memory usage
- Async callback overhead
- Multi-torrent scenarios

## Timeline

**Estimated effort**: 4 weeks (after 1.2.x is complete)

**Total path**: 1.1.x → 1.2.x (3-4 weeks) → 2.0.x (4 weeks) = **7-8 weeks**

## References

- [libtorrent 2.0 Upgrade Guide](https://www.libtorrent.org/upgrade_to_2.0-ref.html)
- [Custom Storage Documentation](https://www.libtorrent.org/reference-Custom_Storage.html)
- [BitTorrent v2 Blog Post](https://blog.libtorrent.org/2020/09/bittorrent-v2/)
- [Migration Issue #6118](https://github.com/arvidn/libtorrent/issues/6118)
