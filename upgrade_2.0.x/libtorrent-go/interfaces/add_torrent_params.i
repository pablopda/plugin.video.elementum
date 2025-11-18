/*
 * add_torrent_params.i - SWIG interface for libtorrent 2.0.x
 *
 * Key changes from 1.2.x:
 * - info_hash -> info_hashes (info_hash_t with v1 + v2)
 * - storage constructor removed (use session_params::disk_io_constructor)
 * - url field removed (use parse_magnet_uri)
 * - uuid removed (RSS support removed)
 */

%{
#include <memory>
#include <stdexcept>
#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/read_resume_data.hpp>
#include <libtorrent/write_resume_data.hpp>
#include <libtorrent/info_hash.hpp>
#include <libtorrent/error_code.hpp>
%}

%include <std_shared_ptr.i>
%shared_ptr(libtorrent::torrent_info)

%ignore libtorrent::add_torrent_params::ti;

// Deprecated/removed in 2.0.x
%ignore libtorrent::add_torrent_params::info_hash;   // Use info_hashes
%ignore libtorrent::add_torrent_params::storage;     // Use session_params
%ignore libtorrent::add_torrent_params::url;         // Use parse_magnet_uri
%ignore libtorrent::add_torrent_params::uuid;        // RSS removed

%include <libtorrent/add_torrent_params.hpp>
%include <libtorrent/magnet_uri.hpp>

// Safe wrapper for parse_magnet_uri that handles error_code and throws on failure
// This allows Go to receive proper error returns via SWIG exception handling
%inline %{
libtorrent::add_torrent_params parse_magnet_uri(std::string const& uri) {
    libtorrent::error_code ec;
    libtorrent::add_torrent_params params = libtorrent::parse_magnet_uri(uri, ec);
    if (ec) {
        throw std::runtime_error("Failed to parse magnet URI: " + ec.message());
    }
    return params;
}

// Alternative version that also returns the error message for inspection
// Returns empty params with default-constructed info_hashes on error
libtorrent::add_torrent_params parse_magnet_uri_with_error(std::string const& uri, std::string& error_out) {
    libtorrent::error_code ec;
    libtorrent::add_torrent_params params = libtorrent::parse_magnet_uri(uri, ec);
    if (ec) {
        error_out = ec.message();
    } else {
        error_out = "";
    }
    return params;
}
%}

%extend libtorrent::add_torrent_params {
    const libtorrent::torrent_info* get_torrent_info() {
        return self->ti.get();
    }

    void set_torrent_info(libtorrent::torrent_info torrent_info) {
        self->ti = std::make_shared<libtorrent::torrent_info>(torrent_info);
    }

    // Note: In 2.0.x, storage is configured at session level via session_params
    // The storage field no longer exists in add_torrent_params

    // Info hash access (2.0.x uses info_hashes)
    void set_info_hash_v1(std::string const& hex) {
        libtorrent::aux::from_hex(hex, self->info_hashes.v1.data());
    }

    void set_info_hash_v2(std::string const& hex) {
        // v2 is truncated SHA-256 for storage
        libtorrent::sha256_hash h;
        libtorrent::aux::from_hex(hex, h.data());
        self->info_hashes.v2 = h;
    }

    libtorrent::info_hash_t get_info_hashes() const {
        return self->info_hashes;
    }

    std::string get_info_hash_v1_hex() const {
        return libtorrent::aux::to_hex(self->info_hashes.v1);
    }

    bool has_v1() const {
        return self->info_hashes.has_v1();
    }

    bool has_v2() const {
        return self->info_hashes.has_v2();
    }
}

// Resume data functions (same as 1.2.x)
namespace libtorrent {
    add_torrent_params read_resume_data(span<char const> buffer, error_code& ec);
    add_torrent_params read_resume_data(bdecode_node const& rd, error_code& ec);
    entry write_resume_data(add_torrent_params const& atp);
    std::vector<char> write_resume_data_buf(add_torrent_params const& atp);
}

%include <libtorrent/read_resume_data.hpp>
%include <libtorrent/write_resume_data.hpp>
