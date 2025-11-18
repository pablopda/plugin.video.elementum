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
#include <mutex>

namespace libtorrent {
    // Thread-safe global pointer to memory_disk_io instance
    // Protected by mutex for multi-threaded access
    std::mutex g_memory_disk_io_mutex;
    memory_disk_io* g_memory_disk_io = nullptr;

    // Set the global memory_disk_io pointer (called during session creation)
    void set_global_memory_disk_io(memory_disk_io* dio) {
        std::lock_guard<std::mutex> lock(g_memory_disk_io_mutex);
        g_memory_disk_io = dio;
    }

    // Clear the global pointer (called during session destruction)
    void clear_global_memory_disk_io() {
        std::lock_guard<std::mutex> lock(g_memory_disk_io_mutex);
        g_memory_disk_io = nullptr;
    }

    // Thread-safe lookbehind wrapper functions
    void memory_disk_set_lookbehind(int storage_index, std::vector<int> const& pieces) {
        std::lock_guard<std::mutex> lock(g_memory_disk_io_mutex);
        if (g_memory_disk_io) {
            g_memory_disk_io->set_lookbehind_pieces(
                storage_index_t(storage_index), pieces);
        }
    }

    void memory_disk_clear_lookbehind(int storage_index) {
        std::lock_guard<std::mutex> lock(g_memory_disk_io_mutex);
        if (g_memory_disk_io) {
            g_memory_disk_io->clear_lookbehind(storage_index_t(storage_index));
        }
    }

    bool memory_disk_is_lookbehind_available(int storage_index, int piece) {
        std::lock_guard<std::mutex> lock(g_memory_disk_io_mutex);
        if (g_memory_disk_io) {
            return g_memory_disk_io->is_lookbehind_available(
                storage_index_t(storage_index), piece);
        }
        return false;
    }

    void memory_disk_get_lookbehind_stats(int storage_index,
        int& available, int& protected_count, std::int64_t& memory) {
        std::lock_guard<std::mutex> lock(g_memory_disk_io_mutex);
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

// ============================================================================
// Storage Index Tracking
// ============================================================================
//
// IMPORTANT: libtorrent 2.0.x does NOT expose storage_index_t from add_torrent.
// The storage_index_t is managed internally by disk_interface.
//
// Workaround: Track storage indices in Go wrapper layer by:
// 1. Counting new_torrent calls (order-based)
// 2. Mapping info_hash_v1 -> storage_index after add_torrent
// 3. Using BTService.storageIndices map
//
// See: elementum/bittorrent/service_2.0.x.go for implementation

// Storage index helper functions
%inline %{
namespace libtorrent {
    // Create storage_index_t from int
    storage_index_t make_storage_index(int idx) {
        return storage_index_t(idx);
    }

    // Get int value from storage_index_t
    int storage_index_value(storage_index_t idx) {
        return static_cast<int>(idx);
    }

    // Get next storage index (returns current count before add)
    // Use this before add_torrent to predict the storage_index
    int get_next_storage_index() {
        std::lock_guard<std::mutex> lock(g_memory_disk_io_mutex);
        // This would need memory_disk_io to expose torrent count
        // For now, track in Go layer
        return -1;
    }
}
%}
