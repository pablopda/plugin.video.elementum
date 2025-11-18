# Lookbehind Buffer - Phase 2 Implementation Files

This directory contains production-ready source files to implement the lookbehind buffer feature in the Elementum Go daemon and libtorrent-go.

## Quick Start

### Step 1: Clone Repositories

```bash
# Clone libtorrent-go (if you have write access)
git clone https://github.com/ElementumOrg/libtorrent-go
cd libtorrent-go

# Or fork first, then clone your fork
git clone https://github.com/YOUR_USERNAME/libtorrent-go
cd libtorrent-go

# Clone Elementum daemon
cd ..
git clone https://github.com/elgatito/elementum
cd elementum

# Or clone your fork
git clone https://github.com/YOUR_USERNAME/elementum
cd elementum
```

### Step 2: Apply libtorrent-go Changes

```bash
cd libtorrent-go

# 1. Open memory_storage.hpp
# 2. Add the public methods from:
#    daemon_implementation/libtorrent-go/memory_storage_lookbehind.hpp
#
# 3. Add the private member:
#    lt::bitfield m_lookbehind_pieces;
#
# 4. Add the C wrapper functions (extern "C" section)

# 5. Copy the Go bindings file
cp /path/to/plugin.video.elementum/daemon_implementation/libtorrent-go/memory_storage_lookbehind.go .

# 6. Build libtorrent-go
make all
```

### Step 3: Apply Elementum Daemon Changes

```bash
cd elementum

# 1. Copy the new lookbehind.go file
cp /path/to/plugin.video.elementum/daemon_implementation/elementum/bittorrent/lookbehind.go bittorrent/

# 2. Apply config changes
# Open config/config.go and add the fields and functions from:
# daemon_implementation/elementum/config/lookbehind_config.go

# 3. Apply patches to existing files
# Follow the instructions in:
# daemon_implementation/elementum/bittorrent/PATCHES.md

# 4. Update go.mod to use modified libtorrent-go
go mod edit -replace github.com/ElementumOrg/libtorrent-go=../libtorrent-go

# 5. Build
make all
```

### Step 4: Test

```bash
# Run with debug logging
./elementum --debug

# In Kodi:
# 1. Play a video via Elementum
# 2. Watch for 60+ seconds
# 3. Seek backward 30 seconds
# 4. Should resume in <2 seconds if in lookbehind

# Check logs for:
# - "Lookbehind initialized: X MB for Ys"
# - "Lookbehind: protecting pieces X-Y"
# - "Backward seek to piece X - data available in lookbehind"
```

---

## File Structure

```
daemon_implementation/
├── README.md                    # This file
├── elementum/
│   ├── bittorrent/
│   │   ├── lookbehind.go        # NEW: LookbehindManager implementation
│   │   └── PATCHES.md           # Changes for existing files
│   └── config/
│       └── lookbehind_config.go # Config additions
└── libtorrent-go/
    ├── memory_storage_lookbehind.hpp  # C++ implementation
    └── memory_storage_lookbehind.go   # Go bindings
```

---

## Detailed Integration Guide

### libtorrent-go Changes

#### memory_storage.hpp

1. **Add to public section:**
   - `set_lookbehind_pieces(std::vector<int> const& pieces)`
   - `clear_lookbehind()`
   - `is_lookbehind_available(int piece)`
   - `get_lookbehind_available_count()`
   - `get_lookbehind_protected_count()`
   - `get_lookbehind_memory_used()`

2. **Add to private section:**
   ```cpp
   lt::bitfield m_lookbehind_pieces;
   ```

3. **Add C wrappers (extern "C"):**
   - `memory_storage_set_lookbehind_pieces`
   - `memory_storage_clear_lookbehind`
   - `memory_storage_is_lookbehind_available`
   - `memory_storage_get_lookbehind_available_count`
   - `memory_storage_get_lookbehind_protected_count`
   - `memory_storage_get_lookbehind_memory_used`

### Elementum Daemon Changes

#### New File: bittorrent/lookbehind.go

Copy `lookbehind.go` directly - it's a complete, standalone file.

#### config/config.go

1. Add fields to `Configuration` struct:
   ```go
   LookbehindEnabled    bool
   LookbehindTime       int
   LookbehindMaxSize    int64
   AutoAdjustLookbehind bool
   ```

2. Add to `Reload()` function (see lookbehind_config.go)

3. Add `enforceLookbehindConstraints()` function

4. Add `CalculateLookbehindSize()` function

#### bittorrent/torrent.go

1. Add `lookbehind *LookbehindManager` field to Torrent struct
2. Add `InitLookbehind()` method
3. Add `OnSeekEvent()` method
4. Add cleanup in `Close()` method

#### bittorrent/torrentfs.go

1. Modify `Seek()` to call `OnSeekEvent()` on significant seeks
2. Modify `Read()` to call `UpdatePosition()` after reads

#### bittorrent/player.go

1. Call `InitLookbehind()` in `Buffer()` after file selection
2. Add `getVideoDuration()` helper
3. Add cleanup in `Close()`

#### bittorrent/service.go

1. Add memory validation in `configure()`

---

## Configuration

The lookbehind buffer is controlled by these settings (in Kodi):

| Setting | Default | Description |
|---------|---------|-------------|
| `lookbehind_enabled` | true | Enable/disable feature |
| `lookbehind_time` | 30 | Seconds of content to retain |
| `lookbehind_max_size` | 50 | Maximum MB for lookbehind |
| `auto_adjust_lookbehind` | true | Auto-size based on bitrate |

### Memory Budget

```
Default configuration:
- Forward buffer:  20 MB
- Lookbehind:      50 MB
- End buffer:       4 MB
- Overhead:         8 MB
────────────────────────
Total:             82 MB (fits in 100 MB default)
```

---

## Expected Performance

| Scenario | Without Lookbehind | With Lookbehind |
|----------|-------------------|-----------------|
| 10s backward seek | 10-25s freeze | <2s |
| 30s backward seek | 15-30s freeze | <2s |
| 60s backward seek | 20-40s freeze | <2s |
| Beyond lookbehind | Same | Same |

---

## Troubleshooting

### "Lookbehind disabled" in logs

- Check `lookbehind_enabled` setting in Kodi
- Ensure `memory_size` > 30 MB
- Lookbehind auto-disables if < 10 MB available

### Still slow after enabling

1. Check if piece is in window: look for "in lookbehind" log message
2. Piece may have been evicted before protection was set
3. Increase `lookbehind_max_size` setting

### Build errors in libtorrent-go

- Ensure C++ functions match Go cgo declarations
- Check pointer types (void* vs specific types)
- Verify SWIG interface if using SWIG

### Memory errors

1. Reduce `lookbehind_max_size`
2. Increase `memory_size`
3. Lookbehind is capped at 50% of total memory

---

## Version Compatibility

- libtorrent-rasterbar: 1.2.x or 2.x
- Go: 1.19+
- Elementum: 0.1.x

---

## Support

For issues with this implementation:
1. Check logs with `--debug` flag
2. Verify all patches were applied correctly
3. Ensure libtorrent-go was rebuilt after changes
4. Test with simple backward seek first
