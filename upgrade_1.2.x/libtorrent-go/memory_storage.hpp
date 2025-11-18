/*
 * memory_storage.hpp - In-memory storage for libtorrent 1.2.x
 *
 * This is the upgraded version compatible with libtorrent 1.2.x API.
 * Key changes from 1.1.x:
 * - Uses span<> instead of pointer+count for readv/writev
 * - Uses piece_index_t instead of raw int for piece indices
 * - Uses std::mutex instead of boost::mutex
 * - Updated storage_interface signatures
 * - Integrated lookbehind buffer functionality
 */

#ifndef TORRENT_MEMORY_STORAGE_HPP_INCLUDED
#define TORRENT_MEMORY_STORAGE_HPP_INCLUDED

#include <cmath>
#include <memory>
#include <algorithm>
#include <iostream>
#include <mutex>
#include <chrono>
#include <vector>
#include <string>

#include <boost/dynamic_bitset.hpp>

#include <libtorrent/error_code.hpp>
#include <libtorrent/bencode.hpp>
#include <libtorrent/storage.hpp>
#include <libtorrent/storage_defs.hpp>
#include <libtorrent/fwd.hpp>
#include <libtorrent/entry.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent.hpp>
#include <libtorrent/span.hpp>
#include <libtorrent/units.hpp>
#include <libtorrent/disk_interface.hpp>

typedef boost::dynamic_bitset<> Bitset;

namespace libtorrent {

// Global memory size setting
std::int64_t memory_size = 0;

// Get current time in milliseconds
std::chrono::steady_clock::time_point now() {
    return std::chrono::steady_clock::now();
}

struct memory_piece
{
public:
    int index;
    int length;
    int size;
    int bi;  // buffer index
    bool is_completed;
    bool is_read;

    memory_piece(int i, int len) : index(i), length(len) {
        size = 0;
        bi = -1;
        is_completed = false;
        is_read = false;
    }

    bool is_buffered() const {
        return bi != -1;
    }

    void reset() {
        bi = -1;
        is_completed = false;
        is_read = false;
        size = 0;
    }
};

struct memory_buffer
{
public:
    int index;
    int length;
    std::vector<char> buffer;
    int pi;  // piece index
    bool is_used;
    std::chrono::steady_clock::time_point accessed;

    memory_buffer(int idx, int len) : index(idx), length(len) {
        pi = -1;
        is_used = false;
        buffer.resize(length);
        accessed = now();
    }

    bool is_assigned() const {
        return pi != -1;
    }

    void reset() {
        is_used = false;
        pi = -1;
        accessed = now();
        std::fill(buffer.begin(), buffer.end(), '\0');
    }
};

struct memory_storage : storage_interface
{
private:
    std::mutex m_mutex;
    std::mutex r_mutex;

public:
    Bitset reader_pieces;
    Bitset reserved_pieces;
    Bitset lookbehind_pieces;

    std::string id;
    std::int64_t capacity;

    int piece_count;
    std::int64_t piece_length;
    std::vector<memory_piece> pieces;

    int buffer_size;
    int buffer_limit;
    int buffer_used;
    int buffer_reserved;
    std::vector<memory_buffer> buffers;

    file_storage const* m_files;
    torrent_info const* m_info;
    libtorrent::torrent_handle* m_handle;
    libtorrent::torrent* t;

    bool is_logging;
    bool is_initialized;
    bool is_reading;

