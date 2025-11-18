#!/bin/bash
# ============================================================================
# Lookbehind Buffer - Quick Test Script
# ============================================================================
#
# This script provides quick tests for the lookbehind buffer implementation.
# Run after building with build_lookbehind.sh
#
# Usage:
#   ./test_lookbehind.sh [test_name]
#
# Tests:
#   all         Run all tests (default)
#   unit        Run Go unit tests
#   build       Verify build artifacts
#   config      Test configuration loading
#
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$(dirname "$SCRIPT_DIR")/build_lookbehind"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log_info() { echo -e "${YELLOW}[TEST]${NC} $1"; }

# ============================================================================
# Test Functions
# ============================================================================

test_build_artifacts() {
    log_info "Checking build artifacts..."

    local passed=0
    local failed=0

    # Check elementum binary
    if [[ -f "$BUILD_DIR/elementum/elementum" ]]; then
        log_pass "Elementum binary exists"
        ((passed++))
    else
        log_fail "Elementum binary not found"
        ((failed++))
    fi

    # Check lookbehind.go
    if [[ -f "$BUILD_DIR/elementum/bittorrent/lookbehind.go" ]]; then
        log_pass "lookbehind.go copied"
        ((passed++))
    else
        log_fail "lookbehind.go not found"
        ((failed++))
    fi

    # Check Go bindings
    if [[ -f "$BUILD_DIR/libtorrent-go/memory_storage_lookbehind.go" ]]; then
        log_pass "Go bindings copied"
        ((passed++))
    else
        log_fail "Go bindings not found"
        ((failed++))
    fi

    echo ""
    echo "Build artifacts: $passed passed, $failed failed"
    return $failed
}

test_go_unit() {
    log_info "Running Go unit tests..."

    cd "$BUILD_DIR/elementum"

    # Run tests with verbose output
    if go test -v ./bittorrent/... 2>&1 | tee /tmp/test_output.txt; then
        log_pass "Unit tests passed"
        return 0
    else
        log_fail "Unit tests failed"
        echo "See /tmp/test_output.txt for details"
        return 1
    fi
}

test_config_loading() {
    log_info "Testing configuration loading..."

    cd "$BUILD_DIR/elementum"

    # Check if lookbehind config fields exist in binary
    if strings elementum 2>/dev/null | grep -q "lookbehind_enabled"; then
        log_pass "Config strings found in binary"
    else
        log_fail "Config strings not found - may need manual integration"
        return 1
    fi

    return 0
}

test_binary_run() {
    log_info "Testing binary execution..."

    cd "$BUILD_DIR/elementum"

    # Try to run with help flag
    if ./elementum --help 2>&1 | head -5; then
        log_pass "Binary executes"
    else
        log_fail "Binary failed to execute"
        return 1
    fi

    return 0
}

# ============================================================================
# Main
# ============================================================================

TEST_NAME="${1:-all}"

echo "============================================================================"
echo "Lookbehind Buffer - Test Suite"
echo "============================================================================"
echo ""

if [[ ! -d "$BUILD_DIR" ]]; then
    log_fail "Build directory not found: $BUILD_DIR"
    echo "Run build_lookbehind.sh first"
    exit 1
fi

case "$TEST_NAME" in
    all)
        test_build_artifacts
        test_config_loading
        test_binary_run
        ;;
    unit)
        test_go_unit
        ;;
    build)
        test_build_artifacts
        ;;
    config)
        test_config_loading
        ;;
    *)
        echo "Unknown test: $TEST_NAME"
        echo "Available: all, unit, build, config"
        exit 1
        ;;
esac

echo ""
echo "============================================================================"
echo "Test suite complete"
echo "============================================================================"
