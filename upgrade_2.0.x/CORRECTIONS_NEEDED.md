# Required Corrections for libtorrent 2.0.x API Accuracy

**Priority**: Critical/High issues must be fixed for production readiness

---

## CRITICAL ISSUES (Must Fix)

### Issue #1: Buffer Ownership Violation in disk_interface

**Severity**: CRITICAL  
**Location**: `/home/user/plugin.video.elementum/upgrade_2.0.x/libtorrent-go/memory_disk_io.hpp` lines 419-424

**Problem**:
```cpp
// Current (WRONG):
post(m_ioc, [handler, error, data, this]
{
    handler(disk_buffer_holder(*this,
        const_cast<char*>(data.data()),
        static_cast<int>(data.size())), error);
});
```

The `disk_buffer_holder` expects to own the buffer and will call `free_disk_buffer()` to clean it up. However:
- `data` points to memory in `memory_storage::m_file_data` map
- This memory is owned by `memory_storage`, not separately allocated
- `free_disk_buffer()` override does nothing (line 610-613)
- Violates libtorrent's memory contract

**Libtorrent's Contract**:
```cpp
disk_buffer_holder {
    ~disk_buffer_holder() {
        if (buffer) allocator.free_disk_buffer(buffer);
    }
};
```

**Fix Options**:

**Option A: Allocate Buffers Properly**
```cpp
// Allocate new buffer for the span data
char* allocated = new char[data.size()];
std::memcpy(allocated, data.data(), data.size());

post(m_ioc, [handler, error, allocated, size=data.size(), this]
{
    handler(disk_buffer_holder(*this, allocated, size), error);
});

// Update free_disk_buffer:
void free_disk_buffer(char* buf) override {
    if (buf) delete[] buf;
}
```

**Option B: Custom Buffer Wrapper (Better)**
```cpp
// Create wrapper that doesn't own buffer
class BorrowedBuffer {
    const char* data;
    int size;
    // No cleanup on destruction
};

// Return borrowed_buffer wrapper instead of disk_buffer_holder
// Requires SWIG/API change
```

**Option C: Document Limitation**
```cpp
// If memory budget allows, pre-allocate buffers
// and document that buffers are NOT freed
// (Only OK if memory is bounded)
```

**Recommendation**: Option A - Allocate copy buffers

---

### Issue #2: extensions.i File Reference

**Severity**: CRITICAL (Build Blocker)  
**Location**: `/home/user/plugin.video.elementum/upgrade_2.0.x/libtorrent-go/interfaces/session.i` line 105

**Problem**:
```swig
%include "extensions.i"  // <- File doesn't exist
```

This will cause SWIG compilation to fail if the file doesn't exist.

**Fix**:
Either create the file or remove the reference:

```swig
// OPTION 1: Remove (if extensions not needed)
// (DELETE line 105)

// OPTION 2: Create empty extensions.i
touch /home/user/plugin.video.elementum/upgrade_2.0.x/libtorrent-go/interfaces/extensions.i
# With content:
/*
 * extensions.i - Plugin extensions interface
 * Currently empty - extensions not exposed to Go
 */
```

**Recommendation**: Option 1 (remove reference) for now

---

### Issue #3: storage_index_t Not Exposed From add_torrent

**Severity**: HIGH (API Limitation)  
**Location**: `/home/user/plugin.video.elementum/upgrade_2.0.x/elementum/bittorrent/service_2.0.x.go` line 148

**Problem**:
```go
// Current code tries to do this:
storageIdx := s.Session.GetStorageIndex(infoHashV1)
```

**Reality**: libtorrent's `session::add_torrent()` doesn't return `storage_index_t`:
```cpp
// Official API
torrent_handle session::add_torrent(const add_torrent_params& p, error_code& ec);
// Returns torrent_handle, not storage_index_t
```

The storage_index_t is managed internally by disk_interface and NOT exposed.

**Impact**: 
- Lookbehind buffer access requires storage_index_t
- Current workaround (track by info_hash) is fragile with duplicate hashes

**Official Workaround**:
libtorrent doesn't provide a way to get storage_index_t from outside. Options:

