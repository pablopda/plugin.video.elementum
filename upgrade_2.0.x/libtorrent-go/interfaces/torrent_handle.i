/*
 * torrent_handle.i - SWIG interface for libtorrent 2.0.x
 *
 * Key changes from 1.2.x:
 * - info_hash() -> info_hashes() (returns info_hash_t)
 * - get_storage_impl() removed (storage is session-level)
 * - Uses strong types: piece_index_t, file_index_t, download_priority_t
 * - announce_entry structure changed for hybrid torrents
 */

%{
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/torrent.hpp>
#include <libtorrent/entry.hpp>
#include <libtorrent/announce_entry.hpp>
#include <libtorrent/info_hash.hpp>
#include <libtorrent/error_code.hpp>
%}

// Factory function for creating torrent_info from file path
// This is exposed as NewTorrentInfo in Go with error handling
%inline %{
namespace libtorrent {
    // Create torrent_info from .torrent file path
    // Returns nullptr on error, with error details in ec
    torrent_info* new_torrent_info(std::string const& path, error_code& ec) {
        try {
            return new torrent_info(path, ec);
        } catch (std::exception const& e) {
            ec = errors::invalid_torrent_file;
            return nullptr;
        }
    }

    // Create torrent_info from in-memory buffer
    // Useful for loading torrent data from network or storage
    torrent_info* new_torrent_info_from_buffer(char const* data, int size, error_code& ec) {
        try {
            return new torrent_info(span<char const>(data, size), ec);
        } catch (std::exception const& e) {
            ec = errors::invalid_torrent_file;
            return nullptr;
        }
    }

    // Delete torrent_info object - for proper memory management from Go
    void delete_torrent_info(torrent_info* ti) {
        delete ti;
    }
}
%}

%include <std_vector.i>
%include <std_pair.i>
%include <carrays.i>

%template(stdVectorPartialPieceInfo) std::vector<libtorrent::partial_piece_info>;
%template(stdVectorAnnounceEntry) std::vector<libtorrent::announce_entry>;
%template(stdVectorTorrentHandle) std::vector<libtorrent::torrent_handle>;

%feature("director") torrent_handle;
%feature("director") torrent_info;
%feature("director") torrent_status;

// Equaler interface
%rename(Equal) libtorrent::torrent_handle::operator==;
%rename(NotEqual) libtorrent::torrent_handle::operator!=;
%rename(Less) libtorrent::torrent_handle::operator<;

%array_class(libtorrent::block_info, block_info_list);

%extend libtorrent::torrent_handle {
    const libtorrent::torrent_info* torrent_file() {
        auto ti = self->torrent_file();
        return ti.get();
    }

    // Note: get_storage_impl() is REMOVED in 2.0.x
    // Storage is now session-level via disk_interface
    // Use storage_index_t from add_torrent to access storage

    // Info hash access (2.0.x)
    libtorrent::info_hash_t get_info_hashes() const {
        return self->info_hashes();
    }

    std::string info_hash_v1_string() const {
        return libtorrent::aux::to_hex(self->info_hashes().v1);
    }

    std::string info_hash_best_string() const {
        return libtorrent::aux::to_hex(self->info_hashes().get_best());
    }

    bool has_v1() const {
        return self->info_hashes().has_v1();
    }

    bool has_v2() const {
        return self->info_hashes().has_v2();
    }

    // Piece operations with int wrapper for Go compatibility
    int piece_priority_int(int piece) {
        return static_cast<int>(self->piece_priority(libtorrent::piece_index_t(piece)));
    }

    void set_piece_priority_int(int piece, int priority) {
        self->piece_priority(libtorrent::piece_index_t(piece),
                            static_cast<libtorrent::download_priority_t>(priority));
    }

    // File operations with int wrapper
    int file_priority_int(int file) {
        return static_cast<int>(self->file_priority(libtorrent::file_index_t(file)));
    }

    void set_file_priority_int(int file, int priority) {
        self->file_priority(libtorrent::file_index_t(file),
                           static_cast<libtorrent::download_priority_t>(priority));
    }

    // Piece deadline with int wrapper
    void set_piece_deadline_int(int piece, int deadline) {
        self->set_piece_deadline(libtorrent::piece_index_t(piece), deadline);
    }

    void reset_piece_deadline_int(int piece) {
        self->reset_piece_deadline(libtorrent::piece_index_t(piece));
    }

    void clear_piece_deadlines() {
        self->clear_piece_deadlines();
    }

    // Client data access (2.0.x)
    void* get_userdata() const {
        return static_cast<void*>(self->userdata());
    }
}

