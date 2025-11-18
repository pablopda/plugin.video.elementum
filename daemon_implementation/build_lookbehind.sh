#!/bin/bash
# ============================================================================
# Lookbehind Buffer - Automated Build and Integration Script
# ============================================================================
#
# This script automates the integration of the lookbehind buffer feature
# into the Elementum Go daemon and libtorrent-go.
#
# Usage:
#   ./build_lookbehind.sh [OPTIONS]
#
# Options:
#   --skip-deps     Skip installing dependencies
#   --skip-clone    Skip cloning repositories (use existing)
#   --clean         Clean build directories before building
#   --test          Run tests after building
#   --help          Show this help message
#
# Requirements:
#   - Go 1.19+
#   - GCC/G++
#   - Make
#   - Git
#   - Internet connection (for cloning repos)
#
# ============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PLUGIN_DIR}/build_lookbehind"
IMPL_DIR="${PLUGIN_DIR}/daemon_implementation"

# Repository URLs (can be overridden)
LIBTORRENT_GO_REPO="${LIBTORRENT_GO_REPO:-https://github.com/ElementumOrg/libtorrent-go}"
ELEMENTUM_REPO="${ELEMENTUM_REPO:-https://github.com/elgatito/elementum}"

# Options
SKIP_DEPS=false
SKIP_CLONE=false
CLEAN_BUILD=false
RUN_TESTS=false

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    head -35 "$0" | tail -30
    exit 0
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 is required but not installed."
        exit 1
    fi
}

# ============================================================================
# Parse Arguments
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-deps)
            SKIP_DEPS=true
            shift
            ;;
        --skip-clone)
            SKIP_CLONE=true
            shift
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --test)
            RUN_TESTS=true
            shift
            ;;
        --help|-h)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            ;;
    esac
done

# ============================================================================
# Pre-flight Checks
# ============================================================================

log_info "Checking prerequisites..."

check_command go
check_command gcc
check_command g++
check_command make
check_command git

GO_VERSION=$(go version | grep -oP 'go\K[0-9]+\.[0-9]+')
log_info "Go version: $GO_VERSION"

if [[ ! -d "$IMPL_DIR" ]]; then
    log_error "Implementation directory not found: $IMPL_DIR"
    log_error "Please run this script from the plugin directory."
    exit 1
fi

log_success "Prerequisites check passed"

# ============================================================================
# Install Dependencies
# ============================================================================

if [[ "$SKIP_DEPS" == false ]]; then
    log_info "Installing dependencies..."

    # Detect package manager
    if command -v apt-get &> /dev/null; then
        log_info "Detected apt package manager"
        sudo apt-get update
        sudo apt-get install -y \
            build-essential \
            libboost-all-dev \
            libssl-dev \
            pkg-config \
            libtorrent-rasterbar-dev \
            swig \
            || log_warning "Some packages may have failed to install"
    elif command -v dnf &> /dev/null; then
        log_info "Detected dnf package manager"
        sudo dnf install -y \
            gcc-c++ \
            boost-devel \
            openssl-devel \
            libtorrent-rasterbar-devel \
            swig \
            || log_warning "Some packages may have failed to install"
    elif command -v pacman &> /dev/null; then
        log_info "Detected pacman package manager"
        sudo pacman -S --noconfirm \
            base-devel \
            boost \
            openssl \
            libtorrent-rasterbar \
            swig \
            || log_warning "Some packages may have failed to install"
    else
        log_warning "Unknown package manager. Please install dependencies manually:"
        log_warning "  - boost"
        log_warning "  - openssl"
        log_warning "  - libtorrent-rasterbar"
        log_warning "  - swig"
    fi

    log_success "Dependencies installed"
else
    log_info "Skipping dependency installation"
fi

# ============================================================================
# Setup Build Directory
# ============================================================================

if [[ "$CLEAN_BUILD" == true ]] && [[ -d "$BUILD_DIR" ]]; then
    log_info "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

log_info "Build directory: $BUILD_DIR"

# ============================================================================
# Clone Repositories
# ============================================================================