    // Constructor for libtorrent 1.2.x
    // Takes file_storage reference as per 1.2.x pattern
    explicit memory_storage(file_storage const& fs, torrent_info const* info)
        : storage_interface(fs)
    {
        piece_count = 0;
        piece_length = 0;
        buffer_size = 0;
        buffer_limit = 0;
        buffer_used = 0;
        buffer_reserved = 0;
        is_logging = false;
        is_initialized = false;
        is_reading = false;
        m_handle = nullptr;
        t = nullptr;

        m_files = &fs;
        m_info = info;

        capacity = memory_size;
        piece_count = m_info->num_pieces();
        piece_length = m_info->piece_length();

        std::cerr << "INFO Init with mem size " << memory_size
                  << ", Pieces: " << piece_count
                  << ", Piece length: " << piece_length << std::endl;

        for (int i = 0; i < piece_count; i++) {
            pieces.push_back(memory_piece(i, m_info->piece_size(piece_index_t(i))));
        }

        // Using max possible buffers + 2
        buffer_size = static_cast<int>(std::ceil(static_cast<double>(capacity) / piece_length) + 2);
        if (buffer_size > piece_count) {
            buffer_size = piece_count;
        }
        buffer_limit = buffer_size;
        std::cerr << "INFO Using " << buffer_size << " buffers" << std::endl;

        for (int i = 0; i < buffer_size; i++) {
            buffers.push_back(memory_buffer(i, static_cast<int>(piece_length)));
        }

        reader_pieces.resize(piece_count + 10);
        reserved_pieces.resize(piece_count + 10);
        lookbehind_pieces.resize(piece_count + 10);

        is_initialized = true;
    }

    ~memory_storage() override = default;

    void initialize(storage_error& ec) override {}

    std::int64_t get_memory_size() const {
        return capacity;
    }

    void set_memory_size(std::int64_t s) {
        if (s <= capacity) return;

        std::unique_lock<std::mutex> scoped_lock(m_mutex);

        capacity = s;
        int prev_buffer_size = buffer_size;

        // Using max possible buffers + 2
        buffer_size = static_cast<int>(std::ceil(static_cast<double>(capacity) / piece_length) + 2);
        if (buffer_size > piece_count) {
            buffer_size = piece_count;
        }
        buffer_limit = buffer_size;

        if (prev_buffer_size == buffer_size) {
            std::cerr << "INFO Not increasing buffer due to same size (" << buffer_size << ")" << std::endl;
            return;
        }

        std::cerr << "INFO Increasing buffer to " << buffer_size << " buffers" << std::endl;

        for (int i = prev_buffer_size; i < buffer_size; i++) {
            buffers.push_back(memory_buffer(i, static_cast<int>(piece_length)));
        }
    }

    // Simple read function for external use
    int read(char* read_buf, int size, int piece, int offset) {
        if (!is_initialized) return 0;
        is_reading = true;

        if (is_logging) {
            printf("Read start: %d, off: %d, size: %d \n", piece, offset, size);
        }

        if (!get_read_buffer(&pieces[piece])) {
            if (is_logging) {
                std::cerr << "INFO nobuffer: " << piece << ", off: " << offset << std::endl;
            }
            restore_piece(piece);
            return -1;
        }

        if (pieces[piece].size < pieces[piece].length) {
            if (is_logging) {
                std::cerr << "INFO less: " << piece << ", off: " << offset
                          << ", size: " << pieces[piece].size
                          << ", length: " << pieces[piece].length << std::endl;
            }
            restore_piece(piece);
            return -1;
        }

        int available = static_cast<int>(buffers[pieces[piece].bi].buffer.size()) - offset;
        if (available <= 0) return 0;
        if (available > size) available = size;

        if (is_logging) {
            printf("       pre: %d, off: %d, size: %d, available: %d \n", piece, offset, size, available);
        }
        memcpy(read_buf, &buffers[pieces[piece].bi].buffer[offset], available);

        if (pieces[piece].is_completed && offset + available >= pieces[piece].size) {
            pieces[piece].is_read = true;
        }

        buffers[pieces[piece].bi].accessed = now();

        return size;
    }

