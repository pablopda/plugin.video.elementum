# Critical Evaluation: libtorrent 2.0.x Upgrade Implementation
## Elementum Plugin - Comprehensive Security & Correctness Review

**Date**: 2025-11-18
**Scope**: /home/user/plugin.video.elementum/upgrade_2.0.x/
**Recommendation**: NOT PRODUCTION-READY - Multiple critical issues must be resolved

---

## CRITICAL ISSUES (Must Fix Before Deployment)

### 1. THREAD SAFETY: Unsafe Global Pointer Pattern
**Severity**: CRITICAL
**Location**: `libtorrent-go/interfaces/disk_interface.i` (lines 25-64)
**File**: `libtorrent-go/memory_disk_io.hpp` (referenced)

**Issue**:
```cpp
namespace libtorrent {
    memory_disk_io* g_memory_disk_io = nullptr;  // DANGEROUS GLOBAL
    
    void memory_disk_set_lookbehind(int storage_index, ...) {
        if (g_memory_disk_io) {
            g_memory_disk_io->set_lookbehind_pieces(...);
        }
    }
}
```

**Problems**:
- Raw global pointer with NO synchronization
- NOT thread-safe for multiple sessions
- Dangling pointer if session is destroyed while lookbehind operations pending
- In session.i line 78: `libtorrent::g_memory_disk_io = dio.get();` stores raw pointer from unique_ptr
- Multiple sessions will overwrite the same global pointer
- Go goroutines can race on this pointer access

**Risk**: Data corruption, crashes, undefined behavior in production

**Fix Required**:
- Use thread-local storage (thread_local) if single-session per thread
- OR use a map: `std::map<storage_index_t, memory_disk_io*>` with mutex
- OR store pointer in Session wrapper instead of global
- Add atomic compare-and-swap for safe updates
- Add synchronization primitives

---

### 2. SWIG INTERFACE LOGIC ERROR: pop_alerts Extend Then Ignore
**Severity**: CRITICAL
**Location**: `libtorrent-go/interfaces/session.i` (lines 60-67)

**Issue**:
```swig
%extend libtorrent::session_handle {
    std::vector<libtorrent::alert*> pop_alerts() {
        std::vector<libtorrent::alert*> alerts;
        self->pop_alerts(&alerts);
        return alerts;
    }
}
%ignore libtorrent::session_handle::pop_alerts;  // <- THIS CANCELS THE EXTEND!
```

**Problem**: 
- `%ignore` directive AFTER `%extend` will prevent the extension from being wrapped
- The extend is completely wasted
- SWIG processes directives top-to-bottom, and ignore takes precedence
- Result: Go code cannot call pop_alerts at all

**Impact**: Alert handling is broken - Go code has NO WAY to get alerts from session

**Fix Required**:
- Remove the `%ignore` directive entirely (it's not needed since we're extending)
- OR place `%ignore` BEFORE any usage
- Test that alerts actually get returned to Go

---

### 3. MISSING MAIN LIBTORRENT.I HEADER FILE
**Severity**: CRITICAL
**Location**: `libtorrent-go/` directory

**Issue**:
- No main `libtorrent.i` file exists to tie together all sub-interfaces
- Individual interface files include each other in unspecified order
- SWIG build will fail without main entry point
- Dependencies between interfaces are not clearly expressed

**Missing Interfaces**:
- No `alerts.i` for alert type definitions
- No `torrent_info.i` (partially covered in torrent_handle.i)
- No main wrapper file to specify include order

**Fix Required**:
Create `libtorrent.i` in proper dependency order:
```swig
// libtorrent.i
%module libtorrent
%{
    #include "memory_disk_io.hpp"
%}

// Dependency order matters!
%include "info_hash.i"        // Base types first
%include "session_params.i"   // Then params
%include "disk_interface.i"   // Then disk I/O
%include "session.i"          // Then session (depends on disk_interface)
%include "torrent_handle.i"   // Then handles
%include "add_torrent_params.i" // Then torrent creation
// ... other interfaces
```