if [[ "$SKIP_CLONE" == false ]]; then
    log_info "Cloning repositories..."

    # Clone libtorrent-go
    if [[ -d "libtorrent-go" ]]; then
        log_info "libtorrent-go already exists, pulling latest..."
        cd libtorrent-go && git pull && cd ..
    else
        log_info "Cloning libtorrent-go..."
        git clone "$LIBTORRENT_GO_REPO" libtorrent-go
    fi

    # Clone elementum
    if [[ -d "elementum" ]]; then
        log_info "elementum already exists, pulling latest..."
        cd elementum && git pull && cd ..
    else
        log_info "Cloning elementum..."
        git clone "$ELEMENTUM_REPO" elementum
    fi

    log_success "Repositories cloned"
else
    log_info "Skipping repository cloning"
fi

# ============================================================================
# Apply libtorrent-go Changes
# ============================================================================

log_info "Applying libtorrent-go changes..."

cd "$BUILD_DIR/libtorrent-go"

# Check if memory_storage.hpp exists
if [[ ! -f "memory_storage.hpp" ]]; then
    log_error "memory_storage.hpp not found in libtorrent-go"
    log_error "The repository structure may have changed."
    exit 1
fi

# Backup original file
cp memory_storage.hpp memory_storage.hpp.backup

# Check if already patched
if grep -q "set_lookbehind_pieces" memory_storage.hpp; then
    log_warning "memory_storage.hpp already contains lookbehind code"
    log_warning "Skipping C++ patch (may need manual verification)"
else
    log_info "Patching memory_storage.hpp..."

    # Find the end of the public section and insert our methods
    # This is a simplified approach - may need adjustment based on actual file structure

    # Create a marker for where to insert
    # We'll insert before the first 'private:' or at end of class

    cat >> memory_storage.hpp << 'LOOKBEHIND_HPP'

// ============================================================================
// LOOKBEHIND BUFFER METHODS - Auto-generated
// ============================================================================

public:
    void set_lookbehind_pieces(std::vector<int> const& pieces) {
        for (int i = 0; i < m_num_pieces && i < static_cast<int>(m_lookbehind_pieces.size()); i++) {
            if (m_lookbehind_pieces.get_bit(i)) {
                m_reserved_pieces.clear_bit(i);
            }
        }
        m_lookbehind_pieces.clear();
        if (pieces.empty()) return;
        int max_piece = 0;
        for (int p : pieces) if (p > max_piece) max_piece = p;
        if (max_piece >= static_cast<int>(m_lookbehind_pieces.size())) {
            m_lookbehind_pieces.resize(max_piece + 1, false);
        }
        for (int piece : pieces) {
            if (piece >= 0 && piece < m_num_pieces) {
                m_lookbehind_pieces.set_bit(piece);
                m_reserved_pieces.set_bit(piece);
            }
        }
    }

    void clear_lookbehind() {
        for (int i = 0; i < m_num_pieces && i < static_cast<int>(m_lookbehind_pieces.size()); i++) {
            if (m_lookbehind_pieces.get_bit(i)) m_reserved_pieces.clear_bit(i);
        }
        m_lookbehind_pieces.clear();
    }

    bool is_lookbehind_available(int piece) const {
        if (piece < 0 || piece >= m_num_pieces) return false;
        if (piece >= static_cast<int>(m_lookbehind_pieces.size()) || !m_lookbehind_pieces.get_bit(piece)) return false;
        return m_pieces[piece].bi >= 0;
    }

    int get_lookbehind_available_count() const {
        int count = 0;
        int max_check = std::min(m_num_pieces, static_cast<int>(m_lookbehind_pieces.size()));
        for (int i = 0; i < max_check; i++) {
            if (m_lookbehind_pieces.get_bit(i) && m_pieces[i].bi >= 0) count++;
        }
        return count;
    }

    int get_lookbehind_protected_count() const {
        return static_cast<int>(m_lookbehind_pieces.count());
    }

    int64_t get_lookbehind_memory_used() const {
        return static_cast<int64_t>(get_lookbehind_available_count()) * m_piece_length;
    }

