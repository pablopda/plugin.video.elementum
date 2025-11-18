/*
 * session_params.i - SWIG interface for libtorrent 2.0.x session_params
 *
 * In 2.0.x, session is created with session_params which includes:
 * - settings_pack
 * - disk_io_constructor
 * - dht_state
 * - extensions
 */

%{
#include <libtorrent/session_params.hpp>
#include "memory_disk_io.hpp"
%}

%include <libtorrent/session_params.hpp>

// Extend session_params with memory disk I/O configuration
%extend libtorrent::session_params {
    // Configure memory disk I/O as the disk backend
    void set_memory_disk_io(std::int64_t memory_size) {
        libtorrent::memory_disk_memory_size = memory_size;
        self->disk_io_constructor = libtorrent::memory_disk_constructor;
    }

    // Set settings pack
    void set_settings(libtorrent::settings_pack const& settings) {
        self->settings = settings;
    }

    // Get settings pack
    libtorrent::settings_pack& get_settings() {
        return self->settings;
    }
}
