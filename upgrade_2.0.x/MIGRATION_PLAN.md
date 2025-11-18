# libtorrent 2.0.x Migration Plan

## Executive Summary

**Source Version**: libtorrent 1.2.x (after completing 1.2.x upgrade)
**Target Version**: libtorrent 2.0.11 (latest stable)
**Key Change**: Complete rewrite of storage system from `storage_interface` to `disk_interface`

**Estimated Effort**: 3-4 weeks additional (after 1.2.x upgrade)

---

## 1. Architecture Changes Overview

### 1.1 Storage System Revolution

| Aspect | 1.2.x | 2.0.x |
|--------|-------|-------|
| **Customization Point** | Per-torrent `storage_interface` | Session-level `disk_interface` |
| **Configured At** | `add_torrent_params::storage` | `session_params::disk_io_constructor` |
| **Operations** | Synchronous `readv`/`writev` | Async `async_read`/`async_write` |
| **Scope** | One storage per torrent | One disk I/O for all torrents |
| **Torrent Identification** | Pointer to storage | `storage_index_t` typed index |
| **Threading** | Storage handles own locking | disk_interface can manage threads |
| **Result Return** | Return values | Callbacks with `std::function<>` |

### 1.2 BitTorrent v2 Support

| Feature | Description |
|---------|-------------|
| **Dual Info Hashes** | Both SHA-1 (v1) and SHA-256 (v2) |
| **`info_hash_t` Type** | New type containing both hashes |
| **Per-File Hash Trees** | v2 uses merkle trees per file |
| **Hybrid Torrents** | Can participate in both v1 and v2 swarms |
| **Truncated v2 for DHT** | SHA-256 truncated to 20 bytes for DHT/trackers |

### 1.3 Build Requirements

- **C++14 required** (was C++11 in 1.2.x)
- **cmake preferred** (configure still supported)
- **Boost 1.67+** (for Asio io_context)

---

## 2. Core Implementation: memory_disk_io

### 2.1 Class Structure

