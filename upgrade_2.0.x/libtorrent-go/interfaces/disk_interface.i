/*
 * disk_interface.i - SWIG interface for libtorrent 2.0.x disk_interface
 *
 * The disk_interface is the customization point for disk I/O in 2.0.x.
 * This interface exposes the memory_disk_io lookbehind methods to Go.
 */

%{
#include <libtorrent/disk_interface.hpp>
#include "memory_disk_io.hpp"
%}

// storage_index_t type
namespace libtorrent {
    struct storage_index_t {
        int value;
    };
}

// Expose lookbehind methods through a wrapper
// Since disk_interface is internal, we access through session

%inline %{
namespace libtorrent {
    // Global pointer to the memory_disk_io instance
    // Set when session is created with memory disk I/O
    memory_disk_io* g_memory_disk_io = nullptr;

    // Lookbehind wrapper functions
    void memory_disk_set_lookbehind(int storage_index, std::vector<int> const& pieces) {
        if (g_memory_disk_io) {
            g_memory_disk_io->set_lookbehind_pieces(
                storage_index_t(storage_index), pieces);
        }
    }

    void memory_disk_clear_lookbehind(int storage_index) {
        if (g_memory_disk_io) {
            g_memory_disk_io->clear_lookbehind(storage_index_t(storage_index));
        }
    }

    bool memory_disk_is_lookbehind_available(int storage_index, int piece) {
        if (g_memory_disk_io) {
            return g_memory_disk_io->is_lookbehind_available(
                storage_index_t(storage_index), piece);
        }
        return false;
    }

    void memory_disk_get_lookbehind_stats(int storage_index,
        int& available, int& protected_count, std::int64_t& memory) {
        if (g_memory_disk_io) {
            g_memory_disk_io->get_lookbehind_stats(
                storage_index_t(storage_index),
                available, protected_count, memory);
        } else {
            available = 0;
            protected_count = 0;
            memory = 0;
        }
    }
}
%}

// Note: The storage_index_t for a torrent can be obtained from
// the torrent_handle or tracked when adding torrents.
// This requires additional integration work in Elementum.
