# Upgrade Implementation Evaluation - Gaps and Missing Items

## Critical Issues Found

### 1. storage_interface Constructor Signature (CRITICAL)

**Issue**: Our memory_storage constructor may not match the 1.2.x signature.

**Current implementation**:
```cpp
memory_storage(storage_params const& params, file_pool& pool)
    : storage_interface(params.files)
```

**Potential problem**: In libtorrent 1.2.x, the storage_interface was significantly refactored. The disk I/O subsystem changed and storage_interface may no longer be the correct base class.

**Investigation needed**:
- Verify if `storage_interface` still exists in 1.2.x
- Check if it's replaced by `disk_interface` or `storage_holder`
- Verify constructor parameters match

**Risk Level**: HIGH - Build failure likely

---

### 2. download_priority_t Type Safety (HIGH)

**Issue**: Piece and file priorities use strongly typed enums in 1.2.x.

**Affected code in Elementum**:
```go
// torrent.go:503, 507
t.th.PiecePriority(curPiece, 3)

// torrent.go:1046
t.th.FilePriority(f.Index, priority)

// torrent.go:2204
pr := t.th.PiecePriority(i).(int)
```

**1.2.x change**: Priority values are now `download_priority_t`:
- `dont_download` = 0
- `low_priority` = 1
- `default_priority` = 4
- `top_priority` = 7

**Fix needed**:
1. Update SWIG interface to handle type conversion
2. Or update all Elementum calls to use typed constants

**Risk Level**: HIGH - Runtime errors possible

---

### 3. Time Field Type Changes (MEDIUM-HIGH)

**Issue**: torrent_status time fields changed from relative seconds to chrono types.

**Affected code**:
```go
// api/torrents.go:380-385
finishedTime := float64(torrentStatus.GetFinishedTime())
downloadTime := float64(torrentStatus.GetActiveTime()) - finishedTime
seedingTime := time.Duration(torrentStatus.GetSeedingTime()) * time.Second
```

**1.2.x change**: These now return `std::chrono::seconds` instead of `int`.

**Fix needed**: Update SWIG interface to convert chrono to int, or update Go code.

**Risk Level**: MEDIUM-HIGH - Type mismatch

---

### 4. open_mode_t Parameter (MEDIUM)

**Issue**: Our readv/writev use `open_mode_t` but may not define it correctly.

**Current implementation**:
```cpp
int readv(span<iovec_t const> bufs, piece_index_t piece, int offset,
          open_mode_t mode, storage_error& ec) override
```

**Investigation needed**: Verify `open_mode_t` is included and defined properly.

**Risk Level**: MEDIUM - Compilation error

---

### 5. storage_params Changes (MEDIUM)

**Issue**: The `storage_params` struct changed between versions.

**Current usage**:
```cpp
m_files = &params.files;
m_info = params.info;
```

**1.2.x changes**:
- `params.files` is now a reference not pointer
- `params.info` may have changed
- May need `params.mapped_files` for renamed files

**Fix needed**: Verify exact structure members in 1.2.x.

**Risk Level**: MEDIUM - Compilation errors

---

### 6. restore_piece Implementation (MEDIUM)

**Issue**: Our restore_piece uses internal torrent APIs that may have changed.

**Current implementation**:
```cpp
void restore_piece(int pi) {
    piece_index_t piece_idx(pi);
    t->reset_piece_deadline(piece_idx);
    t->picker().set_piece_priority(piece_idx, dont_download);
    t->picker().we_dont_have(piece_idx);
}
```

**Concerns**:
- `dont_download` constant name - is it correct for 1.2.x?
- `picker()` access may have changed
- `reset_piece_deadline` may have different signature

**Risk Level**: MEDIUM - Runtime errors

---

### 7. announce_entry Changes (LOW-MEDIUM)

**Issue**: The announce_entry struct may have changed.

**Current usage in Elementum**:
```go
announceEntry := lt.NewAnnounceEntry(tracker)
th.AddTracker(announceEntry)
```

**1.2.x changes**:
- Constructor may take different parameters
- May need tier specification

**Risk Level**: LOW-MEDIUM - Functionality may not work

---

### 8. Missing verify_resume_data Signature Update (MEDIUM)

**Issue**: We updated verify_resume_data but the signature is complex.

