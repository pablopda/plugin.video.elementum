/*
 * memory_disk_io.hpp - In-memory disk I/O for libtorrent 2.0.x
 *
 * This implements the disk_interface for session-level memory storage.
 * Key changes from 1.2.x storage_interface:
 * - Session-level instead of per-torrent
 * - All async operations with callbacks
 * - Uses storage_index_t for torrent identification
 * - Integrates with io_context for async posting
 */

#ifndef TORRENT_MEMORY_DISK_IO_HPP_INCLUDED
#define TORRENT_MEMORY_DISK_IO_HPP_INCLUDED

#include <cmath>
#include <memory>
#include <algorithm>
#include <iostream>
#include <mutex>
#include <chrono>
#include <vector>
#include <string>
#include <map>
#include <functional>

#include <boost/dynamic_bitset.hpp>

#include <libtorrent/config.hpp>
#include <libtorrent/error_code.hpp>
#include <libtorrent/disk_interface.hpp>
#include <libtorrent/disk_buffer_holder.hpp>
#include <libtorrent/storage_defs.hpp>
#include <libtorrent/io_context.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/file_storage.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/hasher.hpp>
#include <libtorrent/sha1_hash.hpp>
#include <libtorrent/aux_/vector.hpp>
#include <libtorrent/units.hpp>
#include <libtorrent/span.hpp>
#include <libtorrent/peer_request.hpp>

typedef boost::dynamic_bitset<> Bitset;

namespace libtorrent {

// Global memory configuration
std::int64_t memory_disk_memory_size = 0;

// Get current time
inline std::chrono::steady_clock::time_point now() {
    return std::chrono::steady_clock::now();
}

// ============================================================================
// memory_storage - Data holder for one torrent's memory buffers
// ============================================================================

struct memory_storage
{
    // Piece data storage
    std::map<piece_index_t, std::vector<char>> m_file_data;

    // Torrent metadata
    file_storage const& m_files;
    int m_piece_length;
    int m_num_pieces;

    // Buffer management
    Bitset reader_pieces;
    Bitset reserved_pieces;
    Bitset lookbehind_pieces;
    std::int64_t capacity;
    int buffer_limit;
    int buffer_used;

    // Timing for LRU
    std::map<piece_index_t, std::chrono::steady_clock::time_point> m_access_times;

    // Logging
    bool is_logging = false;

    explicit memory_storage(storage_params const& p)
        : m_files(p.files)
        , m_piece_length(p.files.piece_length())
        , m_num_pieces(p.files.num_pieces())
        , capacity(memory_disk_memory_size)
        , buffer_limit(0)
        , buffer_used(0)
    {
        // Calculate buffer limit based on capacity
        if (capacity > 0) {
            buffer_limit = static_cast<int>(std::ceil(
                static_cast<double>(capacity) / m_piece_length) + 2);
            if (buffer_limit > m_num_pieces) {
                buffer_limit = m_num_pieces;
            }
        } else {
            buffer_limit = m_num_pieces;
        }

        // Initialize bitsets
        reader_pieces.resize(m_num_pieces + 10);
        reserved_pieces.resize(m_num_pieces + 10);
        lookbehind_pieces.resize(m_num_pieces + 10);

        std::cerr << "INFO memory_storage: pieces=" << m_num_pieces
                  << ", piece_length=" << m_piece_length
                  << ", buffer_limit=" << buffer_limit << std::endl;
    }

    // Read piece data
    span<char const> readv(peer_request const& r, storage_error& ec) const
    {
        auto const i = m_file_data.find(r.piece);
        if (i == m_file_data.end())
        {
            ec.operation = operation_t::file_read;
            ec.ec = boost::asio::error::eof;
            return {};
        }

        if (static_cast<int>(i->second.size()) <= r.start)
        {
            ec.operation = operation_t::file_read;
            ec.ec = boost::asio::error::eof;
            return {};
        }

        int const size = std::min(r.length,
            static_cast<int>(i->second.size()) - r.start);
        return {i->second.data() + r.start, size};
    }

    // Write piece data
    void writev(span<char const> b, piece_index_t const piece, int const offset)
    {
        auto& data = m_file_data[piece];
        if (data.empty())
        {
            // New piece - check buffer limit
            if (capacity > 0 && buffer_used >= buffer_limit)
            {
                trim(piece);
            }
            data.resize(m_files.piece_size(piece));
            buffer_used++;
        }

        // Ensure vector is large enough
        std::size_t const required_size = offset + b.size();
        if (data.size() < required_size)
            data.resize(required_size);

        std::memcpy(data.data() + offset, b.data(), b.size());
        m_access_times[piece] = now();
    }