```cpp
namespace libtorrent {

// Data holder for one torrent's memory storage
struct memory_storage
{
    std::map<piece_index_t, std::vector<char>> m_file_data;
    file_storage const& m_files;
    int piece_length;
    int num_pieces;

    // Lookbehind support
    boost::dynamic_bitset<> lookbehind_pieces;
    boost::dynamic_bitset<> reader_pieces;

    // Buffer management
    int64_t capacity;
    int buffer_limit;
    // ... existing fields from memory_storage

    span<char const> readv(peer_request const& r, storage_error& ec) const;
    void writev(span<char const> b, piece_index_t piece, int offset);
    sha1_hash hash(piece_index_t piece, span<sha256_hash> block_hashes, storage_error& ec) const;
    sha256_hash hash2(piece_index_t piece, int offset, storage_error& ec);
};

// Session-level disk I/O handler
struct memory_disk_io final
    : disk_interface
    , buffer_allocator_interface
{
private:
    io_context& m_ioc;
    aux::vector<std::unique_ptr<memory_storage>, storage_index_t> m_torrents;
    std::vector<storage_index_t> m_free_slots;

    // Global settings
    int64_t m_total_memory_limit;
    bool m_logging_enabled;

public:
    explicit memory_disk_io(io_context& ioc);

    // disk_interface implementation
    storage_holder new_torrent(storage_params const& p,
                               std::shared_ptr<void> const& torrent) override;
    void remove_torrent(storage_index_t) override;

    void async_read(storage_index_t storage, peer_request const& r,
                    std::function<void(disk_buffer_holder, storage_error const&)> handler,
                    disk_job_flags_t flags = {}) override;

    bool async_write(storage_index_t storage, peer_request const& r,
                     char const* buf, std::shared_ptr<disk_observer> o,
                     std::function<void(storage_error const&)> handler,
                     disk_job_flags_t flags = {}) override;

    void async_hash(storage_index_t storage, piece_index_t piece,
                    span<sha256_hash> block_hashes, disk_job_flags_t flags,
                    std::function<void(piece_index_t, sha1_hash const&, storage_error const&)> handler) override;

    void async_hash2(storage_index_t storage, piece_index_t piece, int offset,
                     disk_job_flags_t flags,
                     std::function<void(piece_index_t, sha256_hash const&, storage_error const&)> handler) override;

    void async_move_storage(storage_index_t storage, std::string p, move_flags_t flags,
                            std::function<void(status_t, std::string const&, storage_error const&)> handler) override;

    void async_release_files(storage_index_t storage,
                             std::function<void()> handler = std::function<void()>()) override;

    void async_check_files(storage_index_t storage, add_torrent_params const* resume_data,
                           aux::vector<std::string, file_index_t> links,
                           std::function<void(status_t, storage_error const&)> handler) override;

    void async_stop_torrent(storage_index_t storage,
                            std::function<void()> handler = std::function<void()>()) override;

    void async_rename_file(storage_index_t storage, file_index_t index, std::string name,
                           std::function<void(std::string const&, file_index_t, storage_error const&)> handler) override;

    void async_delete_files(storage_index_t storage, remove_flags_t options,
                            std::function<void(storage_error const&)> handler) override;

    void async_set_file_priority(storage_index_t storage,
                                 aux::vector<download_priority_t, file_index_t> prio,
                                 std::function<void(storage_error const&,
                                     aux::vector<download_priority_t, file_index_t>)> handler) override;

    void async_clear_piece(storage_index_t storage, piece_index_t index,
                           std::function<void(piece_index_t)> handler) override;

    // Additional methods
    void update_stats_counters(counters& c) const override;
    std::vector<open_file_state> get_status(storage_index_t) const override;
    void abort(bool wait) override;
    void submit_jobs() override;
    void settings_updated() override;

    // buffer_allocator_interface
    void free_disk_buffer(char*) override;

    // Custom methods for lookbehind
    void set_lookbehind_pieces(storage_index_t, std::vector<int> const& pieces);
    void clear_lookbehind(storage_index_t);
    bool is_lookbehind_available(storage_index_t, int piece) const;
    int get_lookbehind_stats(storage_index_t, int& available, int& protected_count, int64_t& memory) const;
};

// Factory function for session_params
std::unique_ptr<disk_interface> memory_disk_constructor(
    io_context& ioc, settings_interface const&, counters&);

} // namespace libtorrent
```

### 2.2 Key Implementation Details

#### Async Read Implementation
```cpp
void memory_disk_io::async_read(storage_index_t storage, peer_request const& r,
    std::function<void(disk_buffer_holder, storage_error const&)> handler,
    disk_job_flags_t)
{
    storage_error error;
    auto const& st = *m_torrents[storage];

    // Perform synchronous read
    span<char const> data = st.readv(r, error);

    // Post callback asynchronously
    post(m_ioc, [handler, error, data, this]
    {
        handler(disk_buffer_holder(*this, const_cast<char*>(data.data()), int(data.size())), error);
    });
}
```

#### Async Write Implementation
```cpp
bool memory_disk_io::async_write(storage_index_t storage, peer_request const& r,
    char const* buf, std::shared_ptr<disk_observer>,
    std::function<void(storage_error const&)> handler, disk_job_flags_t)
{
    storage_error error;
    auto& st = *m_torrents[storage];

    // Perform synchronous write
    st.writev({buf, r.length}, r.piece, r.start);

    // Post callback asynchronously
    post(m_ioc, [handler, error] { handler(error); });
    return false; // false = not write-blocked
}
```

#### Storage Index Management
```cpp
storage_holder memory_disk_io::new_torrent(storage_params const& p,
    std::shared_ptr<void> const&)
{
    storage_index_t idx;

    if (m_free_slots.empty())
    {
        idx = storage_index_t(int(m_torrents.size()));
        m_torrents.emplace_back(std::make_unique<memory_storage>(p));
    }
    else
    {
        idx = m_free_slots.back();
        m_free_slots.pop_back();
        m_torrents[idx] = std::make_unique<memory_storage>(p);
    }

    return storage_holder(idx, *this);
}

void memory_disk_io::remove_torrent(storage_index_t idx)
{
    m_torrents[idx].reset();
    m_free_slots.push_back(idx);
}
```

---

