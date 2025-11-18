# Makefile for libtorrent-go 2.0.x
# Build configuration for libtorrent Go bindings

LIBTORRENT_VERSION = v2.0.11
BOOST_VERSION = 1.67

# Compiler settings
CXX = g++
CXXFLAGS = -std=c++14 -fPIC -Wall -O2 -DNDEBUG
CXXFLAGS += -DTORRENT_USE_OPENSSL=1
CXXFLAGS += -DTORRENT_ABI_VERSION=3
CXXFLAGS += -DBOOST_ASIO_SEPARATE_COMPILATION
CXXFLAGS += -DBOOST_ASIO_ENABLE_CANCELIO

# Platform detection
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

ifeq ($(UNAME_S),Linux)
    PLATFORM = linux
    SHARED_EXT = so
    LDFLAGS += -shared -Wl,-soname,liblibtorrent.so
endif
ifeq ($(UNAME_S),Darwin)
    PLATFORM = darwin
    SHARED_EXT = dylib
    LDFLAGS += -dynamiclib -install_name @rpath/liblibtorrent.dylib
endif
ifeq ($(findstring MINGW,$(UNAME_S)),MINGW)
    PLATFORM = windows
    SHARED_EXT = dll
    LDFLAGS += -shared
endif

# Architecture detection
ifeq ($(UNAME_M),x86_64)
    GOARCH = amd64
endif
ifeq ($(UNAME_M),aarch64)
    GOARCH = arm64
endif
ifeq ($(UNAME_M),armv7l)
    GOARCH = arm
endif

# Go settings
GO = go
GOOS = $(PLATFORM)
CGO_ENABLED = 1
GOFLAGS = -v

# SWIG settings
SWIG = swig
SWIG_FLAGS = -c++ -go -cgo -intgosize 64

# Include paths
INCLUDES = -I/usr/local/include -I/usr/include
INCLUDES += $(shell pkg-config --cflags libtorrent-rasterbar 2>/dev/null || echo "")
INCLUDES += $(shell pkg-config --cflags openssl 2>/dev/null || echo "")

# Library paths
LIBS = -ltorrent-rasterbar -lboost_system -lssl -lcrypto -lpthread
LIBS += $(shell pkg-config --libs libtorrent-rasterbar 2>/dev/null || echo "")

# Source files
SWIG_INTERFACE = libtorrent.i
SWIG_WRAP = libtorrent_wrap.cxx
SWIG_GO = go/libtorrent.go

# Output
OUTPUT_DIR = build
LIB_NAME = liblibtorrent.$(SHARED_EXT)

.PHONY: all clean swig build install test check-deps

all: check-deps swig build

check-deps:
	@echo "Checking dependencies..."
	@which $(SWIG) > /dev/null || (echo "SWIG not found" && exit 1)
	@which $(GO) > /dev/null || (echo "Go not found" && exit 1)
	@pkg-config --exists libtorrent-rasterbar 2>/dev/null || echo "Warning: libtorrent-rasterbar pkg-config not found"
	@echo "Platform: $(PLATFORM)"
	@echo "Architecture: $(GOARCH)"
	@echo "libtorrent version: $(LIBTORRENT_VERSION)"

swig: $(SWIG_WRAP)

$(SWIG_WRAP): $(SWIG_INTERFACE)
	@echo "Generating SWIG wrapper..."
	@mkdir -p go
	$(SWIG) $(SWIG_FLAGS) -outdir go -o $@ $<

$(OUTPUT_DIR)/$(LIB_NAME): $(SWIG_WRAP)
	@echo "Compiling shared library..."
	@mkdir -p $(OUTPUT_DIR)
	$(CXX) $(CXXFLAGS) $(INCLUDES) -c $(SWIG_WRAP) -o $(OUTPUT_DIR)/libtorrent_wrap.o
	$(CXX) $(LDFLAGS) $(OUTPUT_DIR)/libtorrent_wrap.o $(LIBS) -o $@

build: $(OUTPUT_DIR)/$(LIB_NAME)
	@echo "Building Go package..."
	cd go && CGO_ENABLED=$(CGO_ENABLED) GOOS=$(GOOS) GOARCH=$(GOARCH) \
		CGO_CXXFLAGS="$(CXXFLAGS) $(INCLUDES)" \
		CGO_LDFLAGS="-L../$(OUTPUT_DIR) $(LIBS)" \
		$(GO) build $(GOFLAGS) .

test:
	@echo "Running tests..."
	cd go && CGO_ENABLED=$(CGO_ENABLED) \
		CGO_LDFLAGS="-L../$(OUTPUT_DIR) $(LIBS)" \
		$(GO) test -v .

install: all
	@echo "Installing library..."
	install -d /usr/local/lib
	install -m 644 $(OUTPUT_DIR)/$(LIB_NAME) /usr/local/lib/
	ldconfig 2>/dev/null || true

clean:
	@echo "Cleaning build artifacts..."
	rm -f $(SWIG_WRAP)
	rm -f $(SWIG_GO)
	rm -rf $(OUTPUT_DIR)
	rm -f go/*.go

# Cross-compilation targets
.PHONY: linux-amd64 linux-arm64 darwin-amd64 darwin-arm64 windows-amd64

linux-amd64:
	$(MAKE) GOOS=linux GOARCH=amd64 build

linux-arm64:
	$(MAKE) GOOS=linux GOARCH=arm64 build

darwin-amd64:
	$(MAKE) GOOS=darwin GOARCH=amd64 build

darwin-arm64:
	$(MAKE) GOOS=darwin GOARCH=arm64 build

windows-amd64:
	$(MAKE) GOOS=windows GOARCH=amd64 build

# Debug build
debug: CXXFLAGS = -std=c++14 -fPIC -Wall -g -O0
debug: all

# Help
help:
	@echo "libtorrent-go $(LIBTORRENT_VERSION) build system"
	@echo ""
	@echo "Targets:"
	@echo "  all          - Build everything (default)"
	@echo "  swig         - Generate SWIG wrappers"
	@echo "  build        - Build shared library and Go package"
	@echo "  test         - Run tests"
	@echo "  install      - Install library to system"
	@echo "  clean        - Remove build artifacts"
	@echo "  debug        - Build with debug symbols"
	@echo ""
	@echo "Cross-compilation:"
	@echo "  linux-amd64  - Build for Linux x86_64"
	@echo "  linux-arm64  - Build for Linux ARM64"
	@echo "  darwin-amd64 - Build for macOS x86_64"
	@echo "  darwin-arm64 - Build for macOS ARM64"
	@echo "  windows-amd64 - Build for Windows x86_64"