    // libtorrent 1.2.x readv using span<>
    int readv(span<iovec_t const> bufs, piece_index_t piece, int offset,
              open_mode_t mode, storage_error& ec) override
    {
        int piece_idx = static_cast<int>(piece);

        if (!is_initialized) return 0;

        if (is_logging) {
            std::cerr << "INFO readv in  p: " << piece_idx << ", off: " << offset << std::endl;
        }

        if (!get_read_buffer(&pieces[piece_idx])) {
            if (is_logging) {
                std::cerr << "INFO noreadbuffer: " << piece_idx << std::endl;
            }
            return 0;
        }

        int file_offset = offset;
        int n = 0;

        for (auto const& buf : bufs) {
            int const to_copy = std::min(
                static_cast<int>(buffers[pieces[piece_idx].bi].buffer.size()) - file_offset,
                static_cast<int>(buf.size())
            );
            memcpy(buf.data(), &buffers[pieces[piece_idx].bi].buffer[file_offset], to_copy);
            file_offset += to_copy;
            n += to_copy;
        }

        if (is_logging) {
            std::cerr << "INFO readv out p: " << piece_idx
                      << ", pl: " << pieces[piece_idx].length
                      << ", bufs: " << bufs.size()
                      << ", off: " << offset
                      << ", bs: " << buffers[pieces[piece_idx].bi].buffer.size()
                      << ", res: " << n << std::endl;
        }

        if (pieces[piece_idx].is_completed && offset + n >= pieces[piece_idx].size) {
            pieces[piece_idx].is_read = true;
        }

        buffers[pieces[piece_idx].bi].accessed = now();

        return n;
    }

    // libtorrent 1.2.x writev using span<>
    int writev(span<iovec_t const> bufs, piece_index_t piece, int offset,
               open_mode_t mode, storage_error& ec) override
    {
        int piece_idx = static_cast<int>(piece);

        if (is_logging) {
            int total_size = 0;
            for (auto const& buf : bufs) total_size += static_cast<int>(buf.size());
            std::cerr << "INFO writev in  p: " << piece_idx << ", off: " << offset
                      << ", bufs: " << total_size << std::endl;
        }

        if (!is_initialized) return 0;

        if (!get_write_buffer(&pieces[piece_idx])) {
            if (is_logging) {
                std::cerr << "INFO nowritebuffer: " << piece_idx << std::endl;
            }
            return 0;
        }

        int file_offset = offset;
        int n = 0;

        for (auto const& buf : bufs) {
            int const to_copy = std::min(
                pieces[piece_idx].length - file_offset,
                static_cast<int>(buf.size())
            );
            std::memcpy(&buffers[pieces[piece_idx].bi].buffer[file_offset], buf.data(), to_copy);
            file_offset += to_copy;
            n += to_copy;
        }

        if (is_logging) {
            std::cerr << "INFO writev out p: " << piece_idx
                      << ", pl: " << pieces[piece_idx].length
                      << ", bufs: " << bufs.size()
                      << ", off: " << offset
                      << ", bs: " << buffers[pieces[piece_idx].bi].buffer.size()
                      << ", res: " << n << std::endl;
        }

        pieces[piece_idx].size += n;
        buffers[pieces[piece_idx].bi].accessed = now();

        if (buffer_used >= buffer_limit) {
            trim(piece_idx);
        }

        return n;
    }

    void rename_file(file_index_t index, std::string const& new_filename,
                     storage_error& ec) override {}

    status_t move_storage(std::string const& save_path, move_flags_t flags,
                          storage_error& ec) override {
        return status_t::no_error;
    }

    bool verify_resume_data(add_torrent_params const& rd,
                            aux::vector<std::string, file_index_t> const& links,
                            storage_error& ec) override {
        return false;
    }

    void write_resume_data(entry& rd, storage_error& ec) const override {}

    void release_files(storage_error& ec) override {}

    bool has_any_file(storage_error& ec) override {
        if (is_logging) {
            printf("Has any file\n");
        }
        return false;
    }

    void delete_files(remove_flags_t options, storage_error& ec) override {
        if (is_logging) {
            printf("Delete files\n");
        }
    }

    void set_torrent_handle(libtorrent::torrent_handle* h) {
        m_handle = h;
        t = m_handle->native_handle().get();
    }

    // ========================================================================
    // Buffer management functions
    // ========================================================================

