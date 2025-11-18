/*
 * priority_types.i - SWIG interface for download_priority_t handling
 *
 * In libtorrent 1.2.x, priorities use strongly typed enums.
 * This interface provides conversion helpers for Go code.
 */

%{
#include <libtorrent/download_priority.hpp>
%}

// Define the priority type
namespace libtorrent {
    // Strongly typed priority enum
    enum class download_priority_t : std::uint8_t {};

    // Named priority constants
    constexpr download_priority_t dont_download{0};
    constexpr download_priority_t low_priority{1};
    constexpr download_priority_t default_priority{4};
    constexpr download_priority_t top_priority{7};
}

// Include the header
%include <libtorrent/download_priority.hpp>

// Create Go-friendly constants
%constant int PRIORITY_DONT_DOWNLOAD = 0;
%constant int PRIORITY_LOW = 1;
%constant int PRIORITY_DEFAULT = 4;
%constant int PRIORITY_TOP = 7;

// Helper functions to convert between int and download_priority_t
%inline %{
namespace libtorrent {
    // Convert int to download_priority_t
    download_priority_t int_to_priority(int p) {
        return static_cast<download_priority_t>(p);
    }

    // Convert download_priority_t to int
    int priority_to_int(download_priority_t p) {
        return static_cast<int>(static_cast<std::uint8_t>(p));
    }
}
%}

// Extend torrent_handle with int-based priority methods
%extend libtorrent::torrent_handle {
    // Get piece priority as int
    int get_piece_priority_int(int piece) {
        return static_cast<int>(static_cast<std::uint8_t>(
            self->piece_priority(libtorrent::piece_index_t(piece))
        ));
    }

    // Set piece priority from int
    void set_piece_priority_int(int piece, int priority) {
        self->piece_priority(
            libtorrent::piece_index_t(piece),
            static_cast<libtorrent::download_priority_t>(priority)
        );
    }

    // Get file priority as int
    int get_file_priority_int(int file) {
        return static_cast<int>(static_cast<std::uint8_t>(
            self->file_priority(libtorrent::file_index_t(file))
        ));
    }

    // Set file priority from int
    void set_file_priority_int(int file, int priority) {
        self->file_priority(
            libtorrent::file_index_t(file),
            static_cast<libtorrent::download_priority_t>(priority)
        );
    }
}
