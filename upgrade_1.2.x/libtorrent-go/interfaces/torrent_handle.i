/*
 * torrent_handle.i - SWIG interface for libtorrent 1.2.x
 *
 * Key changes from 1.1.x:
 * - Uses piece_index_t instead of raw int in some places
 * - Some functions use span<> for parameters
 */

%{
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/torrent.hpp>
#include <libtorrent/entry.hpp>
#include <libtorrent/announce_entry.hpp>
%}

%include <std_vector.i>
%include <std_pair.i>
%include <carrays.i>

%template(stdVectorPartialPieceInfo) std::vector<libtorrent::partial_piece_info>;
%template(stdVectorAnnounceEntry) std::vector<libtorrent::announce_entry>;
%template(stdVectorTorrentHandle) std::vector<libtorrent::torrent_handle>;

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

    libtorrent::memory_storage* get_memory_storage() {
        return ((libtorrent::memory_storage*) self->get_storage_impl());
    }

    // Helper methods for piece operations with piece_index_t
    int piece_priority_int(int piece) {
        return static_cast<int>(self->piece_priority(libtorrent::piece_index_t(piece)));
    }

    void set_piece_priority_int(int piece, int priority) {
        self->piece_priority(libtorrent::piece_index_t(piece),
                            static_cast<libtorrent::download_priority_t>(priority));
    }
}

%ignore libtorrent::torrent_handle::torrent_file;
%ignore libtorrent::torrent_handle::use_interface;

%extend libtorrent::partial_piece_info {
    block_info_list* blocks() {
        return block_info_list_frompointer(self->blocks);
    }
}
%ignore libtorrent::partial_piece_info::blocks;
%ignore libtorrent::hash_value;
%ignore libtorrent::block_info::peer;
%ignore libtorrent::block_info::set_peer;

%feature("director") torrent_handle;
%feature("director") torrent_info;
%feature("director") torrent_status;

%include <libtorrent/entry.hpp>
%include <libtorrent/torrent_info.hpp>
%include <libtorrent/torrent_handle.hpp>
%include <libtorrent/torrent_status.hpp>
#include <libtorrent/torrent.hpp>
%include <libtorrent/announce_entry.hpp>