---

### 4. MISSING "extensions.i" FILE
**Severity**: CRITICAL
**Location**: `libtorrent-go/interfaces/session.i` (line 104)

**Issue**:
```swig
%include "extensions.i"  // <- FILE DOESN'T EXIST
```

**Problem**:
- SWIG will fail to compile
- This file is expected to define extensions but missing
- No fallback or error handling

**Fix Required**:
- Either create extensions.i with required definitions
- Or remove the include if it's not actually needed

---

### 5. MALFORMED SWIG INCLUDE DIRECTIVES
**Severity**: HIGH
**Location**: `libtorrent-go/interfaces/torrent_handle.i` (lines 15, 161)

**Issue**:
```swig
%{
#include <libtorrent/torrent_info.hpp>
...
#include <libtorrent/torrent.hpp>      // CORRECT - inside %{ %}
%}

// ... later at line 161
#include <libtorrent/torrent.hpp>      // WRONG - outside %{ %}, should be %include
```

**Problem**:
- Line 161 uses `#include` instead of `%include`
- This won't be processed by SWIG correctly
- Likely compiler error or incomplete wrapping

**Fix Required**:
Change line 161 to:
```swig
%include <libtorrent/torrent.hpp>
```

---

## IMPORTANT GAPS (Should Be Addressed)

### 6. MISSING ALERT TYPE DEFINITIONS AND HANDLERS
**Severity**: HIGH
**Location**: No alerts.i file exists

**Issue**:
- No SWIG wrapping for alert types from 2.0.x
- torrent_removed_alert, state_update_alert, etc. not wrapped
- torrent_status changes for info_hashes not documented
- No templates for alert vector iteration

**Required Types**:
```cpp
// These need SWIG wrapping:
- state_update_alert (replaces stats_alert)
- torrent_removed_alert (has info_hashes field, not info_hash)
- torrent_delete_failed_alert
- peer_connect_alert (uses socket_type_t enum)
- listen_failed_alert (uses socket_type_t enum)
// ... and all others that use info_hashes
```

**Recommendation**:
Create `alerts.i` with:
- %template directives for std::vector<alert*>
- %extend for each alert subclass
- Helper methods to cast alerts safely
- Documentation of 2.0.x alert changes

---

### 7. INCOMPLETE TYPE CONVERSION COVERAGE
**Severity**: HIGH
**Location**: Multiple SWIG interfaces

**Missing Strong Type Mappings**:
- `piece_index_t` - Only wrapped via SetPiecePriorityInt/PiecePriorityInt
- `file_index_t` - Only wrapped via SetFilePriorityInt/FilePriorityInt
- `download_priority_t` - Cast to int, not properly typed
- `move_flags_t` - Not wrapped
- `remove_flags_t` - Not wrapped
- `disk_job_flags_t` - Not wrapped
- `save_state_flags_t` - Only partially in function signature
- `operation_t` enum in storage_error - Not mapped
- `status_t` enum - Not mapped

**Impact**:
- Go code uses raw int which is error-prone
- Type safety lost at language boundary
- No validation of priority values

**Recommendation**:
Create type wrapper Go structs with validation:
```go
type PieceIndex int
type FileIndex int
type Priority int
const (
    PriorityDontDownload Priority = 0
    PriorityNormal       Priority = 4
    PriorityHigh         Priority = 7
)
```

---

### 8. MEMORY MANAGEMENT: Buffer Ownership Unclear
**Severity**: HIGH
**Location**: `libtorrent-go/memory_disk_io.hpp` (lines 419-424)

**Issue**:
```cpp
void async_read(...) override {
    // ... read data
    post(m_ioc, [handler, error, data, this]
    {
        handler(disk_buffer_holder(*this,
            const_cast<char*>(data.data()),
            static_cast<int>(data.size())), error);
    });
}
```