    // Compute SHA1 hash for a piece
    sha1_hash hash(piece_index_t const piece,
                   span<sha256_hash> const block_hashes,
                   storage_error& ec) const
    {
        auto const i = m_file_data.find(piece);
        if (i == m_file_data.end())
        {
            ec.operation = operation_t::file_read;
            ec.ec = boost::asio::error::eof;
            return {};
        }

        hasher h;
        h.update(i->second);

        // Compute block hashes for v2 if requested
        if (!block_hashes.empty())
        {
            int const piece_size2 = m_files.piece_size2(piece);
            int const blocks_in_piece = (piece_size2 + 0x3fff) / 0x4000;
            char const* buf = i->second.data();
            std::int64_t offset = 0;
            for (int k = 0; k < blocks_in_piece; ++k)
            {
                hasher256 h2;
                std::ptrdiff_t const len = std::min(0x4000,
                    static_cast<int>(i->second.size() - offset));
                h2.update({buf, len});
                buf += len;
                offset += len;
                block_hashes[k] = h2.final();
            }
        }

        return h.final();
    }

    // Compute SHA256 hash for a block (v2 torrents)
    sha256_hash hash2(piece_index_t const piece, int const offset,
                      storage_error& ec)
    {
        auto const i = m_file_data.find(piece);
        if (i == m_file_data.end())
        {
            ec.operation = operation_t::file_read;
            ec.ec = boost::asio::error::eof;
            return {};
        }

        hasher256 h;
        std::ptrdiff_t const len = std::min(0x4000,
            static_cast<int>(i->second.size()) - offset);
        h.update({i->second.data() + offset, len});
        return h.final();
    }

    // Check if piece has data
    bool has_piece(piece_index_t piece) const
    {
        return m_file_data.find(piece) != m_file_data.end();
    }

    // Remove a piece to free space
    void remove_piece(piece_index_t piece)
    {
        auto it = m_file_data.find(piece);
        if (it != m_file_data.end())
        {
            m_file_data.erase(it);
            m_access_times.erase(piece);
            buffer_used--;

            if (is_logging)
            {
                std::cerr << "INFO Removed piece " << static_cast<int>(piece)
                          << ", buffer_used=" << buffer_used << std::endl;
            }
        }
    }

    // Trim buffers using LRU eviction
    void trim(piece_index_t const current_piece)
    {
        while (buffer_used >= buffer_limit)
        {
            // Find oldest piece that's not protected
            piece_index_t oldest_piece(-1);
            auto oldest_time = now();

            for (auto const& kv : m_access_times)
            {
                int const idx = static_cast<int>(kv.first);

                // Skip current piece
                if (kv.first == current_piece) continue;

                // Skip protected pieces
                if (idx < m_num_pieces)
                {
                    if (reserved_pieces.test(idx)) continue;
                    if (lookbehind_pieces.test(idx)) continue;
                }

                if (kv.second < oldest_time)
                {
                    oldest_time = kv.second;
                    oldest_piece = kv.first;
                }
            }

            if (static_cast<int>(oldest_piece) == -1)
            {
                // No piece found to evict
                break;
            }

            remove_piece(oldest_piece);
        }
    }

    // ========================================================================
    // Lookbehind buffer methods
    // ========================================================================

    void set_lookbehind_pieces(std::vector<int> const& pieces)
    {
        // Clear previous
        lookbehind_pieces.reset();

        // Set new
        for (int piece : pieces)
        {
            if (piece >= 0 && piece < m_num_pieces)
            {
                lookbehind_pieces.set(piece);
            }
        }
    }

    void clear_lookbehind()
    {
        lookbehind_pieces.reset();
    }

    bool is_lookbehind_available(int piece) const
    {
        if (piece < 0 || piece >= m_num_pieces) return false;
        if (!lookbehind_pieces.test(piece)) return false;
        return has_piece(piece_index_t(piece));
    }

    int get_lookbehind_available_count() const
    {
        int count = 0;
        for (int i = 0; i < m_num_pieces; i++)
        {
            if (lookbehind_pieces.test(i) && has_piece(piece_index_t(i)))
            {
                count++;
            }
        }
        return count;
    }

    int get_lookbehind_protected_count() const
    {
        return static_cast<int>(lookbehind_pieces.count());
    }