    bool get_read_buffer(memory_piece* p) {
        return get_buffer(p, false);
    }

    bool get_write_buffer(memory_piece* p) {
        return get_buffer(p, true);
    }

    bool get_buffer(memory_piece* p, bool is_write) {
        if (p->is_buffered()) {
            return true;
        } else if (!is_write) {
            // Trying to lock and get to make sure we are not affected
            // by write/read at the same time.
            std::unique_lock<std::mutex> scoped_lock(m_mutex);
            return p->is_buffered();
        }

        std::unique_lock<std::mutex> scoped_lock(m_mutex);

        // Once again checking in case we had multiple writes in parallel
        if (p->is_buffered()) return true;

        // Check if piece is not in reader ranges and avoid allocation
        if (is_reading && !is_readered(p->index)) {
            restore_piece(p->index);
            return false;
        }

        for (int i = 0; i < buffer_size; i++) {
            if (buffers[i].is_used) {
                continue;
            }

            if (is_logging) {
                std::cerr << "INFO Setting buffer " << buffers[i].index
                          << " to piece " << p->index << std::endl;
            }

            buffers[i].is_used = true;
            buffers[i].pi = p->index;
            buffers[i].accessed = now();

            p->bi = buffers[i].index;

            // If we are placing permanent buffer entry - we should reduce the limit,
            // to properly check for the usage.
            if (reserved_pieces.test(p->index) || lookbehind_pieces.test(p->index)) {
                buffer_limit--;
            } else {
                buffer_used++;
            }

            break;
        }

        return p->is_buffered();
    }

    void trim(int pi) {
        if (capacity < 0 || buffer_used < buffer_limit) {
            return;
        }

        std::unique_lock<std::mutex> scoped_lock(m_mutex);

        while (buffer_used >= buffer_limit) {
            if (is_logging) {
                std::cerr << "INFO Trimming " << buffer_used << " to " << buffer_limit
                          << " with reserved " << buffer_reserved
                          << ", " << get_buffer_info() << std::endl;
            }

            if (!reader_pieces.empty()) {
                int bi = find_last_buffer(pi, true);
                if (bi != -1) {
                    if (is_logging) {
                        std::cerr << "INFO Removing non-read piece: " << buffers[bi].pi
                                  << ", buffer:" << bi << std::endl;
                    }
                    remove_piece(bi);
                    continue;
                }
            }

            int bi = find_last_buffer(pi, false);
            if (bi != -1) {
                if (is_logging) {
                    std::cerr << "INFO Removing LRU piece: " << buffers[bi].pi
                              << ", buffer:" << bi << std::endl;
                }
                remove_piece(bi);
                continue;
            }

            // No piece found to remove, break to avoid infinite loop
            break;
        }
    }

    std::string get_buffer_info() {
        std::string result = "";

        for (size_t i = 0; i < buffers.size(); i++) {
            if (!result.empty()) result += " ";
            result += std::to_string(buffers[i].index) + ":" + std::to_string(buffers[i].pi);
        }

        return result;
    }

    int find_last_buffer(int pi, bool check_read) {
        int bi = -1;
        auto minTime = now();
        std::unique_lock<std::mutex> scoped_lock(r_mutex);

        for (size_t i = 0; i < buffers.size(); i++) {
            if (buffers[i].is_used && buffers[i].is_assigned()
                && !is_reserved(buffers[i].pi)
                && !is_lookbehind_protected(buffers[i].pi)
                && buffers[i].pi != pi
                && (!check_read || !is_readered(buffers[i].pi))
                && buffers[i].accessed < minTime) {
                bi = buffers[i].index;
                minTime = buffers[i].accessed;
            }
        }

        return bi;
    }

    void remove_piece(int bi) {
        int pi = buffers[bi].pi;

        buffers[bi].reset();
        buffer_used--;

        if (pi != -1 && pi < piece_count) {
            pieces[pi].reset();
            restore_piece(pi);
        }
    }

