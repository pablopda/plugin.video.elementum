/*
 * add_torrent_params.i - SWIG interface for libtorrent 1.2.x
 *
 * Key changes from 1.1.x:
 * - Uses std::shared_ptr instead of boost::shared_ptr
 * - Updated resume data handling
 */

%{
#include <memory>
#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/read_resume_data.hpp>
#include <libtorrent/write_resume_data.hpp>
%}

%include <std_shared_ptr.i>
%shared_ptr(libtorrent::torrent_info)

%extend libtorrent::add_torrent_params {
    const libtorrent::torrent_info* get_torrent_info() {
        return self->ti.get();
    }

    void set_torrent_info(libtorrent::torrent_info torrent_info) {
        self->ti = std::make_shared<libtorrent::torrent_info>(torrent_info);
    }

    void set_memory_storage(std::int64_t size) {
        libtorrent::memory_size = size;
        self->storage = libtorrent::memory_storage_constructor;
    }

    // New resume data API for 1.2.x
    // The old resume_data field is deprecated
    // Use read_resume_data() to create add_torrent_params from resume data
}

%ignore libtorrent::add_torrent_params::ti;

// Deprecated in 1.2.x - resume_data field
// %ignore libtorrent::add_torrent_params::resume_data;

%include <libtorrent/add_torrent_params.hpp>
%include <libtorrent/magnet_uri.hpp>

// New functions for resume data in 1.2.x
namespace libtorrent {
    add_torrent_params read_resume_data(span<char const> buffer, error_code& ec);
    add_torrent_params read_resume_data(bdecode_node const& rd, error_code& ec);
    entry write_resume_data(add_torrent_params const& atp);
    std::vector<char> write_resume_data_buf(add_torrent_params const& atp);
}

%include <libtorrent/read_resume_data.hpp>
%include <libtorrent/write_resume_data.hpp>