// Deprecated/removed in 2.0.x
%ignore libtorrent::torrent_handle::torrent_file;
%ignore libtorrent::torrent_handle::use_interface;
%ignore libtorrent::torrent_handle::info_hash;          // Use info_hashes()
%ignore libtorrent::torrent_handle::get_storage_impl;   // Removed

%extend libtorrent::partial_piece_info {
    block_info_list* blocks() {
        return block_info_list_frompointer(self->blocks);
    }
}
%ignore libtorrent::partial_piece_info::blocks;
%ignore libtorrent::hash_value;
%ignore libtorrent::block_info::peer;
%ignore libtorrent::block_info::set_peer;

// Torrent status extensions for 2.0.x
%extend libtorrent::torrent_status {
    // Info hash access
    libtorrent::info_hash_t get_info_hashes() const {
        return self->info_hashes;
    }

    std::string get_info_hash_string() const {
        return libtorrent::aux::to_hex(self->info_hashes.v1);
    }

    // Timing helpers (1.2.x+ use chrono)
    std::int64_t get_active_time_seconds() const {
        return std::chrono::duration_cast<std::chrono::seconds>(
            self->active_duration).count();
    }

    std::int64_t get_finished_time_seconds() const {
        return std::chrono::duration_cast<std::chrono::seconds>(
            self->finished_duration).count();
    }

    std::int64_t get_seeding_time_seconds() const {
        return std::chrono::duration_cast<std::chrono::seconds>(
            self->seeding_duration).count();
    }
}

// Deprecated in 2.0.x
%ignore libtorrent::torrent_status::info_hash;

%include <libtorrent/entry.hpp>
%include <libtorrent/torrent_info.hpp>
%include <libtorrent/torrent_handle.hpp>
%include <libtorrent/torrent_status.hpp>
%include <libtorrent/torrent.hpp>
%include <libtorrent/announce_entry.hpp>

// Torrent info extensions for common operations
%extend libtorrent::torrent_info {
    // Get info hash as hex string (v1)
    std::string info_hash_hex() const {
        return libtorrent::aux::to_hex(self->info_hashes().v1);
    }

    // Get best info hash as hex string
    std::string best_info_hash_hex() const {
        return libtorrent::aux::to_hex(self->info_hashes().get_best());
    }

    // Get v2 info hash as hex string (empty if not hybrid)
    std::string info_hash_v2_hex() const {
        if (self->info_hashes().has_v2()) {
            return libtorrent::aux::to_hex(self->info_hashes().v2);
        }
        return "";
    }

    // Check if hybrid torrent (has both v1 and v2)
    bool is_hybrid() const {
        return self->info_hashes().has_v1() && self->info_hashes().has_v2();
    }

    // Get number of files
    int num_files_int() const {
        return self->num_files();
    }

    // Get total size
    std::int64_t total_size_int() const {
        return self->total_size();
    }

    // Get piece length
    int piece_length_int() const {
        return self->piece_length();
    }

    // Get number of pieces
    int num_pieces_int() const {
        return self->num_pieces();
    }

    // Get file path by index (with int for Go compatibility)
    std::string file_path_at(int index) const {
        return self->files().file_path(libtorrent::file_index_t(index));
    }

    // Get file size by index (with int for Go compatibility)
    std::int64_t file_size_at(int index) const {
        return self->files().file_size(libtorrent::file_index_t(index));
    }

    // Get file offset by index (with int for Go compatibility)
    std::int64_t file_offset_at(int index) const {
        return self->files().file_offset(libtorrent::file_index_t(index));
    }
}

// Announce entry extensions for hybrid torrent support
%extend libtorrent::announce_entry {
    // Get tracker URL
    std::string get_url() const {
        return self->url;
    }

    // Get tier
    int get_tier() const {
        return self->tier;
    }

    // Check if verified
    bool is_verified() const {
        return self->verified;
    }
}

// announce_endpoint and announce_infohash for hybrid torrent iteration
%extend libtorrent::announce_endpoint {
    // Get V1 announce info
    libtorrent::announce_infohash const& get_v1_info() const {
        return self->info_hashes[0];
    }

    // Get V2 announce info
    libtorrent::announce_infohash const& get_v2_info() const {
        return self->info_hashes[1];
    }
}

%extend libtorrent::announce_infohash {
    // Get number of failures
    int get_fails() const {
        return self->fails;
    }

    // Get message
    std::string get_message() const {
        return self->message;
    }

    // Is updating
    bool is_updating() const {
        return self->updating;
    }
}