**Fix Option A: Track in C++ Extension**
```cpp
// In disk_interface.i
%inline %{
namespace libtorrent {
    // Keep a map of handles to storage indices
    std::map<torrent_handle, storage_index_t> g_handle_to_index;
    std::mutex g_handle_index_mutex;
    
    storage_index_t register_torrent_handle(
        torrent_handle h, storage_index_t idx) 
    {
        std::lock_guard<std::mutex> lock(g_handle_index_mutex);
        g_handle_to_index[h] = idx;
        return idx;
    }
    
    storage_index_t get_storage_index(torrent_handle h) {
        std::lock_guard<std::mutex> lock(g_handle_index_mutex);
        auto it = g_handle_to_index.find(h);
        if (it != g_handle_to_index.end()) {
            return it->second;
        }
        return storage_index_t(-1);
    }
}
%}
```

**Fix Option B: Expose disk_interface from session**
```cpp
// In session.i - wrap disk_interface accessor
%extend libtorrent::session_handle {
    libtorrent::memory_disk_io* get_memory_disk_io() {
        // Get the actual disk_interface
        // (Requires session to expose it - may not be possible)
        return nullptr;  // Placeholder
    }
}
```

**Fix Option C: Batch Operation Method**
```cpp
// Instead of tracking by hash, use batch API
void register_all_torrents() {
    for each torrent handle h {
        storage_index_t idx = predict_next_index();
        h -> store mapping
    }
}
```

**Recommendation**: Use Option A - Track handles in map with mutex

---

## HIGH PRIORITY ISSUES

### Issue #4: storage_index_t Type Definition

**Severity**: HIGH  
**Location**: `/home/user/plugin.video.elementum/upgrade_2.0.x/libtorrent-go/interfaces/disk_interface.i` lines 14-18

**Problem**:
```cpp
// Current:
namespace libtorrent {
    struct storage_index_t {
        int value;
    };
}
```

This is wrong because:
1. storage_index_t should be opaque (hide implementation)
2. Exposing `value` field breaks encapsulation
3. Official API uses aux::vector indexing, not simple int struct

**Fix**:
```cpp
// CORRECTED:
namespace libtorrent {
    // DO NOT expose raw struct
    // Instead, provide helper functions only
}

// Remove the struct definition entirely
// Use only the conversion functions:
%inline %{
namespace libtorrent {
    // Create from int
    storage_index_t make_storage_index(int idx) {
        return storage_index_t(idx);
    }
    
    // Extract int value
    int get_storage_index_value(storage_index_t idx) {
        return static_cast<int>(idx);
    }
}
%}
```

This enforces that Go code can't treat storage_index_t as a plain int.

---

### Issue #5: Missing dht_state Field in session_params

**Severity**: HIGH (Data Loss Risk)  
**Location**: `/home/user/plugin.video.elementum/upgrade_2.0.x/libtorrent-go/interfaces/session_params.i`

**Problem**: 
session_params has optional `dht_state` field that can restore DHT state from previous session. Not exposed.

**Official API**:
```cpp
struct session_params {
    settings_pack settings;
    disk_io_constructor disk_io_constructor;
    std::vector<char> dht_state;  // Can be restored
    std::vector<std::shared_ptr<plugin>> extensions;
};
```

**Impact**: 
- DHT peer lists not preserved across restarts
- Cold start on each session
- Slower peer discovery

**Fix**:
```cpp
// Add to session_params.i
%extend libtorrent::session_params {
    // Save DHT state
    std::vector<char> get_dht_state() const {
        return self->dht_state;
    }
    
    // Restore DHT state
    void set_dht_state(std::vector<char> const& state) {
        self->dht_state = state;
    }
}
```

Also add save/load functions:
```cpp
// In session.i
namespace libtorrent {
    std::vector<char> read_dht_state(span<char const> buf);
    std::vector<char> write_dht_state(session const& ses);
}
```

---

### Issue #6: pop_alerts() SWIG Directive (FIXED)

**Severity**: HIGH (But Already Fixed)  
**Location**: `/home/user/plugin.video.elementum/upgrade_2.0.x/libtorrent-go/interfaces/session.i` lines 60-67

**Status**: ✅ FIXED in current code

Current code shows:
```swig
%extend libtorrent::session_handle {
    std::vector<libtorrent::alert*> pop_alerts() {
        std::vector<libtorrent::alert*> alerts;
        self->pop_alerts(&alerts);
        return alerts;
    }
}
// Note: Do NOT use %ignore for pop_alerts - we want the extended version
```

