#!/bin/bash
#
# build-libtorrent.sh - Build libtorrent 1.2.x for cross-compilation
#
# Key changes from 1.1.x build:
# - Uses RC_1_2 branch
# - Different cmake/b2 options for 1.2.x

set -e

LIBTORRENT_VERSION="${LIBTORRENT_VERSION:-v1.2.20}"
LIBTORRENT_BRANCH="RC_1_2"

echo "Building libtorrent ${LIBTORRENT_VERSION} from ${LIBTORRENT_BRANCH}"

# Clone or update libtorrent
if [ ! -d "libtorrent" ]; then
    git clone --depth 1 --branch ${LIBTORRENT_BRANCH} \
        https://github.com/arvidn/libtorrent.git
    cd libtorrent
    git fetch --tags
    git checkout ${LIBTORRENT_VERSION}
else
    cd libtorrent
    git fetch --tags
    git checkout ${LIBTORRENT_VERSION}
fi

# Create build directory
mkdir -p build
cd build

# Configure with cmake (1.2.x prefers cmake)
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_STANDARD=11 \
    -DCMAKE_INSTALL_PREFIX=${CROSS_ROOT} \
    -Dstatic_runtime=ON \
    -Dbuild_tests=OFF \
    -Dbuild_examples=OFF \
    -Dbuild_tools=OFF \
    -Ddeprecated-functions=OFF \
    -DOPENSSL_ROOT_DIR=${CROSS_ROOT} \
    -DBoost_USE_STATIC_LIBS=ON \
    -DBoost_USE_STATIC_RUNTIME=ON

# Build
make -j$(nproc)

# Install
make install

echo "libtorrent ${LIBTORRENT_VERSION} built successfully"
