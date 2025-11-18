# Quick Start Guide - Building Lookbehind Buffer

## Prerequisites

Your system has:
- Go 1.24.7 ✅
- GCC 13.3.0 ✅
- Make, Git ✅

Missing (will be installed by script):
- libtorrent-rasterbar-dev
- boost libraries
- SWIG

---

## Option 1: Automated Build (Recommended)

### One-Command Build

```bash
cd /home/user/plugin.video.elementum/daemon_implementation
./build_lookbehind.sh
```

This will:
1. Install dependencies (requires sudo)
2. Clone libtorrent-go and elementum
3. Apply lookbehind changes
4. Build both projects

### Build Options

```bash
# Skip installing dependencies
./build_lookbehind.sh --skip-deps

# Clean build (remove previous build)
./build_lookbehind.sh --clean

# Use existing repos (don't clone again)
./build_lookbehind.sh --skip-clone

# Run tests after building
./build_lookbehind.sh --test
```

### After Building

The script will tell you what to do next:

1. **Review patched files** - Some patches may need manual adjustment
2. **Integrate config** - See `config_lookbehind_additions.go`
3. **Apply remaining patches** - See `PATCHES.md`

---

## Option 2: Manual Build

### Step 1: Install Dependencies

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    libboost-all-dev \
    libssl-dev \
    libtorrent-rasterbar-dev \
    swig

# Fedora
sudo dnf install -y \
    gcc-c++ \
    boost-devel \
    openssl-devel \
    libtorrent-rasterbar-devel \
    swig
```

### Step 2: Clone and Patch libtorrent-go

```bash
# Create build directory
mkdir -p ~/elementum_build && cd ~/elementum_build

# Clone
git clone https://github.com/ElementumOrg/libtorrent-go

# Apply patches
cd libtorrent-go

# Copy implementation files
cp /home/user/plugin.video.elementum/daemon_implementation/libtorrent-go/*.go .

# Manually edit memory_storage.hpp to add the methods from
# memory_storage_lookbehind.hpp

# Build
make linux-x64
```

### Step 3: Clone and Patch Elementum

```bash
cd ~/elementum_build

# Clone
git clone https://github.com/elgatito/elementum
cd elementum

# Copy lookbehind.go
cp /home/user/plugin.video.elementum/daemon_implementation/elementum/bittorrent/lookbehind.go bittorrent/

# Apply patches from PATCHES.md to:
# - bittorrent/torrent.go
# - bittorrent/torrentfs.go
# - bittorrent/player.go
# - bittorrent/service.go
# - config/config.go

# Use local libtorrent-go
go mod edit -replace github.com/ElementumOrg/libtorrent-go=../libtorrent-go
go mod tidy

# Build
make linux-x64
```

---

## Testing the Build

### Run Test Suite

```bash
cd /home/user/plugin.video.elementum/daemon_implementation
./test_lookbehind.sh
```

### Manual Testing

```bash
# Run daemon with debug logging
cd ~/elementum_build/elementum
./elementum --debug

# Watch for lookbehind messages:
# - "Lookbehind initialized: X MB for Ys"
# - "Lookbehind: protecting pieces X-Y"
```

### Test in Kodi

1. Copy binary to Kodi addon folder:
   ```bash
   cp elementum ~/.kodi/addons/plugin.video.elementum/resources/bin/linux-x64/
   ```

2. Restart Kodi

3. Go to Elementum Settings > BitTorrent > Lookbehind Buffer
   - Enable lookbehind buffer: ON
   - Lookbehind time: 30 seconds
   - Maximum size: 50 MB

4. Play a video via Elementum

5. Watch for 60+ seconds, then seek backward 30 seconds

6. **Expected**: Seek completes in <2 seconds

---

## Troubleshooting

### Build Fails: "libtorrent not found"

```bash
# Check if installed
pkg-config --exists libtorrent-rasterbar && echo "Found" || echo "Not found"

# Install on Ubuntu
sudo apt-get install libtorrent-rasterbar-dev

# On Fedora
sudo dnf install libtorrent-rasterbar-devel
```

### Build Fails: "undefined reference to..."

The C++ methods weren't properly added to memory_storage.hpp.

1. Open `libtorrent-go/memory_storage.hpp`
2. Find the `memory_storage` class
3. Add the methods from `memory_storage_lookbehind.hpp`
4. Make sure `lt::bitfield m_lookbehind_pieces;` is in the private section

### Go Build Fails: "cannot find package"

```bash
cd elementum
go mod edit -replace github.com/ElementumOrg/libtorrent-go=../libtorrent-go
go mod tidy
```

### Lookbehind Not Working in Kodi

1. Check settings: BitTorrent > Lookbehind Buffer > Enable
2. Check logs: `~/.kodi/temp/kodi.log`
3. Look for "Lookbehind" messages
4. Verify memory_size > 30 MB in settings

---

## Files Overview

```
daemon_implementation/
├── build_lookbehind.sh          # Automated build script
├── test_lookbehind.sh           # Test suite
├── README.md                    # Full integration guide
├── QUICK_START.md               # This file
├── elementum/
│   ├── bittorrent/
│   │   ├── lookbehind.go        # Main implementation
│   │   └── PATCHES.md           # Patches for existing files
│   └── config/
│       └── lookbehind_config.go # Config additions
└── libtorrent-go/
    ├── memory_storage_lookbehind.hpp  # C++ implementation
    └── memory_storage_lookbehind.go   # Go bindings
```

---

## Expected Results

| Metric | Before | After |
|--------|--------|-------|
| 10s backward seek | 10-25s | <2s |
| 30s backward seek | 15-30s | <2s |
| Memory usage | ~50 MB | ~100 MB |

---

## Need Help?

1. Check the full guide: `README.md`
2. Check patches: `elementum/bittorrent/PATCHES.md`
3. Run tests: `./test_lookbehind.sh`
4. Enable debug logging: `./elementum --debug`