    std::int64_t get_lookbehind_memory_used() const
    {
        return static_cast<std::int64_t>(get_lookbehind_available_count())
               * m_piece_length;
    }
};

// ============================================================================
// memory_disk_io - Session-level disk I/O handler
// ============================================================================

struct memory_disk_io final
    : disk_interface
    , buffer_allocator_interface
{
private:
    io_context& m_ioc;
    aux::vector<std::unique_ptr<memory_storage>, storage_index_t> m_torrents;
    std::vector<storage_index_t> m_free_slots;
    mutable std::mutex m_mutex;
    bool m_abort = false;

public:
    explicit memory_disk_io(io_context& ioc)
        : m_ioc(ioc)
    {
        std::cerr << "INFO memory_disk_io created" << std::endl;
    }

    // ========================================================================
    // Storage management
    // ========================================================================

    storage_holder new_torrent(storage_params const& p,
                               std::shared_ptr<void> const&) override
    {
        std::lock_guard<std::mutex> lock(m_mutex);

        storage_index_t idx;
        if (m_free_slots.empty())
        {
            idx = storage_index_t(static_cast<int>(m_torrents.size()));
            m_torrents.emplace_back(std::make_unique<memory_storage>(p));
        }
        else
        {
            idx = m_free_slots.back();
            m_free_slots.pop_back();
            m_torrents[idx] = std::make_unique<memory_storage>(p);
        }

        std::cerr << "INFO new_torrent idx=" << static_cast<int>(idx)
                  << std::endl;
        return storage_holder(idx, *this);
    }

    void remove_torrent(storage_index_t idx) override
    {
        std::lock_guard<std::mutex> lock(m_mutex);

        std::cerr << "INFO remove_torrent idx=" << static_cast<int>(idx)
                  << std::endl;
        m_torrents[idx].reset();
        m_free_slots.push_back(idx);
    }

    // ========================================================================
    // Async I/O operations
    // ========================================================================

    void async_read(storage_index_t storage, peer_request const& r,
        std::function<void(disk_buffer_holder, storage_error const&)> handler,
        disk_job_flags_t) override
    {
        storage_error error;
        span<char const> data;

        {
            std::lock_guard<std::mutex> lock(m_mutex);
            if (storage < m_torrents.end_index() && m_torrents[storage])
            {
                data = m_torrents[storage]->readv(r, error);
            }
            else
            {
                error.ec = boost::asio::error::invalid_argument;
            }
        }

        post(m_ioc, [handler, error, data, this]
        {
            handler(disk_buffer_holder(*this,
                const_cast<char*>(data.data()),
                static_cast<int>(data.size())), error);
        });
    }

    bool async_write(storage_index_t storage, peer_request const& r,
        char const* buf, std::shared_ptr<disk_observer>,
        std::function<void(storage_error const&)> handler,
        disk_job_flags_t) override
    {
        storage_error error;

        {
            std::lock_guard<std::mutex> lock(m_mutex);
            if (storage < m_torrents.end_index() && m_torrents[storage])
            {
                m_torrents[storage]->writev({buf, r.length}, r.piece, r.start);
            }
            else
            {
                error.ec = boost::asio::error::invalid_argument;
            }
        }

        post(m_ioc, [handler, error] { handler(error); });
        return false; // false = not write-blocked
    }

    void async_hash(storage_index_t storage, piece_index_t piece,
        span<sha256_hash> block_hashes, disk_job_flags_t,
        std::function<void(piece_index_t, sha1_hash const&, storage_error const&)> handler) override
    {
        storage_error error;
        sha1_hash h;

        {
            std::lock_guard<std::mutex> lock(m_mutex);
            if (storage < m_torrents.end_index() && m_torrents[storage])
            {
                h = m_torrents[storage]->hash(piece, block_hashes, error);
            }
            else
            {
                error.ec = boost::asio::error::invalid_argument;
            }
        }

        post(m_ioc, [handler, piece, h, error] { handler(piece, h, error); });
    }

    void async_hash2(storage_index_t storage, piece_index_t piece, int offset,
        disk_job_flags_t,
        std::function<void(piece_index_t, sha256_hash const&, storage_error const&)> handler) override
    {
        storage_error error;
        sha256_hash h;

        {
            std::lock_guard<std::mutex> lock(m_mutex);
            if (storage < m_torrents.end_index() && m_torrents[storage])
            {
                h = m_torrents[storage]->hash2(piece, offset, error);
            }
            else
            {
                error.ec = boost::asio::error::invalid_argument;
            }
        }

        post(m_ioc, [handler, piece, h, error] { handler(piece, h, error); });
    }

    void async_move_storage(storage_index_t, std::string,
        move_flags_t,
        std::function<void(status_t, std::string const&, storage_error const&)> handler) override
    {
        // Memory storage doesn't support moving
        storage_error error;
        error.ec = boost::asio::error::operation_not_supported;
        post(m_ioc, [handler, error]
        {
            handler(status_t::fatal_disk_error, "", error);
        });
    }

    void async_release_files(storage_index_t storage,
        std::function<void()> handler) override
    {
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            if (storage < m_torrents.end_index() && m_torrents[storage])
            {
                m_torrents[storage]->m_file_data.clear();
            }
        }

        if (handler) post(m_ioc, handler);
    }

