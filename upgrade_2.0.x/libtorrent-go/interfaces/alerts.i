/*
 * alerts.i - SWIG interface for libtorrent 2.0.x alerts
 *
 * Key changes from 1.2.x:
 * - Alert info_hash fields -> info_hashes (info_hash_t)
 * - stats_alert deprecated (use post_torrent_updates)
 * - socket_type_t enum for connection types
 * - state_update_alert replaces stats_alert
 */

%{
#include <libtorrent/alert.hpp>
#include <libtorrent/alert_types.hpp>
%}

// Alert vector (already defined in session.i)
// %template(stdVectorAlerts) std::vector<libtorrent::alert*>;

// Socket type enum (new in 2.0.x)
namespace libtorrent {
    enum class socket_type_t : std::uint8_t {
        tcp,
        socks5,
        http,
        utp,
        i2p,
        tcp_ssl,
        socks5_ssl,
        http_ssl,
        utp_ssl
    };
}

// Include alert headers
%include <libtorrent/alert.hpp>

// Alert category flags
%include <libtorrent/alert_types.hpp>

// Base alert extensions
%extend libtorrent::alert {
    // Get alert type for type switching in Go
    int alert_type() const {
        return self->type();
    }

    // Get alert category
    int alert_category() const {
        return static_cast<int>(self->category());
    }

    // Get timestamp as seconds since epoch
    std::int64_t timestamp_seconds() const {
        return std::chrono::duration_cast<std::chrono::seconds>(
            self->timestamp().time_since_epoch()).count();
    }
}

// Torrent alert extensions (base class for torrent-specific alerts)
%extend libtorrent::torrent_alert {
    // Get info hashes (2.0.x)
    libtorrent::info_hash_t get_info_hashes() const {
        return self->handle.info_hashes();
    }

    // Get v1 hash string (backward compatible)
    std::string get_info_hash_v1_string() const {
        return lt::aux::to_hex(self->handle.info_hashes().v1);
    }

    // Check if torrent handle is valid
    bool is_valid() const {
        return self->handle.is_valid();
    }
}

// State update alert (replaces stats_alert in 2.0.x)
%extend libtorrent::state_update_alert {
    // Get number of statuses
    int status_count() const {
        return static_cast<int>(self->status.size());
    }

    // Get status at index with bounds checking
    libtorrent::torrent_status const& get_status(int index) const {
        if (index < 0 || index >= static_cast<int>(self->status.size())) {
            throw std::out_of_range("status index out of bounds");
        }
        return self->status[index];
    }
}

// Torrent removed alert (info_hashes instead of info_hash)
%extend libtorrent::torrent_removed_alert {
    // Get info hashes (2.0.x field)
    libtorrent::info_hash_t get_info_hashes() const {
        return self->info_hashes;
    }

    // Get v1 hash string
    std::string get_info_hash_v1_string() const {
        return lt::aux::to_hex(self->info_hashes.v1);
    }

    // Get v2 hash string (empty if no v2 hash)
    std::string get_info_hash_v2_string() const {
        if (self->info_hashes.has_v2()) {
            return libtorrent::aux::to_hex(self->info_hashes.get_best());
        }
        return "";
    }
}

// Torrent deleted alert
%extend libtorrent::torrent_deleted_alert {
    libtorrent::info_hash_t get_info_hashes() const {
        return self->info_hashes;
    }

    std::string get_info_hash_v1_string() const {
        return lt::aux::to_hex(self->info_hashes.v1);
    }
}

// Torrent delete failed alert
%extend libtorrent::torrent_delete_failed_alert {
    libtorrent::info_hash_t get_info_hashes() const {
        return self->info_hashes;
    }

    std::string get_info_hash_v1_string() const {
        return lt::aux::to_hex(self->info_hashes.v1);
    }
}

// Peer alerts with socket_type_t
%extend libtorrent::peer_connect_alert {
    // Get socket type as int
    int get_socket_type() const {
        return static_cast<int>(self->socket_type);
    }
}

%extend libtorrent::peer_disconnected_alert {
    int get_socket_type() const {
        return static_cast<int>(self->socket_type);
    }
}

%extend libtorrent::incoming_connection_alert {
    int get_socket_type() const {
        return static_cast<int>(self->socket_type);
    }
}

// Listen alerts with socket_type_t
%extend libtorrent::listen_failed_alert {
    int get_socket_type() const {
        return static_cast<int>(self->socket_type);
    }
}

%extend libtorrent::listen_succeeded_alert {
    int get_socket_type() const {
        return static_cast<int>(self->socket_type);
    }
}

// Add torrent alert
%extend libtorrent::add_torrent_alert {
    libtorrent::info_hash_t get_info_hashes() const {
        return self->handle.info_hashes();
    }

    // Check if add failed
    bool has_error() const {
        return static_cast<bool>(self->error);
    }

    // Get error message
    std::string get_error_message() const {
        return self->error.message();
    }
}

// Save resume data alert
%extend libtorrent::save_resume_data_alert {
    // Get resume data buffer
    std::vector<char> get_resume_data_buf() const {
        return libtorrent::write_resume_data_buf(self->params);
    }
}

// Tracker alerts
%extend libtorrent::tracker_reply_alert {
    int get_num_peers() const {
        return self->num_peers;
    }
}

%extend libtorrent::tracker_error_alert {
    int get_times_in_row() const {
        return self->times_in_row;
    }
}

// File completed alert
%extend libtorrent::file_completed_alert {
    int get_file_index() const {
        return static_cast<int>(self->index);
    }
}

// Piece finished alert
%extend libtorrent::piece_finished_alert {
    int get_piece_index() const {
        return static_cast<int>(self->piece_index);
    }
}

// Helper to cast alert to specific type
%inline %{
namespace libtorrent {
    // Alert type IDs for type switching
    const int ALERT_STATE_UPDATE = state_update_alert::alert_type;
    const int ALERT_TORRENT_REMOVED = torrent_removed_alert::alert_type;
    const int ALERT_TORRENT_DELETED = torrent_deleted_alert::alert_type;
    const int ALERT_ADD_TORRENT = add_torrent_alert::alert_type;
    const int ALERT_SAVE_RESUME_DATA = save_resume_data_alert::alert_type;
    const int ALERT_SAVE_RESUME_DATA_FAILED = save_resume_data_failed_alert::alert_type;
    const int ALERT_PIECE_FINISHED = piece_finished_alert::alert_type;
    const int ALERT_FILE_COMPLETED = file_completed_alert::alert_type;
    const int ALERT_TORRENT_FINISHED = torrent_finished_alert::alert_type;
    const int ALERT_TORRENT_ERROR = torrent_error_alert::alert_type;
    const int ALERT_TRACKER_REPLY = tracker_reply_alert::alert_type;
    const int ALERT_TRACKER_ERROR = tracker_error_alert::alert_type;
    const int ALERT_PEER_CONNECT = peer_connect_alert::alert_type;
    const int ALERT_PEER_DISCONNECTED = peer_disconnected_alert::alert_type;
    const int ALERT_TRACKER_WARNING = tracker_warning_alert::alert_type;
    const int ALERT_DHT_ERROR = dht_error_alert::alert_type;
    const int ALERT_EXTERNAL_IP = external_ip_alert::alert_type;
    const int ALERT_PERFORMANCE = performance_alert::alert_type;
}
%}
