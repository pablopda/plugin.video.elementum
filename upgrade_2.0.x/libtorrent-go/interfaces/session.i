/*
 * session.i - SWIG interface for libtorrent 2.0.x session
 *
 * Key changes from 1.2.x:
 * - Session created with session_params
 * - Deprecated: load_state/save_state -> read_session_params/write_session_params
 * - io_service renamed to io_context
 * - stats_alert deprecated -> use post_torrent_updates()
 * - dht_settings merged into settings_pack
 */

%{
#include <libtorrent/io_context.hpp>
#include <libtorrent/ip_filter.hpp>
#include <libtorrent/kademlia/dht_storage.hpp>
#include <libtorrent/bandwidth_limit.hpp>
#include <libtorrent/peer_class.hpp>
#include <libtorrent/peer_class_type_filter.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/session_params.hpp>
#include <libtorrent/session_stats.hpp>
#include <libtorrent/session_handle.hpp>
#include "memory_disk_io.hpp"
%}

%feature("director") session_handle;

// Ignore problematic methods
%ignore libtorrent::session_handle::add_extension;
%ignore libtorrent::session_handle::dht_put_item;

// Deprecated in 2.0.x
%ignore libtorrent::session_settings;
%ignore libtorrent::session_handle::load_state;
%ignore libtorrent::session_handle::save_state;
%ignore libtorrent::dht_settings;

%template(stdVectorAlerts) std::vector<libtorrent::alert*>;

// Session creation with session_params (2.0.x way)
%extend libtorrent::session {
    // Create session with params
    static libtorrent::session* create_with_params(libtorrent::session_params params) {
        // Store disk_io reference for lookbehind access
        auto* sess = new libtorrent::session(std::move(params));
        return sess;
    }

    libtorrent::session_handle* get_handle() {
        return self;
    }

    // Get session state for saving
    libtorrent::session_params get_session_state() const {
        return self->session_state();
    }
}

%extend libtorrent::session_handle {
    std::vector<libtorrent::alert*> pop_alerts() {
        std::vector<libtorrent::alert*> alerts;
        self->pop_alerts(&alerts);
        return alerts;
    }
}
// Note: Do NOT use %ignore for pop_alerts - we want the extended version

// Session params extensions
%extend libtorrent::session_params {
    // Configure memory disk I/O
    void set_memory_disk_io(std::int64_t memory_size) {
        libtorrent::memory_disk_memory_size = memory_size;
        self->disk_io_constructor = [](libtorrent::io_context& ioc,
            libtorrent::settings_interface const& si, libtorrent::counters& cnt)
        {
            auto dio = std::make_unique<libtorrent::memory_disk_io>(ioc);
            // Use thread-safe setter for global pointer
            libtorrent::set_global_memory_disk_io(dio.get());
            return dio;
        };
    }

    // Set settings pack
    void set_settings(libtorrent::settings_pack const& settings) {
        self->settings = settings;
    }

    // Get settings pack
    libtorrent::settings_pack& get_settings() {
        return self->settings;
    }
}

// Session state save/load functions (2.0.x way)
namespace libtorrent {
    session_params read_session_params(span<char const> buf,
        save_state_flags_t flags = save_state_flags_t::all());
    std::vector<char> write_session_params(session_params const& sp,
        save_state_flags_t flags = save_state_flags_t::all());
    std::vector<char> write_session_params_buf(session_params const& sp,
        save_state_flags_t flags = save_state_flags_t::all());
}

%include "extensions.i"
%include <libtorrent/io_context.hpp>
%include <libtorrent/ip_filter.hpp>
%include <libtorrent/kademlia/dht_storage.hpp>
%include <libtorrent/bandwidth_limit.hpp>
%include <libtorrent/peer_class.hpp>
%include <libtorrent/peer_class_type_filter.hpp>
%include <libtorrent/settings_pack.hpp>
%include <libtorrent/session_params.hpp>
%include <libtorrent/session.hpp>
%include <libtorrent/session_stats.hpp>
%include <libtorrent/session_handle.hpp>

%extend libtorrent::settings_pack {
    void set_bool(std::string const& name, bool val) {
        int setting = libtorrent::setting_by_name(name);
        if (setting >= 0) {
            $self->set_bool(setting, val);
        }
    }

    void set_int(std::string const& name, int val) {
        int setting = libtorrent::setting_by_name(name);
        if (setting >= 0) {
            $self->set_int(setting, val);
        }
    }

    void set_str(std::string const& name, std::string const& val) {
        int setting = libtorrent::setting_by_name(name);
        if (setting >= 0) {
            $self->set_str(setting, val);
        }
    }

    bool get_bool(std::string const& name) const {
        int setting = libtorrent::setting_by_name(name);
        if (setting >= 0) {
            return $self->get_bool(setting);
        }
        return false;
    }

    int get_int(std::string const& name) const {
        int setting = libtorrent::setting_by_name(name);
        if (setting >= 0) {
            return $self->get_int(setting);
        }
        return 0;
    }

    std::string get_str(std::string const& name) const {
        int setting = libtorrent::setting_by_name(name);
        if (setting >= 0) {
            return $self->get_str(setting);
        }
        return "";
    }

    bool has_setting(std::string const& name) const {
        return libtorrent::setting_by_name(name) >= 0;
    }
}
