#!/bin/bash
#
# upgrade.sh - Automated upgrade script for libtorrent 1.1.x to 1.2.x
#
# This script applies all the necessary changes to upgrade libtorrent-go
# and Elementum to use libtorrent 1.2.x
#
# Usage:
#   ./upgrade.sh [--apply] [--build] [--test]
#
# Options:
#   --apply   Apply patches to the cloned repositories
#   --build   Build libtorrent-go and elementum
#   --test    Run validation tests
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/../build_1.2.x"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse arguments
DO_APPLY=false
DO_BUILD=false
DO_TEST=false

for arg in "$@"; do
    case $arg in
        --apply)
            DO_APPLY=true
            ;;
        --build)
            DO_BUILD=true
            ;;
        --test)
            DO_TEST=true
            ;;
        --all)
            DO_APPLY=true
            DO_BUILD=true
            DO_TEST=true
            ;;
        --help)
            echo "Usage: $0 [--apply] [--build] [--test] [--all]"
            exit 0
            ;;
    esac
done

echo "============================================================"
echo "  libtorrent Upgrade: 1.1.x → 1.2.x"
echo "============================================================"
echo ""

# Step 1: Create build directory and clone repositories
setup_repositories() {
    log_info "Setting up build directory..."

    mkdir -p "${BUILD_DIR}"
    cd "${BUILD_DIR}"

    # Clone libtorrent-go
    if [ ! -d "libtorrent-go" ]; then
        log_info "Cloning libtorrent-go..."
        git clone https://github.com/ElementumOrg/libtorrent-go.git
    else
        log_info "libtorrent-go already cloned"
    fi

    # Clone elementum
    if [ ! -d "elementum" ]; then
        log_info "Cloning elementum..."
        git clone https://github.com/elgatito/elementum.git
    else
        log_info "elementum already cloned"
    fi

    log_info "Repositories ready"
}

# Step 2: Apply patches
apply_patches() {
    log_info "Applying 1.2.x upgrade patches..."

    cd "${BUILD_DIR}"

    # Apply memory_storage.hpp
    log_info "Updating memory_storage.hpp..."
    cp "${SCRIPT_DIR}/libtorrent-go/memory_storage.hpp" \
       "${BUILD_DIR}/libtorrent-go/memory_storage.hpp"

    # Apply SWIG interfaces
    log_info "Updating SWIG interfaces..."
    cp "${SCRIPT_DIR}/libtorrent-go/interfaces/add_torrent_params.i" \
       "${BUILD_DIR}/libtorrent-go/interfaces/add_torrent_params.i"
    cp "${SCRIPT_DIR}/libtorrent-go/interfaces/session.i" \
       "${BUILD_DIR}/libtorrent-go/interfaces/session.i"
    cp "${SCRIPT_DIR}/libtorrent-go/interfaces/torrent_handle.i" \
       "${BUILD_DIR}/libtorrent-go/interfaces/torrent_handle.i"

    # Apply Makefile patch
    log_info "Updating Makefile..."
    cd "${BUILD_DIR}/libtorrent-go"
    if [ -f "${SCRIPT_DIR}/libtorrent-go/Makefile.patch" ]; then
        patch -p1 < "${SCRIPT_DIR}/libtorrent-go/Makefile.patch" || true
    fi

    # Copy build script
    log_info "Updating build scripts..."
    cp "${SCRIPT_DIR}/libtorrent-go/docker/scripts/build-libtorrent.sh" \
       "${BUILD_DIR}/libtorrent-go/docker/scripts/build-libtorrent.sh"
    chmod +x "${BUILD_DIR}/libtorrent-go/docker/scripts/build-libtorrent.sh"

    # Apply Elementum patches
    log_info "Applying Elementum patches..."
    cd "${BUILD_DIR}/elementum"
    if [ -f "${SCRIPT_DIR}/elementum/bittorrent/service.go.patch" ]; then
        patch -p1 < "${SCRIPT_DIR}/elementum/bittorrent/service.go.patch" || log_warn "Patch may have already been applied"
    fi

    # Copy test files
    log_info "Copying test files..."
    mkdir -p "${BUILD_DIR}/tests"
    cp "${SCRIPT_DIR}/tests/upgrade_test.go" "${BUILD_DIR}/tests/"

    log_info "Patches applied successfully"
}

# Step 3: Build
build_project() {
    log_info "Building libtorrent-go and elementum..."

    cd "${BUILD_DIR}/libtorrent-go"

    # Check for Docker
    if command -v docker &> /dev/null; then
        log_info "Docker found, building with Docker..."

        # Build for linux-x64
        make env PLATFORM=linux-x64
        make linux-x64
    else
        log_warn "Docker not found"
        log_info "Attempting native build..."

        # Check for libtorrent-rasterbar
        if pkg-config --exists libtorrent-rasterbar; then
            log_info "libtorrent-rasterbar found"

            # Update go.mod in elementum
            cd "${BUILD_DIR}/elementum"
            go mod edit -replace github.com/ElementumOrg/libtorrent-go=../libtorrent-go

            # Build elementum
            log_info "Building elementum..."
            go build -v -o elementum .

            log_info "Build complete: ${BUILD_DIR}/elementum/elementum"
        else
            log_error "libtorrent-rasterbar not found"
            log_error "Install with: sudo apt-get install libtorrent-rasterbar-dev"
            exit 1
        fi
    fi
}

# Step 4: Run tests
run_tests() {
    log_info "Running validation tests..."

    cd "${BUILD_DIR}"

    # Check if tests exist
    if [ -f "${BUILD_DIR}/tests/upgrade_test.go" ]; then
        log_info "Running Go tests..."

        # Set up test environment
        export CGO_ENABLED=1

        # Run tests
        go test -v ./tests/ || {
            log_error "Some tests failed"
            return 1
        }

        log_info "All tests passed!"
    else
        log_warn "Test files not found"
    fi
}

# Main execution
main() {
    setup_repositories

    if [ "$DO_APPLY" = true ]; then
        apply_patches
    fi

    if [ "$DO_BUILD" = true ]; then
        build_project
    fi

    if [ "$DO_TEST" = true ]; then
        run_tests
    fi

    echo ""
    echo "============================================================"
    echo "  Upgrade process complete!"
    echo "============================================================"
    echo ""
    echo "Next steps:"
    echo "  1. Review the applied patches in ${BUILD_DIR}"
    echo "  2. Build for all target platforms"
    echo "  3. Test with actual torrents"
    echo "  4. Deploy to Kodi"
    echo ""
}

main "$@"
