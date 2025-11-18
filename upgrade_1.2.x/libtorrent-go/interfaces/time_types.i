/*
 * time_types.i - SWIG interface for chrono time handling
 *
 * In libtorrent 1.2.x, time fields use std::chrono instead of int.
 * This interface provides conversion helpers for Go code.
 */

%{
#include <chrono>
#include <libtorrent/time.hpp>
%}

// Helper functions to convert chrono to int64
%inline %{
namespace libtorrent {
    // Convert chrono::seconds to int64
    std::int64_t seconds_to_int64(std::chrono::seconds s) {
        return static_cast<std::int64_t>(s.count());
    }

    // Convert chrono::milliseconds to int64
    std::int64_t milliseconds_to_int64(std::chrono::milliseconds ms) {
        return static_cast<std::int64_t>(ms.count());
    }
}
%}

// Extend torrent_status with int-based time getters
%extend libtorrent::torrent_status {
    // Get active time in seconds (int64)
    std::int64_t get_active_time_seconds() {
        return std::chrono::duration_cast<std::chrono::seconds>(
            self->active_duration
        ).count();
    }

    // Get finished time in seconds (int64)
    std::int64_t get_finished_time_seconds() {
        return std::chrono::duration_cast<std::chrono::seconds>(
            self->finished_duration
        ).count();
    }

    // Get seeding time in seconds (int64)
    std::int64_t get_seeding_time_seconds() {
        return std::chrono::duration_cast<std::chrono::seconds>(
            self->seeding_duration
        ).count();
    }

    // Backward compatible getters that return int
    int GetActiveTime() {
        return static_cast<int>(std::chrono::duration_cast<std::chrono::seconds>(
            self->active_duration
        ).count());
    }

    int GetFinishedTime() {
        return static_cast<int>(std::chrono::duration_cast<std::chrono::seconds>(
            self->finished_duration
        ).count());
    }

    int GetSeedingTime() {
        return static_cast<int>(std::chrono::duration_cast<std::chrono::seconds>(
            self->seeding_duration
        ).count());
    }
}
