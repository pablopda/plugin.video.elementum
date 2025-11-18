# QUICK FIX GUIDE - SWIG Interface Errors

## Critical Issues - MUST FIX

### 1. Delete Duplicate Code (session_params.i)
**File**: `interfaces/session_params.i`  
**Lines 38-43**: DELETE this entire block

```swig
%extend libtorrent::session {
    // Create session with params (2.0.x way)
    static libtorrent::session* create_with_params(libtorrent::session_params params) {
        return new libtorrent::session(std::move(params));
    }
}
```

**Reason**: Same method already defined in session.i (lines 42-48). SWIG compilation will fail with duplicate method error.

---

### 2. Fix session.i Directive Ordering
**File**: `interfaces/session.i`

#### Step A: Delete line 105
```swig
%include "extensions.i"  // <- DELETE THIS LINE
```

#### Step B: Move lines 106-116
Move these lines to immediately after line 25 (after the `%{...%}` block):

```swig
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
```

**Reason**: %include must come before %extend blocks.

---

### 3. Fix Namespace References (info_hash.i)
**File**: `interfaces/info_hash.i`  
**Lines**: 22, 27, 42, 52, 55, 68, 76

Replace all: `lt::aux::` → `libtorrent::aux::`

**Example**:
```cpp
// BEFORE
return lt::aux::to_hex(self->v1);

// AFTER
return libtorrent::aux::to_hex(self->v1);
```

**Reason**: Undefined namespace alias `lt` - C++ compiler won't recognize it.

---

### 4. Fix %ignore Ordering (info_hash.i)
**File**: `interfaces/info_hash.i`

**Move lines 85-88** to immediately after line 16:

```swig
%include <libtorrent/info_hash.hpp>

%ignore libtorrent::add_torrent_params::info_hash;
%ignore libtorrent::torrent_status::info_hash;
%ignore libtorrent::torrent_handle::info_hash;

%extend libtorrent::info_hash_t {
    // ... rest of file
```

**Reason**: %ignore must precede %extend blocks to ensure proper method visibility.

---

## Supporting Fixes - SHOULD DO

### 5. Consolidate %include (add_torrent_params.i)
Group all %include directives after %{ %} block instead of scattering them throughout.

### 6. Fix %feature Placement (torrent_handle.i)
Move lines 153-155 to before line 21 (before any %include directives).

### 7. Clean Up (extensions.i)
DELETE this file - it's empty and included unnecessarily.

---

## Verification Command

```bash
cd /home/user/plugin.video.elementum/upgrade_2.0.x/libtorrent-go/
swig -go -cgo -module libtorrent -I. -outdir . libtorrent.i
```

**Expected Result**: No errors, no SWIG warnings

---

## Error Messages You May Have Seen

- `Error: Duplicate declaration of method create_with_params` → Fix #1
- `Error: Unknown directive placement` → Fix #2  
- `Error: Undefined namespace 'lt'` → Fix #3
- `Error: Method visibility issue` → Fix #4

