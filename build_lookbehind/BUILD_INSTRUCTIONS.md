# Lookbehind Buffer - Build Instructions

## Current State

All source files have been patched and are ready for compilation:

- [x] libtorrent-go C++ methods added to `memory_storage.hpp`
- [x] Go bindings in `memory_storage_lookbehind.go`
- [x] `lookbehind.go` copied to elementum/bittorrent/
- [x] go.mod updated to use local libtorrent-go

## Building in a Proper Environment

This build requires:
- Docker (for libtorrent-go cross-compilation)
- OR: libtorrent-rasterbar-dev, libboost-all-dev, libssl-dev, swig

### Option A: Using Docker (Recommended)

```bash
# In an environment with Docker installed:
cd /path/to/build_lookbehind/libtorrent-go

# Build for Linux x64
make linux-x64

# Or build all platforms
make all
```

### Option B: Native Build (Without Docker)

```bash
# Install dependencies (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    libboost-all-dev \
    libssl-dev \
    pkg-config \
    libtorrent-rasterbar-dev \
    swig

# Build libtorrent-go
cd /path/to/build_lookbehind/libtorrent-go

# Set up local environment
make local-env LOCALPLATFORM=linux-x64

# Build with local libraries
PKG_CONFIG_PATH=$(pwd)/local-env/lib/pkgconfig \
CROSS_ROOT=$(pwd)/local-env \
make build

# Build elementum
cd ../elementum
go build -o elementum .
```

### Option C: GitHub Actions / CI

Copy the `build_lookbehind` directory to a system with CI/CD that has Docker access.

## After Building

1. **Copy binary to Kodi**:
   ```bash
   cp elementum ~/.kodi/addons/plugin.video.elementum/resources/bin/linux-x64/
   ```

2. **Enable in Kodi Settings**:
   - Go to Elementum Settings > BitTorrent
   - Find "Lookbehind Buffer" section
   - Enable lookbehind buffer: ON
   - Lookbehind time: 30 seconds
   - Maximum size: 50 MB

3. **Test**:
   - Play a video via Elementum
   - Watch for 60+ seconds
   - Seek backward 30 seconds
   - Should resume in <2 seconds

## Manual Patches Still Needed

Some integration patches need manual application. See:
`/home/user/plugin.video.elementum/daemon_implementation/elementum/bittorrent/PATCHES.md`

Files to patch:
- `bittorrent/torrent.go` - Add lookbehind field and methods
- `bittorrent/torrentfs.go` - Hook into Seek() and Read()
- `bittorrent/player.go` - Initialize lookbehind on playback
- `config/config.go` - Add configuration fields

## Directory Structure

```
build_lookbehind/
├── libtorrent-go/
│   ├── memory_storage.hpp        # Patched with lookbehind methods
│   ├── memory_storage.hpp.backup # Original backup
│   └── memory_storage_lookbehind.go # Go bindings
├── elementum/
│   ├── bittorrent/
│   │   └── lookbehind.go        # Lookbehind manager
│   └── go.mod                   # Updated with replace directive
└── BUILD_INSTRUCTIONS.md        # This file
```

## Troubleshooting

### "docker: command not found"
Install Docker or use Option B (native build).

### "libtorrent not found"
```bash
pkg-config --exists libtorrent-rasterbar && echo "Found" || echo "Not found"
sudo apt-get install libtorrent-rasterbar-dev
```

### Go module download failures
Check network/DNS. May need to set GOPROXY:
```bash
export GOPROXY=https://proxy.golang.org,direct
```

### Memory errors at runtime
Reduce `lookbehind_max_size` in settings or increase `memory_size`.