## 3. Breaking Changes from 1.2.x

### 3.1 Removed Features

| Removed | Replacement |
|---------|-------------|
| `add_torrent_params::storage` | `session_params::disk_io_constructor` |
| `torrent_handle::get_storage_impl()` | Use disk_interface methods |
| `session::load_state()` / `save_state()` | `read_session_params()` / `write_session_params()` |
| `stats_alert` | `session::post_torrent_updates()` |
| `add_torrent_params::url` | Use `parse_magnet_uri()` |
| `add_torrent_params::info_hash` | `add_torrent_params::info_hashes` |
| `lazy_bdecode` / `lazy_entry` | Use `bdecode_node` |
| Bittyrant choking | Fixed slots choker |

### 3.2 Type Changes

| Old Type | New Type |
|----------|----------|
| `sha1_hash` (for info hash) | `info_hash_t` |
| `boost::asio::io_service` | `lt::io_context` (alias) |
| `int` (resume data) | Use `read_resume_data()` functions |
| `dht_settings` | Unified into `settings_pack` |

### 3.3 API Changes

```cpp
// OLD (1.2.x)
torrent_handle::info_hash();           // Returns sha1_hash
add_torrent_params::info_hash = ...;   // sha1_hash field
session(settings_pack);                // Simple constructor

// NEW (2.0.x)
torrent_handle::info_hashes();         // Returns info_hash_t
add_torrent_params::info_hashes = ...; // info_hash_t field
session(session_params);               // Takes session_params
```

---

## 4. SWIG Interface Updates

### 4.1 New Interfaces Required

#### disk_interface.i
```cpp
%{
#include <libtorrent/disk_interface.hpp>
#include <libtorrent/session_params.hpp>
%}

// storage_index_t type
%template(StorageIndex) lt::storage_index_t;

// disk_interface is internal, expose through session_params
%extend libtorrent::session_params {
    void set_memory_disk_io(std::int64_t memory_size) {
        libtorrent::memory_disk_memory_size = memory_size;
        self->disk_io_constructor = libtorrent::memory_disk_constructor;
    }
}
```

#### info_hash.i
```cpp
%{
#include <libtorrent/info_hash.hpp>
%}

%include <libtorrent/info_hash.hpp>

// Helper methods for info_hash_t
%extend libtorrent::info_hash_t {
    std::string v1_hex() const {
        return lt::aux::to_hex(self->v1);
    }

    std::string v2_hex() const {
        return lt::aux::to_hex(self->get_best());
    }

    bool has_v1() const {
        return self->has_v1();
    }

    bool has_v2() const {
        return self->has_v2();
    }
}
```

#### session_params.i
```cpp
%{
#include <libtorrent/session_params.hpp>
%}

%include <libtorrent/session_params.hpp>

// Session constructor now takes session_params
%extend libtorrent::session {
    static session* create_with_params(session_params& params) {
        return new session(std::move(params));
    }
}
```

### 4.2 Updated Interfaces

#### torrent_handle.i Updates
```cpp
// Add info_hashes method
%extend libtorrent::torrent_handle {
    // Backward compatible - returns v1 hash
    std::string info_hash_v1_string() const {
        auto ih = self->info_hashes();
        return lt::aux::to_hex(ih.v1);
    }

    // New - returns both hashes
    libtorrent::info_hash_t info_hashes_typed() const {
        return self->info_hashes();
    }
}

// Remove deprecated methods
%ignore libtorrent::torrent_handle::info_hash;
```

#### add_torrent_params.i Updates
```cpp
// Update for info_hashes (plural)
%extend libtorrent::add_torrent_params {
    void set_info_hash_v1(std::string const& hex) {
        self->info_hashes.v1 = lt::sha1_hash(hex);
    }

    // Storage is no longer set per-torrent
    // Use session_params::disk_io_constructor instead
}

// Ignore deprecated field
%ignore libtorrent::add_torrent_params::info_hash;
%ignore libtorrent::add_torrent_params::storage;
```

---

## 5. Elementum Code Updates

### 5.1 Session Creation