**Problems**:
- `data` is `span<char const>` pointing to memory in `memory_storage`
- disk_buffer_holder takes ownership of buffer
- But memory is still owned by memory_storage
- free_disk_buffer override does nothing: `void free_disk_buffer(char*) override {}`
- When disk_buffer_holder goes out of scope, tries to free non-owned memory
- Potential use-after-free or double-free

**Recommendation**:
- Implement proper free_disk_buffer that tracks allocated buffers
- OR use custom buffer wrapper that knows memory is borrowed
- Document buffer lifetime clearly
- Consider if const_cast is actually safe here

---

### 9. ASYNC CALLBACK SAFETY WITH GO GOROUTINES
**Severity**: HIGH
**Location**: `libtorrent-go/memory_disk_io.hpp` (all async methods)

**Issue**:
```cpp
post(m_ioc, [handler, error, data, this]  // handler is std::function<>
{
    handler(...);  // Called from io_context thread
});
```

**Problems**:
- Callbacks are invoked from io_context thread pool
- Go callbacks (`std::function<>` wrapping Go) not thread-safe
- Go runtime may not be running those threads
- CGO marshaling overhead on thread pool threads
- Potential deadlocks if Go code tries to call back into libtorrent

**Recommendation**:
- Document that callbacks happen off-session thread
- Add synchronization for Go callback invocation
- Consider if cgo/mutex protection is needed
- Test with race detector enabled

---

### 10. SESSION PARAMS EXTENSION DOESN'T PERSIST
**Severity**: MEDIUM
**Location**: `libtorrent-go/interfaces/session_params.i` (lines 19-24)

**Issue**:
```cpp
%extend libtorrent::session_params {
    void set_memory_disk_io(std::int64_t memory_size) {
        libtorrent::memory_disk_memory_size = memory_size;  // GLOBAL!
        self->disk_io_constructor = libtorrent::memory_disk_constructor;
    }
}
```

**Problems**:
- Uses global `memory_disk_memory_size` variable
- Multiple sessions will interfere with each other
- No per-session configuration of memory limits
- Memory size is global but applied per-torrent in memory_storage

**Better Approach**:
- Store memory limit in session_params context
- Pass through disk_io_constructor
- Or use thread-local storage

---

### 11. STORAGE INDEX TRACKING NOT EXPOSED TO GO
**Severity**: HIGH
**Location**: `elementum/bittorrent/service_2.0.x.go` (line 148)

**Issue**:
```go
// Get storage index (HOW?)
storageIdx := s.Session.GetStorageIndex(infoHashV1)
```

**Problem**:
- Session.AddTorrent needs to return BOTH torrent_handle AND storage_index_t
- Current SWIG wrappers don't expose storage_index_t from add_torrent
- Go code has no way to get storage index for a torrent
- Lookbehind access requires storage index
- Code calls GetStorageIndex which likely returns -1 (invalid)

**Current API Signature Missing**:
```cpp
// In add_torrent_params.i - MISSING:
%extend libtorrent::session_handle {
    std::pair<libtorrent::torrent_handle, libtorrent::storage_index_t> 
    add_torrent_with_index(libtorrent::add_torrent_params const& p,
                           libtorrent::error_code& ec) {
        return {self->add_torrent(p, ec), ???};  // Can't get index!
    }
}
```

**Problem**: libtorrent::session doesn't expose storage_index_t from add_torrent

**Workaround in Code**:
- Store storage indices in a map after add_torrent
- Track by info_hash_v1
- This is fragile - multiple torrents with same hash will fail

---

### 12. MISSING SWIG %TYPEMAP DIRECTIVES
**Severity**: MEDIUM
**Location**: All SWIG interfaces