The previous critical evaluation document was incorrect - this has been fixed.

---

## MEDIUM PRIORITY ISSUES

### Issue #7: Missing v2 Merkle Tree Support

**Severity**: MEDIUM  
**Location**: Multiple files

**Problem**:
Official 2.0.x added:
```cpp
add_torrent_params::verified_leaf_hashes   // Vector of hash vectors
add_torrent_params::merkle_trees           // For v2 torrents
```

Removed:
```cpp
add_torrent_params::merkle_tree  // Old way
```

**Current Implementation**: Not wrapped - means v2 torrent resumption incomplete

**Fix** (Optional for now):
```cpp
// In add_torrent_params.i
%extend libtorrent::add_torrent_params {
    // Merkle tree methods for v2 torrents
    // (Complex - requires vector<vector<sha256_hash>>)
}
```

**Impact**: LOW (only needed if full v2 support required)

---

### Issue #8: Buffer Ownership Documentation

**Severity**: MEDIUM  
**Location**: `/home/user/plugin.video.elementum/upgrade_2.0.x/libtorrent-go/memory_disk_io.hpp`

**Problem**: No documentation about callback execution context

**Fix**: Add comments:
```cpp
// async_read() callback is posted to m_ioc thread pool
// Execution context: Not on session thread
// Thread safety: Callback receives const data span from memory_storage
// Lifetime: Buffer pointer only valid during callback execution
```

---

## VERIFICATION CHECKLIST

### Build Verification
- [ ] extensions.i reference removed or file created
- [ ] All %include directives in libtorrent.i resolve
- [ ] SWIG compilation completes without errors
- [ ] C++ compilation with all dependencies

### Unit Tests
- [ ] disk_interface::new_torrent/remove_torrent
- [ ] async_read with proper buffer cleanup
- [ ] async_write operation
- [ ] async_hash and async_hash2
- [ ] info_hash_t has_v1(), has_v2(), get_best()
- [ ] Alert types: state_update_alert, torrent_removed_alert
- [ ] Session creation with session_params
- [ ] Thread safety with concurrent operations

### Integration Tests  
- [ ] Add torrent via service_2.0.x.go
- [ ] Lookbehind buffer access
- [ ] Remove torrent cleanup
- [ ] Session state save/load
- [ ] Multiple sessions (if supported)

### API Compatibility  
- [ ] All removed APIs properly ignored
- [ ] parse_magnet_uri() used instead of url field
- [ ] write_session_params() used instead of save_state()
- [ ] settings in settings_pack, not dht_settings

---

## SUMMARY TABLE

| Issue | File | Line | Severity | Fix Time | Status |
|-------|------|------|----------|----------|--------|
| Buffer ownership | memory_disk_io.hpp | 419 | CRITICAL | 2-3 days | TO DO |
| extensions.i reference | session.i | 105 | CRITICAL | 1 hour | TO DO |
| storage_index_t tracking | service_2.0.x.go | 148 | HIGH | 2-3 days | TO DO |
| storage_index_t opaque type | disk_interface.i | 14 | HIGH | 1 day | TO DO |
| dht_state field | session_params.i | - | HIGH | 1-2 days | TO DO |
| pop_alerts directive | session.i | 60 | HIGH | FIXED | DONE |
| v2 merkle trees | add_torrent_params.i | - | MEDIUM | 3-4 days | OPTIONAL |
| Documentation | memory_disk_io.hpp | - | MEDIUM | 1 day | TO DO |

---

## EFFORT ESTIMATE

- **Critical Fixes**: 3-4 days (buffer ownership, storage_index_t, extensions.i)
- **High Priority**: 3-4 days (dht_state, type improvements)
- **Testing**: 2-3 days (verify all fixes work together)
- **Total**: 8-11 days of development work

---

## DEPLOYMENT GATES

**Alpha Testing Gates**:
- [ ] All CRITICAL issues fixed
- [ ] Build succeeds on all platforms
- [ ] Basic torrent add/remove works

**Beta Testing Gates**:
- [ ] All HIGH issues fixed
- [ ] Lookbehind buffer working
- [ ] Session state save/load working

**Production Gates**:
- [ ] MEDIUM issues addressed or documented
- [ ] Comprehensive testing on all 13 platforms
- [ ] Performance benchmarks acceptable
- [ ] Memory leak detection clean

---