```go
// OLD (1.2.x)
settings := lt.NewSettingsPack()
// ... configure settings ...
session := lt.NewSession(settings, 0)

// NEW (2.0.x)
settings := lt.NewSettingsPack()
// ... configure settings ...

params := lt.NewSessionParams()
params.SetSettings(settings)
params.SetMemoryDiskIO(memorySize)  // Configure memory storage at session level

session := lt.CreateSessionWithParams(params)
```

### 5.2 Info Hash Access

```go
// OLD (1.2.x)
infoHash := torrentStatus.GetInfoHash().ToString()

// NEW (2.0.x)
infoHashes := torrentStatus.GetInfoHashes()
infoHashV1 := infoHashes.V1Hex()  // For backward compatibility
// Or check both:
if infoHashes.HasV2() {
    infoHashV2 := infoHashes.V2Hex()
}
```

### 5.3 Lookbehind Buffer Access

Since storage is now at session level, we need a different approach:

```go
// OLD (1.2.x) - Per-torrent storage
ms := t.th.GetMemoryStorage()
ms.SetLookbehindPieces(pieces)

// NEW (2.0.x) - Through session's disk_interface
// Need to expose methods through session or use storage_index_t
session.SetLookbehindPieces(storageIndex, pieces)
```

This requires:
1. Tracking storage_index_t for each torrent
2. Exposing disk_interface methods through SWIG
3. Or: Creating a Go-side wrapper that coordinates with disk_io

### 5.4 Resume Data

```go
// OLD (1.2.x)
params := lt.ReadResumeData(data, errorCode)

// NEW (2.0.x) - Same API, but info_hashes instead of info_hash
params := lt.ReadResumeData(data, errorCode)
// But when comparing:
if params.GetInfoHashes().V1Hex() == existingHash {
    // Match found
}
```

---

## 6. Migration Phases

### Phase 1: Infrastructure (Week 1)

#### 1.1 Build System Updates
- Update LIBTORRENT_VERSION to v2.0.11
- Set C++14 standard in all Docker files
- Update cmake configuration

#### 1.2 Core Type Updates
- Add info_hash_t support
- Add storage_index_t type
- Add disk_interface base

#### 1.3 SWIG Foundation
- Create session_params.i
- Create info_hash.i
- Create disk_interface.i skeleton

### Phase 2: memory_disk_io Implementation (Week 2)

#### 2.1 Core Structure
- Create memory_disk_io class
- Implement storage management (new_torrent, remove_torrent)
- Implement slot reuse

#### 2.2 Async Operations
- async_read with callback posting
- async_write with callback posting
- async_hash / async_hash2 for v1/v2

#### 2.3 Supporting Operations
- async_move_storage (return error - not supported)
- async_release_files
- async_delete_files
- async_rename_file
- async_set_file_priority
- async_clear_piece
- async_check_files

#### 2.4 Lookbehind Integration
- Port lookbehind logic to memory_storage
- Expose through disk_interface wrapper
- Handle multi-torrent scenarios

### Phase 3: Elementum Updates (Week 3)

#### 3.1 Session Creation
- Switch to session_params
- Configure disk_io_constructor
- Handle memory_size at session level

#### 3.2 Info Hash Migration
- Update all info_hash() calls to info_hashes()
- Add v1/v2 hash handling
- Update torrent identification

#### 3.3 Lookbehind Rearchitecture
- Track storage_index_t per torrent
- Route lookbehind calls through session
- Update player.go and torrent.go

#### 3.4 Resume Data
- Verify resume data compatibility
- Update any info_hash comparisons

### Phase 4: Testing & Validation (Week 4)

#### 4.1 Unit Tests
- memory_disk_io creation
- Async read/write operations
- Hash computation (v1 and v2)
- Storage index management

#### 4.2 Integration Tests
- Full torrent lifecycle
- Multiple torrents with shared disk_io
- Lookbehind buffer across torrents
- Resume data round-trip

#### 4.3 Performance Tests
- Compare with 1.2.x baseline
- Memory usage patterns
- Async callback overhead
- Multi-torrent scenarios

#### 4.4 Platform Testing
- Build for all 13 platforms
- Test on Linux, Windows, Android
- Verify hybrid torrent handling

---

## 7. Risk Assessment