**Missing Type Mappings**:
- `std::string` to/from Go string (usually automatic)
- `std::vector<int>` to/from Go []int (for lookbehind pieces)
- `span<>` types - No automatic conversion for Go
- `std::function<>` - Callbacks not automatically marshaled
- `error_code&` out parameter pattern - Needs %typemap
- `storage_error` structure - Needs proper marshaling
- `sha1_hash`, `sha256_hash` - Should have string conversions

**Example of Missing Mapping**:
```swig
// MISSING: how does Go pass []int to C++?
void memory_disk_set_lookbehind(int storage_index, std::vector<int> const& pieces)

// NEEDED:
%typemap(gotype) std::vector<int> const& "[]int"
%typemap(in) std::vector<int> const& {
    // Convert Go []int to std::vector<int>
}
```

---

## PRODUCTION READINESS ASSESSMENT

### Current State: **NOT PRODUCTION READY**

**Blocking Issues** (must fix):
1. ✗ Unsafe global pointer (g_memory_disk_io)
2. ✗ pop_alerts method disabled by ignore directive
3. ✗ Missing libtorrent.i main header
4. ✗ Missing extensions.i file
5. ✗ Malformed include directives
6. ✗ No storage_index_t exposure to Go
7. ✗ Buffer ownership/lifetime unclear

**Incomplete Features** (should fix):
1. ✗ Alert type wrapping (no alerts.i)
2. ✗ Strong type mappings
3. ✗ Session state save/load for multiple sessions
4. ✗ Proper memory configuration per-session
5. ✗ Thread safety documentation

**Risk Assessment**:
- **Data Loss**: Possible (buffer corruption, pointer issues)
- **Crashes**: Likely (dangling pointers, memory access)
- **Hangs**: Possible (thread safety issues)
- **Corruption**: Likely (unsynchronized global state)

---

## REQUIRED FIXES BEFORE DEPLOYMENT

### Fix #1: Thread-Safe Global Pointer (Priority: CRITICAL)

Replace unsafe global pattern in `disk_interface.i`:

```cpp
// REPLACE THIS:
namespace libtorrent {
    memory_disk_io* g_memory_disk_io = nullptr;
}

// WITH THIS (if single-session guarantee):
// Store in Session wrapper class with proper lifetime
class Session {
    memory_disk_io* disk_io_ = nullptr;  // Owned by disk_interface
    // ...
};

// OR use thread-local for session-per-thread pattern:
thread_local memory_disk_io* g_memory_disk_io_tl = nullptr;

// AND update lookbehind functions:
void memory_disk_set_lookbehind(...) {
    if (thread_local_disk_io) {
        thread_local_disk_io->...
    }
}
```

---

### Fix #2: Fix pop_alerts SWIG Directive

Remove the conflicting ignore directive:

```swig
// FROM session.i - CORRECT ORDER:
%extend libtorrent::session_handle {
    std::vector<libtorrent::alert*> pop_alerts() {
        std::vector<libtorrent::alert*> alerts;
        self->pop_alerts(&alerts);
        return alerts;
    }
}
// NO %ignore DIRECTIVE - remove line 67
```

---

### Fix #3: Create Main libtorrent.i

Create `/home/user/plugin.video.elementum/upgrade_2.0.x/libtorrent-go/libtorrent.i`:

```swig
%module libtorrent

%include <typemaps.i>
%include <std_vector.i>
%include <std_string.i>
%include <std_map.i>

%{
#include "memory_disk_io.hpp"
#include <libtorrent/session.hpp>
#include <libtorrent/session_params.hpp>
%}

// Correct dependency order
%include "interfaces/info_hash.i"
%include "interfaces/disk_interface.i"
%include "interfaces/session_params.i"
%include "interfaces/session.i"
%include "interfaces/add_torrent_params.i"
%include "interfaces/torrent_handle.i"
```

---

### Fix #4: Create extensions.i or Remove Reference

Either create the file or remove the include from session.i line 104.

---

### Fix #5: Add Storage Index Exposure