    void async_check_files(storage_index_t, add_torrent_params const*,
        aux::vector<std::string, file_index_t>,
        std::function<void(status_t, storage_error const&)> handler) override
    {
        // Memory storage always passes check (no files to verify)
        post(m_ioc, [handler]
        {
            handler(status_t::no_error, storage_error());
        });
    }

    void async_stop_torrent(storage_index_t,
        std::function<void()> handler) override
    {
        if (handler) post(m_ioc, handler);
    }

    void async_rename_file(storage_index_t, file_index_t index, std::string name,
        std::function<void(std::string const&, file_index_t, storage_error const&)> handler) override
    {
        // Memory storage doesn't support renaming
        post(m_ioc, [handler, name, index]
        {
            handler(name, index, storage_error());
        });
    }

    void async_delete_files(storage_index_t storage, remove_flags_t,
        std::function<void(storage_error const&)> handler) override
    {
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            if (storage < m_torrents.end_index() && m_torrents[storage])
            {
                m_torrents[storage]->m_file_data.clear();
            }
        }

        post(m_ioc, [handler] { handler(storage_error()); });
    }

    void async_set_file_priority(storage_index_t,
        aux::vector<download_priority_t, file_index_t> prio,
        std::function<void(storage_error const&,
            aux::vector<download_priority_t, file_index_t>)> handler) override
    {
        post(m_ioc, [handler, prio]
        {
            handler(storage_error(), std::move(prio));
        });
    }

    void async_clear_piece(storage_index_t storage, piece_index_t index,
        std::function<void(piece_index_t)> handler) override
    {
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            if (storage < m_torrents.end_index() && m_torrents[storage])
            {
                m_torrents[storage]->remove_piece(index);
            }
        }

        post(m_ioc, [handler, index] { handler(index); });
    }

    // ========================================================================
    // Status and control
    // ========================================================================

    void update_stats_counters(counters&) const override {}

    std::vector<open_file_state> get_status(storage_index_t) const override
    {
        return {};
    }

    void abort(bool wait) override
    {
        m_abort = true;
        // If wait is true, we should wait for pending operations
        // For memory storage, operations are synchronous, so nothing to wait for
    }

    void submit_jobs() override {}

    void settings_updated() override {}

    // buffer_allocator_interface
    void free_disk_buffer(char*) override
    {
        // Buffers are owned by memory_storage, no separate free needed
    }

    // ========================================================================
    // Lookbehind buffer access
    // ========================================================================

    void set_lookbehind_pieces(storage_index_t storage,
                               std::vector<int> const& pieces)
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (storage < m_torrents.end_index() && m_torrents[storage])
        {
            m_torrents[storage]->set_lookbehind_pieces(pieces);
        }
    }

    void clear_lookbehind(storage_index_t storage)
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (storage < m_torrents.end_index() && m_torrents[storage])
        {
            m_torrents[storage]->clear_lookbehind();
        }
    }

    bool is_lookbehind_available(storage_index_t storage, int piece) const
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (storage < m_torrents.end_index() && m_torrents[storage])
        {
            return m_torrents[storage]->is_lookbehind_available(piece);
        }
        return false;
    }

    void get_lookbehind_stats(storage_index_t storage,
                              int& available, int& protected_count,
                              std::int64_t& memory) const
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (storage < m_torrents.end_index() && m_torrents[storage])
        {
            available = m_torrents[storage]->get_lookbehind_available_count();
            protected_count = m_torrents[storage]->get_lookbehind_protected_count();
            memory = m_torrents[storage]->get_lookbehind_memory_used();
        }
        else
        {
            available = 0;
            protected_count = 0;
            memory = 0;
        }
    }
};

// ============================================================================
// Factory function for session_params
// ============================================================================

std::unique_ptr<disk_interface> memory_disk_constructor(
    io_context& ioc, settings_interface const&, counters&)
{
    return std::make_unique<memory_disk_io>(ioc);
}

} // namespace libtorrent

#endif // TORRENT_MEMORY_DISK_IO_HPP_INCLUDED