    void restore_piece(int pi) {
        if (!m_handle || !t) return;

        if (is_logging) {
            std::cerr << "INFO Restoring piece: " << pi << std::endl;
        }

        piece_index_t piece_idx(pi);
        t->reset_piece_deadline(piece_idx);
        t->picker().set_piece_priority(piece_idx, dont_download);
        t->picker().we_dont_have(piece_idx);
    }

    void enable_logging() {
        is_logging = true;
    }

    void disable_logging() {
        is_logging = false;
    }

    void update_reader_pieces(std::vector<int> const& piece_list) {
        if (!is_initialized) return;

        std::unique_lock<std::mutex> scoped_lock(r_mutex);
        reader_pieces.reset();
        for (int piece : piece_list) {
            if (piece >= 0 && piece < piece_count) {
                reader_pieces.set(piece);
            }
        }
    }

    void update_reserved_pieces(std::vector<int> const& piece_list) {
        if (!is_initialized) return;

        std::unique_lock<std::mutex> scoped_lock(r_mutex);
        buffer_reserved = 0;
        reserved_pieces.reset();
        for (int piece : piece_list) {
            if (piece >= 0 && piece < piece_count) {
                reserved_pieces.set(piece);
                buffer_reserved++;
            }
        }
    }

    bool is_reserved(int index) const {
        if (!is_initialized || index < 0 || index >= piece_count) return false;
        return reserved_pieces.test(index);
    }

    bool is_readered(int index) {
        if (!is_initialized) return false;

        if (!m_handle) {
            std::cerr << "INFO no handle" << std::endl;
            return true;
        }

        return m_handle->piece_priority(piece_index_t(index)) != dont_download;
    }

    // ========================================================================
    // Lookbehind buffer methods
    // ========================================================================

    void set_lookbehind_pieces(std::vector<int> const& piece_list) {
        if (!is_initialized) return;

        std::unique_lock<std::mutex> scoped_lock(r_mutex);

        // Clear previous lookbehind protection
        for (int i = 0; i < piece_count; i++) {
            if (lookbehind_pieces.test(i)) {
                // Only clear from reserved if it was set by lookbehind
                if (!reserved_pieces.test(i)) {
                    // It's fine, was never in reserved
                }
            }
        }
        lookbehind_pieces.reset();

        // Set new lookbehind pieces
        for (int piece : piece_list) {
            if (piece >= 0 && piece < piece_count) {
                lookbehind_pieces.set(piece);
            }
        }
    }

    void clear_lookbehind() {
        if (!is_initialized) return;

        std::unique_lock<std::mutex> scoped_lock(r_mutex);
        lookbehind_pieces.reset();
    }

    bool is_lookbehind_protected(int index) const {
        if (!is_initialized || index < 0 || index >= piece_count) return false;
        return lookbehind_pieces.test(index);
    }

    bool is_lookbehind_available(int piece) const {
        if (!is_initialized || piece < 0 || piece >= piece_count) return false;
        if (!lookbehind_pieces.test(piece)) return false;
        return pieces[piece].bi >= 0;
    }

    int get_lookbehind_available_count() const {
        if (!is_initialized) return 0;

        int count = 0;
        for (int i = 0; i < piece_count; i++) {
            if (lookbehind_pieces.test(i) && pieces[i].bi >= 0) {
                count++;
            }
        }
        return count;
    }

    int get_lookbehind_protected_count() const {
        if (!is_initialized) return 0;
        return static_cast<int>(lookbehind_pieces.count());
    }

    std::int64_t get_lookbehind_memory_used() const {
        return static_cast<std::int64_t>(get_lookbehind_available_count()) * piece_length;
    }
};

// Storage constructor function for 1.2.x
storage_interface* memory_storage_constructor(storage_params const& params, file_pool&)
{
    return new memory_storage(params.files, params.info);
}

} // namespace libtorrent

#endif // TORRENT_MEMORY_STORAGE_HPP_INCLUDED
