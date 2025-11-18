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