**Current implementation**:
```cpp
bool verify_resume_data(add_torrent_params const& rd,
                        aux::vector<std::string, file_index_t> const& links,
                        storage_error& ec) override
```

**Concern**: The `aux::vector` type and exact signature needs verification.

**Risk Level**: MEDIUM - Compilation error

---

## Additional Features Needing Updates

### 1. Session Status Deprecation

**Issue**: `session_status` is deprecated in 1.2.x.

**Replacement**: Use `session_stats_alert` with counter indices.

**Impact**: Any code querying session-level statistics needs updating.

---

### 2. DHT Settings Migration

**Issue**: DHT settings moved to main settings_pack.

**Old (1.1.x)**:
```cpp
dht::dht_settings dht;
dht.max_peers_reply = 100;
session.set_dht_settings(dht);
```

**New (1.2.x)**:
```cpp
settings.set_int("dht_max_peers_reply", 100);
```

**Impact**: Any DHT configuration code needs review.

---

### 3. IP Filter Changes

**Issue**: IP filter API may have subtle changes.

**Investigation needed**: Verify `ip_filter` class usage.

---

### 4. Peer Class Changes

**Issue**: Peer class API was updated.

**Impact**: Any bandwidth limiting by peer class needs review.

---

### 5. Extension Plugin Registration

**Issue**: Extension/plugin registration may have changed.

**Current commented code**:
```go
// s.Session.AddUploadExtension()
```

**Impact**: Custom extensions need verification.

---

## SWIG Interface Gaps

### 1. Missing span<> Support

**Issue**: Need proper SWIG typemaps for `span<>`.

**Fix**: Add to interfaces:
```cpp
%include <std_span.i>
// Or custom typemaps
```

---

### 2. Type-Safe Index Wrappers

**Issue**: `piece_index_t`, `file_index_t` need proper wrapping.

**Fix**: Add template instantiations and conversion helpers.

---

### 3. chrono Duration Conversions

**Issue**: `std::chrono::seconds` needs conversion to Go time.

**Fix**: Add typemaps or wrapper functions.

---

## Memory Storage Specific Gaps

### 1. is_readered() Using Deprecated Check

**Current implementation**:
```cpp
bool is_readered(int index) {
    return m_handle->piece_priority(piece_index_t(index)) != dont_download;
}
```

**Issue**: May need to use proper priority type comparison.

---

### 2. Missing async Operations

**Issue**: 1.2.x disk I/O is more async-focused.

**Methods we don't implement**:
- `async_read`
- `async_write`
- `async_hash`
- `async_move_storage`

**Impact**: May affect performance or cause issues.

---

### 3. settings_interface Usage

**Issue**: Storage may need to implement additional interface methods.

**Check**: Verify all pure virtual methods are implemented.

---

## Recommended Fixes Priority

### Immediate (Before Build)

1. **Verify storage_interface signature** - Check 1.2.x headers
2. **Add download_priority_t handling** - SWIG typemaps
3. **Fix open_mode_t include** - Add proper header
4. **Verify storage_params members** - Match 1.2.x structure

### High Priority (For Functionality)

5. **Time field conversions** - chrono to int
6. **restore_piece constants** - dont_download verification
7. **verify_resume_data signature** - Match exactly

### Medium Priority (For Completeness)

8. **announce_entry updates** - Verify constructor
9. **Session stats migration** - If used
10. **DHT settings** - If configured

### Low Priority (Optimizations)

11. **Async operations** - For performance
12. **Peer class updates** - If used

---

## Test Cases to Add

### Critical Path Tests

1. Memory storage creation with 1.2.x params
2. Piece priority setting/getting
3. File priority setting/getting
4. Resume data round-trip
5. Time field access

### Regression Tests

1. Lookbehind buffer protection
2. LRU eviction
3. Reader piece tracking
4. Buffer allocation/deallocation

### Integration Tests

1. Full torrent add/remove cycle
2. Playback with seeking
3. Resume after restart
4. Multi-file torrent handling

---

## Summary

### Critical Issues: 3
- storage_interface constructor
- download_priority_t types
- Time field types

### High Priority Issues: 4
- open_mode_t
- storage_params
- restore_piece
- verify_resume_data

### Medium Priority Issues: 5+
- Various SWIG and API updates

### Estimated Additional Work: 1-2 days

Most issues are related to type safety changes in 1.2.x. The storage_interface refactoring is the biggest concern and needs immediate investigation before attempting a build.