Update `session.i` to expose storage_index_t:

```cpp
%extend libtorrent::session_handle {
    // Wrapper that returns both handle and storage index
    // NOTE: libtorrent doesn't expose storage_index_t from add_torrent
    // Workaround: track in Go wrapper after add_torrent succeeds
    
    // Or add helper to query storage index by info hash
    int get_storage_index_for_info_hash(std::string const& v1_hex) const {
        // Implementation would need to search through torrents
        // This is NOT a standard libtorrent API
        return -1;  // Not available
    }
}
```

---

## ADDITIONAL RECOMMENDATIONS

### Security Hardening
1. Add mutex protection to g_memory_disk_io access
2. Add validation for storage_index_t range
3. Add bounds checking in lookbehind piece arrays
4. Sanitize error messages before sending to Go

### Documentation
1. Document thread safety guarantees
2. Document buffer lifetime and ownership
3. Document callback execution context (thread pool)
4. Document limitations vs. 1.2.x implementation
5. Add examples of correct Go usage patterns

### Testing
1. Unit tests for g_memory_disk_io thread safety
2. Benchmark async callback overhead
3. Test session creation/destruction with lookbehind
4. Test multiple sessions (verify they don't interfere)
5. Memory leak detection (valgrind/ASAN)
6. Race detector: `go test -race`

### CGO Integration
1. Test callback invocation from different threads
2. Verify Go runtime is accessible from io_context thread
3. Profile callback marshaling overhead
4. Consider if separate thread pool needed for callbacks

---

## CODE SAMPLE FIXES

### Fix for Global Pointer Thread Safety

**File**: `libtorrent-go/interfaces/disk_interface.i`

```cpp
// OLD (UNSAFE):
%inline %{
namespace libtorrent {
    memory_disk_io* g_memory_disk_io = nullptr;
    void memory_disk_set_lookbehind(...) {
        if (g_memory_disk_io) { ... }
    }
}
%}

// NEW (SAFE):
%inline %{
namespace libtorrent {
    thread_local memory_disk_io* g_memory_disk_io_tl = nullptr;
    std::mutex g_memory_disk_io_mutex;
    memory_disk_io* g_memory_disk_io_ptr = nullptr;
    
    void memory_disk_set_lookbehind_global(
        int storage_index, 
        std::vector<int> const& pieces) 
    {
        std::lock_guard<std::mutex> lock(g_memory_disk_io_mutex);
        if (g_memory_disk_io_ptr) {
            g_memory_disk_io_ptr->set_lookbehind_pieces(
                storage_index_t(storage_index), pieces);
        }
    }
    
    void set_global_memory_disk_io(memory_disk_io* dio) {
        std::lock_guard<std::mutex> lock(g_memory_disk_io_mutex);
        g_memory_disk_io_ptr = dio;
    }
}
%}
```

---

## SUMMARY TABLE

| Issue | Severity | Type | Status |
|-------|----------|------|--------|
| Global pointer race | CRITICAL | Thread safety | Must fix |
| pop_alerts ignore | CRITICAL | SWIG logic | Must fix |
| Missing main .i | CRITICAL | Build | Must fix |
| Missing extensions.i | CRITICAL | Build | Must fix |
| Storage index exposure | CRITICAL | API | Must fix |
| Malformed includes | HIGH | SWIG | Must fix |
| Alert types | HIGH | Feature | Should fix |
| Buffer ownership | HIGH | Memory | Should fix |
| Type mappings | HIGH | Safety | Should fix |
| Session memory config | MEDIUM | Feature | Nice to have |

---

## DEPLOYMENT TIMELINE

**Before Alpha Testing**: Fix all CRITICAL items
**Before Beta Testing**: Fix all HIGH items
**Before Production**: Complete all IMPORTANT gaps

**Estimated effort for fixes**: 2-3 weeks of development + 1-2 weeks testing

---