### 7.1 High Risk Areas

| Risk | Impact | Mitigation |
|------|--------|------------|
| Complete storage rewrite | Core functionality break | Extensive testing, keep 1.2.x fallback |
| Async callback complexity | Race conditions, deadlocks | Careful io_context usage, thread safety |
| Multi-torrent lookbehind | Memory management | Clear ownership, per-storage limits |
| SWIG binding complexity | Go interop failures | Test each binding thoroughly |

### 7.2 Medium Risk Areas

| Risk | Impact | Mitigation |
|------|--------|------------|
| info_hash_t migration | Torrent identification issues | Careful v1/v2 handling |
| C++14 build issues | Platform incompatibility | Test all Docker toolchains |
| v2 hash computation | Performance, correctness | Test with known v2 torrents |

### 7.3 Low Risk Areas

| Risk | Impact | Mitigation |
|------|--------|------------|
| Settings changes | Minor functionality | Document and test each |
| Alert changes | Logging gaps | Update all alert handlers |

---

## 8. Rollback Strategy

### 8.1 Version Branching

```bash
# Create feature branch
git checkout -b feature/libtorrent-2.0-upgrade

# Keep 1.2.x as stable
git tag stable-1.2.x
```

### 8.2 Conditional Compilation

Consider build flags to select version:
```cpp
#ifdef LIBTORRENT_2_0
    // 2.0.x code
#else
    // 1.2.x code
#endif
```

### 8.3 Staged Deployment

1. Alpha: Internal testing only
2. Beta: Opt-in for power users
3. RC: Wider testing
4. Release: Full deployment

---

## 9. Documentation Requirements

### 9.1 User Documentation
- New session creation flow
- Memory storage configuration
- Hybrid torrent support
- Breaking changes list

### 9.2 Developer Documentation
- disk_interface architecture
- SWIG binding details
- Async callback patterns
- Storage index management

---

## 10. Success Criteria

### 10.1 Functional Requirements
- [ ] All existing features work
- [ ] Lookbehind buffer functional
- [ ] Resume data works
- [ ] Multiple torrents work

### 10.2 Performance Requirements
- [ ] Memory usage ≤ 1.2.x
- [ ] Seek latency ≤ 1.2.x
- [ ] CPU usage ≤ 1.2.x + 10%

### 10.3 Quality Requirements
- [ ] All tests pass
- [ ] No memory leaks
- [ ] No deadlocks
- [ ] Clean build on all platforms

---

## 11. Timeline Summary

| Week | Focus | Deliverables |
|------|-------|--------------|
| Week 1 | Infrastructure | Build system, SWIG foundation, core types |
| Week 2 | memory_disk_io | Complete implementation with lookbehind |
| Week 3 | Elementum | All code updates, integration |
| Week 4 | Testing | Validation, performance, platforms |

**Total: 4 weeks** (after 1.2.x upgrade is complete)

---

## 12. Dependencies

### 12.1 Prerequisites
- libtorrent 1.2.x upgrade complete and tested
- Understanding of Boost.Asio io_context
- familiarity with async callback patterns

### 12.2 External Resources
- libtorrent 2.0 documentation
- BitTorrent v2 specification (BEP 52)
- qBittorrent 2.0 migration experiences

---

## 13. Open Questions

1. **Should we support v2-only torrents?**
   - Initial: Support hybrid and v1-only
   - Future: Full v2 support

2. **Memory sharing across torrents?**
   - Consider global buffer pool
   - Or per-torrent limits

3. **Lookbehind in multi-torrent scenario?**
   - Per-torrent lookbehind
   - Or shared lookbehind pool

4. **Storage index exposure to Elementum?**
   - Expose as opaque handle
   - Or internal tracking

---

## Conclusion

The 2.0.x migration is a substantial undertaking due to the complete storage architecture change. However, it brings significant benefits:

- Modern async architecture
- BitTorrent v2 support
- Better multi-torrent handling
- Performance improvements

The phased approach with 1.2.x as an intermediate step reduces risk and allows for incremental validation.

Estimated total effort: **7-8 weeks** (3-4 for 1.2.x + 4 for 2.0.x)
