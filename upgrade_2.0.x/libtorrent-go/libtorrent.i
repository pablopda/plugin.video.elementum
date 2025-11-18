/*
 * libtorrent.i - Main SWIG interface for libtorrent 2.0.x
 *
 * This is the entry point for SWIG compilation.
 * Includes all sub-interfaces in correct dependency order.
 */

%module(directors="1") libtorrent

// Standard SWIG library includes
%include <typemaps.i>
%include <std_string.i>
%include <std_vector.i>
%include <std_map.i>
%include <std_pair.i>
%include <stdint.i>
%include <exception.i>

// Go-specific configuration
#ifdef SWIGGO
%include <go/std_string.i>
#endif

// Common C++ includes
%{
#include <string>
#include <vector>
#include <memory>
#include <functional>
#include <chrono>

// libtorrent core
#include <libtorrent/config.hpp>
#include <libtorrent/version.hpp>
#include <libtorrent/sha1_hash.hpp>
#include <libtorrent/info_hash.hpp>
#include <libtorrent/error_code.hpp>
#include <libtorrent/bdecode.hpp>
#include <libtorrent/bencode.hpp>

// Session and settings
#include <libtorrent/session.hpp>
#include <libtorrent/session_params.hpp>
#include <libtorrent/settings_pack.hpp>

// Torrent handling
#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/torrent_status.hpp>

// Alerts
#include <libtorrent/alert.hpp>
#include <libtorrent/alert_types.hpp>

// Custom memory disk I/O
#include "memory_disk_io.hpp"
%}

// Vector templates
%template(StdVectorChar) std::vector<char>;
%template(StdVectorInt) std::vector<int>;
%template(StdVectorString) std::vector<std::string>;

// Type mappings for Go compatibility
%typemap(gotype) std::int64_t "int64"
%typemap(gotype) std::uint64_t "uint64"
%typemap(gotype) std::int32_t "int32"
%typemap(gotype) std::uint32_t "uint32"

// Error code handling
%typemap(in, numinputs=0) libtorrent::error_code& ec (libtorrent::error_code temp) {
    $1 = &temp;
}
%typemap(argout) libtorrent::error_code& ec {
    if ($1->value() != 0) {
        // Error occurred - handle appropriately
    }
}

// ============================================================================
// Include interfaces in dependency order
// ============================================================================

// 1. Base types and utilities
%include "interfaces/info_hash.i"

// 2. Disk I/O (before session)
%include "interfaces/disk_interface.i"

// 3. Session parameters (before session)
%include "interfaces/session_params.i"

// 4. Session (uses disk_interface and session_params)
%include "interfaces/session.i"

// 5. Torrent operations
%include "interfaces/add_torrent_params.i"
%include "interfaces/torrent_handle.i"

// 6. Alerts
%include "interfaces/alerts.i"

// ============================================================================
// Additional helper functions
// ============================================================================

%inline %{
namespace libtorrent {
    // Version info
    int get_libtorrent_version_major() {
        return LIBTORRENT_VERSION_MAJOR;
    }

    int get_libtorrent_version_minor() {
        return LIBTORRENT_VERSION_MINOR;
    }

    const char* get_libtorrent_version_string() {
        return LIBTORRENT_VERSION;
    }

    // Check if this is 2.0.x
    bool is_libtorrent_2x() {
        return LIBTORRENT_VERSION_MAJOR >= 2;
    }
}
%}
