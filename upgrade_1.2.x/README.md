# libtorrent 1.2.x Upgrade Implementation

This directory contains all the files needed to upgrade libtorrent-go from 1.1.x to 1.2.x.

## Overview

**Current Version**: libtorrent RC_1_1 (March 2020)
**Target Version**: libtorrent v1.2.20 (January 2025)

## Directory Structure

```
upgrade_1.2.x/
├── README.md                           # This file
├── upgrade.sh                          # Automated upgrade script
├── libtorrent-go/
│   ├── memory_storage.hpp              # Rewritten for 1.2.x storage API
│   ├── Makefile.patch                  # Version and settings updates
│   ├── interfaces/
│   │   ├── add_torrent_params.i        # Updated for std::shared_ptr
│   │   ├── session.i                   # Updated settings pack
│   │   └── torrent_handle.i            # Updated piece operations
│   └── docker/scripts/
│       └── build-libtorrent.sh         # Build script for 1.2.x
├── elementum/
│   └── bittorrent/
│       ├── service_patches.go          # Documented code changes
│       └── service.go.patch            # Git patch file
└── tests/
    └── upgrade_test.go                 # Validation test suite
```

## Key Changes

### 1. Storage Interface (memory_storage.hpp)

The most significant change. Completely rewritten for new API:

```cpp
// OLD (1.1.x)
int readv(file::iovec_t const* bufs, int num_bufs, int piece, ...)

// NEW (1.2.x)
int readv(span<iovec_t const> bufs, piece_index_t piece, ...)
```

Also uses:
- `std::mutex` instead of `boost::mutex`
- `std::chrono` instead of `boost::posix_time`
- Proper `piece_index_t` type usage

### 2. SWIG Interfaces

- `std::shared_ptr` instead of `boost::shared_ptr`
- New resume data API functions
- Settings existence checks

### 3. Elementum Code

Removed deprecated settings:
- `lazy_bitfields` - REMOVED in 1.2.x
- `use_dht_as_fallback` - DEPRECATED

Updated resume data handling to use new API.

## Quick Start

### Option A: Automated Upgrade

```bash
cd /home/user/plugin.video.elementum/upgrade_1.2.x

# Apply patches only
./upgrade.sh --apply

# Apply, build, and test
./upgrade.sh --all
```

### Option B: Manual Upgrade

1. **Clone repositories**:
   ```bash
   mkdir build_1.2.x && cd build_1.2.x
   git clone https://github.com/ElementumOrg/libtorrent-go.git
   git clone https://github.com/elgatito/elementum.git
   ```

2. **Copy updated files**:
   ```bash
   cp ../upgrade_1.2.x/libtorrent-go/memory_storage.hpp libtorrent-go/
   cp ../upgrade_1.2.x/libtorrent-go/interfaces/*.i libtorrent-go/interfaces/
   ```

3. **Apply Makefile patch**:
   Update `LIBTORRENT_VERSION` to `v1.2.20`

4. **Apply Elementum patches**:
   ```bash
   cd elementum
   patch -p1 < ../upgrade_1.2.x/elementum/bittorrent/service.go.patch
   ```

5. **Build**:
   ```bash
   # With Docker
   cd libtorrent-go
   make env PLATFORM=linux-x64
   make linux-x64

   # Without Docker (requires libtorrent-dev)
   cd elementum
   go mod edit -replace github.com/ElementumOrg/libtorrent-go=../libtorrent-go
   go build -o elementum .
   ```

## Testing

Run the validation test suite:

```bash
cd build_1.2.x
go test -v ./tests/
```

Tests verify:
- Session creation
- Settings compatibility
- Memory storage initialization
- Alert types
- Resume data API
- Concurrent operations

## Compatibility Notes

### Settings Removed in 1.2.x

| Setting | Replacement |
|---------|-------------|
| `lazy_bitfields` | None (always enabled) |
| `use_dht_as_fallback` | Use `enable_dht` directly |

### API Changes

| Old (1.1.x) | New (1.2.x) |
|-------------|-------------|
| `boost::shared_ptr` | `std::shared_ptr` |
| `resume_data` field | `read_resume_data()` function |
| `int piece` | `piece_index_t piece` |
| `iovec_t* bufs, int num` | `span<iovec_t const> bufs` |

## Troubleshooting

### "Setting not found"

The SWIG wrapper now checks if settings exist. Verify you're not using:
- `lazy_bitfields`
- `use_dht_as_fallback`

### Build errors with span<>

Ensure you have a C++11 compatible compiler. The span<> header is included in libtorrent 1.2.x.

### Resume data won't load

Use the new API:
```go
params := lt.ReadResumeData(data, errorCode)
```

Instead of the old:
```go
params.SetResumeData(vector)
```

## Files Reference

### memory_storage.hpp (560 lines)

Complete rewrite including:
- New storage_interface signatures
- Integrated lookbehind buffer
- std:: types instead of boost::

### add_torrent_params.i (50 lines)

- std::shared_ptr for torrent_info
- New resume data functions

### session.i (95 lines)

- Settings existence checking
- Deprecated function ignores

### upgrade_test.go (230 lines)

Comprehensive test suite for validation.

## Next Steps

After successful build and testing:

1. Build for all 13 target platforms
2. Test with real torrents
3. Test backward seeking (lookbehind buffer)
4. Deploy to Kodi

## Future: Upgrade to 2.0.x

After 1.2.x is stable, consider upgrading to 2.0.x for:
- BitTorrent v2 support (SHA-256 hashes)
- Further performance improvements
- Modern C++14 features

See `LIBTORRENT_UPGRADE_PLAN.md` for the complete roadmap.