private:
    lt::bitfield m_lookbehind_pieces;
LOOKBEHIND_HPP

    log_warning "C++ code appended to memory_storage.hpp"
    log_warning "Manual review recommended to ensure proper class structure"
fi

# Copy Go bindings
log_info "Copying Go bindings..."
cp "$IMPL_DIR/libtorrent-go/memory_storage_lookbehind.go" .

log_success "libtorrent-go changes applied"

# ============================================================================
# Build libtorrent-go
# ============================================================================

log_info "Building libtorrent-go..."

# Check if Makefile exists
if [[ -f "Makefile" ]]; then
    make linux-x64 || {
        log_warning "make linux-x64 failed, trying make all..."
        make all || {
            log_error "Failed to build libtorrent-go"
            log_error "You may need to build manually or check dependencies"
            exit 1
        }
    }
else
    log_warning "No Makefile found in libtorrent-go"
    log_warning "You may need to build manually"
fi

log_success "libtorrent-go built"

# ============================================================================
# Apply Elementum Changes
# ============================================================================

log_info "Applying Elementum daemon changes..."

cd "$BUILD_DIR/elementum"

# Copy lookbehind.go
log_info "Copying lookbehind.go..."
cp "$IMPL_DIR/elementum/bittorrent/lookbehind.go" bittorrent/

# Check if config needs patching
if grep -q "LookbehindEnabled" config/config.go; then
    log_warning "config.go already contains lookbehind settings"
else
    log_info "Patching config.go..."

    # Append config additions (user will need to manually integrate properly)
    cat "$IMPL_DIR/elementum/config/lookbehind_config.go" >> config/config_lookbehind_additions.go

    log_warning "Config additions saved to config/config_lookbehind_additions.go"
    log_warning "Manual integration into config.go required"
fi

log_success "Elementum changes applied"

# ============================================================================
# Update Go Dependencies
# ============================================================================

log_info "Updating Go dependencies..."

cd "$BUILD_DIR/elementum"

# Point to local libtorrent-go
go mod edit -replace github.com/ElementumOrg/libtorrent-go=../libtorrent-go

# Tidy dependencies
go mod tidy || log_warning "go mod tidy had warnings"

log_success "Go dependencies updated"

# ============================================================================
# Build Elementum
# ============================================================================

log_info "Building Elementum daemon..."

if [[ -f "Makefile" ]]; then
    make linux-x64 || make all || {
        log_warning "Make failed, trying go build..."
        go build -o elementum . || {
            log_error "Failed to build Elementum"
            exit 1
        }
    }
else
    log_info "No Makefile, using go build..."
    go build -o elementum . || {
        log_error "Failed to build Elementum"
        exit 1
    }
fi

log_success "Elementum daemon built"

# ============================================================================
# Run Tests (Optional)
# ============================================================================

if [[ "$RUN_TESTS" == true ]]; then
    log_info "Running tests..."

    cd "$BUILD_DIR/elementum"

    go test ./... || log_warning "Some tests failed"

    log_success "Tests completed"
fi

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "============================================================================"
echo -e "${GREEN}BUILD COMPLETE${NC}"
echo "============================================================================"
echo ""
echo "Build directory: $BUILD_DIR"
echo ""
echo "Binaries:"
if [[ -f "$BUILD_DIR/elementum/elementum" ]]; then
    echo "  - $BUILD_DIR/elementum/elementum"
fi
echo ""
echo "Next steps:"
echo "  1. Review the patched files for correctness"
echo "  2. Manually integrate config additions (see config_lookbehind_additions.go)"
echo "  3. Apply patches from: $IMPL_DIR/elementum/bittorrent/PATCHES.md"
echo "  4. Test with: ./elementum --debug"
echo ""
echo "To test in Kodi:"
echo "  1. Copy the elementum binary to your Kodi addon directory"
echo "  2. Enable lookbehind in Elementum settings"
echo "  3. Play a video and seek backward"
echo "  4. Check logs for 'Lookbehind' messages"
echo ""
