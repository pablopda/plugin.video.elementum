/*
 * info_hash.i - SWIG interface for libtorrent 2.0.x info_hash_t
 *
 * In 2.0.x, torrents can have dual info hashes:
 * - v1: SHA-1 (20 bytes)
 * - v2: SHA-256 (32 bytes)
 *
 * info_hash_t bundles both hashes together.
 */

%{
#include <libtorrent/info_hash.hpp>
#include <libtorrent/hex.hpp>
%}

%include <libtorrent/info_hash.hpp>

// Helper methods for info_hash_t
%extend libtorrent::info_hash_t {
    // Get v1 hash as hex string
    std::string v1_hex() const {
        return lt::aux::to_hex(self->v1);
    }

    // Get best available hash as hex string (prefers v2)
    std::string best_hex() const {
        return lt::aux::to_hex(self->get_best());
    }

    // Check if has v1 hash
    bool has_v1() const {
        return self->has_v1();
    }

    // Check if has v2 hash
    bool has_v2() const {
        return self->has_v2();
    }

    // For backward compatibility - returns v1 hash string
    std::string to_string() const {
        return lt::aux::to_hex(self->v1);
    }
}

// Update torrent_status for info_hashes
%extend libtorrent::torrent_status {
    // Get info hashes (2.0.x way)
    libtorrent::info_hash_t get_info_hashes() const {
        return self->info_hashes;
    }

    // Backward compatible - get v1 hash
    std::string get_info_hash_string() const {
        return lt::aux::to_hex(self->info_hashes.v1);
    }
}

// Update torrent_handle for info_hashes
%extend libtorrent::torrent_handle {
    // Get info hashes (2.0.x way)
    libtorrent::info_hash_t get_info_hashes() const {
        return self->info_hashes();
    }

    // Backward compatible - get v1 hash string
    std::string info_hash_v1_string() const {
        return lt::aux::to_hex(self->info_hashes().v1);
    }
}

// Update add_torrent_params for info_hashes
%extend libtorrent::add_torrent_params {
    // Set v1 info hash from hex string
    void set_info_hash_v1(std::string const& hex) {
        lt::aux::from_hex(hex, self->info_hashes.v1.data());
    }

    // Get info hashes
    libtorrent::info_hash_t get_info_hashes() const {
        return self->info_hashes;
    }
}

// Ignore deprecated single info_hash field
%ignore libtorrent::add_torrent_params::info_hash;
%ignore libtorrent::torrent_status::info_hash;
%ignore libtorrent::torrent_handle::info_hash;
