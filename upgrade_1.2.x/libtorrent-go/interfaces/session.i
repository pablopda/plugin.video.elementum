/*
 * session.i - SWIG interface for libtorrent 1.2.x
 *
 * Key changes from 1.1.x:
 * - Some deprecated functions removed
 * - Settings unified into settings_pack
 */

%{
#include <libtorrent/io_service.hpp>
#include <libtorrent/ip_filter.hpp>
#include <libtorrent/kademlia/dht_storage.hpp>
#include <libtorrent/bandwidth_limit.hpp>
#include <libtorrent/peer_class.hpp>
#include <libtorrent/peer_class_type_filter.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/session_stats.hpp>
#include <libtorrent/session_handle.hpp>
%}

%feature("director") session_handle;

// These are problematic, so we ignore them.
%ignore libtorrent::session_handle::add_extension;
%ignore libtorrent::session_handle::dht_put_item;

// Deprecated in 1.2.x - use settings_pack instead
%ignore libtorrent::session_settings;

%template(stdVectorAlerts) std::vector<libtorrent::alert*>;

%extend libtorrent::session {
    libtorrent::session_handle* get_handle() {
        return self;
    }
}

%extend libtorrent::session_handle {
    std::vector<libtorrent::alert*> pop_alerts() {
        std::vector<libtorrent::alert*> alerts;
        self->pop_alerts(&alerts);
        return alerts;
    }
}
%ignore libtorrent::session_handle::pop_alerts;

%include "extensions.i"
%include <libtorrent/io_service.hpp>
%include <libtorrent/ip_filter.hpp>
%include <libtorrent/kademlia/dht_storage.hpp>
%include <libtorrent/bandwidth_limit.hpp>
%include <libtorrent/peer_class.hpp>
%include <libtorrent/peer_class_type_filter.hpp>
%include <libtorrent/settings_pack.hpp>
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

    // Helper to check if setting exists (useful for deprecated settings)
    bool has_setting(std::string const& name) const {
        return libtorrent::setting_by_name(name) >= 0;
    }
}
