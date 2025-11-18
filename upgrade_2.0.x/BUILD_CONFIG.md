# Build Configuration for libtorrent 2.0.x

## Version Requirements

```makefile
LIBTORRENT_VERSION = v2.0.11
BOOST_VERSION = 1.76.0  # Requires 1.67+
```

## C++ Standard

**2.0.x requires C++14** (was C++11 in 1.2.x)

Update in Makefile/CMakeLists.txt:
```makefile
CXXFLAGS += -std=c++14
```

## CMake Configuration

```cmake
cmake_minimum_required(VERSION 3.10)

# C++14 required
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Boost 1.67+ required
find_package(Boost 1.67 REQUIRED COMPONENTS system)
```

## Makefile Updates

```makefile
# Version
LIBTORRENT_VERSION := v2.0.11

# Compiler flags
CXXFLAGS := -std=c++14 -O2 -DNDEBUG
CXXFLAGS += -DTORRENT_USE_OPENSSL
CXXFLAGS += -DTORRENT_USE_LIBCRYPTO
CXXFLAGS += -DBOOST_ASIO_ENABLE_CANCELIO

# For Android, add:
# CXXFLAGS += -DANDROID

# Include paths
INCLUDES := -I$(LIBTORRENT_DIR)/include
INCLUDES += -I$(BOOST_DIR)

# Libraries
LIBS := -ltorrent-rasterbar
LIBS += -lboost_system
LIBS += -lssl -lcrypto
LIBS += -lpthread

# SWIG
SWIG := swig
SWIGFLAGS := -c++ -go -cgo -intgosize 64
SWIGFLAGS += -DLIBTORRENT_VERSION_NUM=20000  # 2.0.x
```

## Docker Build Updates

Update Dockerfile for each platform:

```dockerfile
# Base dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    swig \
    libboost1.76-all-dev \
    libssl-dev

# C++14 compiler
ENV CXX=g++-10
ENV CC=gcc-10

# libtorrent 2.0.x
ARG LIBTORRENT_VERSION=v2.0.11
RUN git clone --depth 1 --branch ${LIBTORRENT_VERSION} \
    https://github.com/arvidn/libtorrent.git

# Build libtorrent
WORKDIR /libtorrent
RUN cmake -B build \
    -DCMAKE_CXX_STANDARD=14 \
    -DCMAKE_BUILD_TYPE=Release \
    -Ddeprecated-functions=OFF \
    && cmake --build build -j$(nproc) \
    && cmake --install build
```

## Platform-Specific Notes

### Linux x86_64
- GCC 7+ for C++14 support
- Boost 1.67+ from package manager or build

### Android
- NDK r21+ for C++14 support
- Standalone toolchain with C++14 flags
- Add `-DANDROID` to CXXFLAGS

### Windows
- MSVC 2017+ or MinGW-w64 with GCC 7+
- Use vcpkg for Boost dependencies

### macOS/iOS
- Xcode 10+ for C++14 support
- Homebrew boost or build from source

### ARM (Raspberry Pi, etc.)
- GCC 7+ cross-compiler
- Build Boost for target architecture

## Removed Settings

Remove these settings from configuration (no longer exist in 2.0.x):

```go
// REMOVED - Do not use
settings.SetInt("cache_size", 1024)      // OS handles caching
settings.SetInt("cache_expiry", 300)
settings.SetBool("use_read_cache", true)
settings.SetBool("use_write_cache", true)
settings.SetBool("lock_disk_cache", false)
```

## New Settings

Add these 2.0.x-specific settings:

```go
// Separate hashing threads (was part of aio_threads)
settings.SetInt("aio_threads", 4)
settings.SetInt("hashing_threads", 2)
```

## SWIG Interface Order

The SWIG interfaces must be included in dependency order:

```cpp
// libtorrent.i
%include "session_params.i"    // Before session.i
%include "info_hash.i"         // Before torrent_handle.i
%include "disk_interface.i"    // Before session.i
%include "session.i"
%include "add_torrent_params.i"
%include "torrent_handle.i"
// ... other interfaces
```

## Testing the Build

```bash
# Clone and build
git clone --branch v2.0.11 https://github.com/arvidn/libtorrent.git
cd libtorrent
cmake -B build -DCMAKE_CXX_STANDARD=14
cmake --build build

# Test
cd build
ctest

# Build SWIG bindings
cd /path/to/libtorrent-go
make LIBTORRENT_VERSION=v2.0.11
```

## Migration Checklist

- [ ] Update LIBTORRENT_VERSION to v2.0.11
- [ ] Set C++14 standard
- [ ] Update Boost to 1.67+
- [ ] Add new SWIG interfaces (session_params.i, info_hash.i, disk_interface.i)
- [ ] Update session.i for session_params
- [ ] Remove deprecated settings from code
- [ ] Test build on all platforms
