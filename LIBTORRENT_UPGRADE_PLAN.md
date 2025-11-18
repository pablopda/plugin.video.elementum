# Libtorrent Upgrade Plan: 1.1.x → 1.2.x/2.0.x

## Executive Summary

**Current State**: libtorrent RC_1_1 (commit from March 2020 - 5 years old)
**Target Options**:
- **Conservative**: libtorrent 1.2.20 (latest 1.2.x branch)
- **Modern**: libtorrent 2.0.11 (latest stable, requires C++14)

**Recommendation**: Upgrade to **1.2.x first**, then evaluate 2.0.x

**Estimated Effort**:
- 1.2.x upgrade: 2-3 weeks development + 1 week testing
- 2.0.x upgrade: Additional 1-2 weeks

---

## 1. Breaking Changes Analysis

### 1.1 Critical Breaking Changes (Affects Elementum)

| Change | Version | Impact | Elementum Files Affected |
|--------|---------|--------|--------------------------|
| `boost::shared_ptr` → `std::shared_ptr` | 1.2.x | All SWIG interfaces | All .i files, memory_storage.hpp |
| Storage interface refactoring | 1.2.x | memory_storage.hpp needs rewrite | memory_storage.hpp |
| `lazy_bitfields` setting removed | 1.2.x | Setting no longer exists | service.go:234 |
| `bittyrant` choker removed | 2.0.x | Algorithm removed | service.go:334 |
| Resume data API change | 1.2.x | New handling method | service.go:800-807, 1040 |
| `info_hash` → `info_hash_t` | 2.0.x | Dual hash support | Multiple files |
| `string_view` and `span<>` adoption | 1.2.x | Interface changes | SWIG interfaces |
| DHT settings unified | 2.0.x | Moved to settings_pack | service.go DHT settings |

### 1.2 Settings Pack Changes

#### Removed in 1.2.x
```go
// These settings no longer exist:
settings.SetBool("lazy_bitfields", true)        // line 234 - REMOVED
settings.SetBool("use_dht_as_fallback", false)  // line 242 - DEPRECATED
```

#### Removed in 2.0.x
```go
// Bittyrant choker algorithm removed:
settings.SetInt("choking_algorithm", lt.SettingsPackBittyrantChoker) // line 334 - REMOVED
```

#### Changed Behavior
```go
// force_proxy now means "always use proxy" in 1.2.x
settings.SetBool("force_proxy", false) // line 411 - BEHAVIOR CHANGED
```

### 1.3 Type System Changes

#### 1.2.x: boost → std
```cpp
// OLD (1.1.x)
boost::shared_ptr<torrent_plugin>

// NEW (1.2.x)
std::shared_ptr<torrent_plugin>
```

**Affected Files**:
- `upload_plugin.hpp` - Uses `boost::shared_ptr`
- `memory_storage.hpp` - Uses `boost::shared_ptr`, `boost::mutex`
- All SWIG .i files - Template declarations

#### 2.0.x: info_hash changes
```cpp
// OLD (1.1.x, 1.2.x)
sha1_hash info_hash;
add_torrent_params::info_hash

// NEW (2.0.x)
info_hash_t info_hashes;  // Contains both v1 (SHA-1) and v2 (SHA-256)
add_torrent_params::info_hashes
```

**Affected Code**:
- `torrentParams.GetInfoHash().ToString()` - service.go:743
- `ts.GetInfoHash().ToString()` - torrent.go:123
- `stateAlert.GetHandle().InfoHash().ToString()` - torrentfs.go:158

### 1.4 Storage Interface Changes (Critical)

The storage interface underwent major refactoring in 1.2.x:

```cpp
// OLD (1.1.x) - memory_storage.hpp uses this
struct storage_interface {
    virtual int readv(file::iovec_t const* bufs, int num_bufs,
                      int piece, int offset, int flags, storage_error& ec) = 0;
    virtual int writev(file::iovec_t const* bufs, int num_bufs,
                       int piece, int offset, int flags, storage_error& ec) = 0;
};

// NEW (1.2.x) - Uses span<>
struct storage_interface {
    virtual int readv(span<iovec_t const> bufs,
                      piece_index_t piece, int offset,
                      open_mode_t mode, storage_error& ec) = 0;
    virtual int writev(span<iovec_t const> bufs,
                       piece_index_t piece, int offset,
                       open_mode_t mode, storage_error& ec) = 0;
};
```

**Impact**: Complete rewrite of `memory_storage.hpp` read/write methods required.

### 1.5 Resume Data Changes

```cpp
// OLD (1.1.x)
add_torrent_params p;
p.resume_data = read_resume_data_from_file();

// NEW (1.2.x)
add_torrent_params p = read_resume_data(resume_data_buffer);
// Or use write_resume_data() / read_resume_data() functions
```

**Affected Code**:
- `torrentParams.SetResumeData(fastResumeVector)` - service.go:807
- `t.th.SaveResumeData(1)` - service.go:1040

---

## 2. Dependency Updates Required

### 2.1 Build Dependencies

| Dependency | Current | For 1.2.x | For 2.0.x |
|------------|---------|-----------|-----------|
| Boost | 1.72.0 | 1.72.0+ | 1.72.0+ |
| OpenSSL | 1.1.1f | 1.1.1+ | 1.1.1+ |
| C++ Standard | C++11 | C++11 | **C++14** |
| GCC | 9.x | 9.x | 9.x+ |

### 2.2 Makefile Changes

```makefile
# Current
LIBTORRENT_VERSION = 760f94862ef6b76a13bba0a68d55ca6507aef7c2 # RC_1_1

# For 1.2.x upgrade
LIBTORRENT_VERSION = v1.2.20  # Or specific commit from RC_1_2 branch

# For 2.0.x upgrade
LIBTORRENT_VERSION = v2.0.11  # Or specific commit from RC_2_0 branch
CXXFLAGS += -std=c++14  # Required for 2.0.x
```

---

## 3. Phased Migration Plan

### Phase 1: Preparation & Analysis (Week 1)

#### 1.1 Create Test Suite
- [ ] Write comprehensive tests for current functionality
- [ ] Test backward seeking (lookbehind buffer)
- [ ] Test resume data save/load
- [ ] Test all alert types
- [ ] Test memory storage limits

#### 1.2 Fork and Branch
```bash
# Create upgrade branch
git checkout -b feature/libtorrent-1.2-upgrade
```

#### 1.3 Document Current Behavior
- [ ] Record piece prioritization behavior
- [ ] Record memory usage patterns
- [ ] Record alert timing and types

---

### Phase 2: libtorrent-go Updates (Week 1-2)

#### 2.1 Update Makefile
```makefile
# Update version
LIBTORRENT_VERSION = v1.2.20

# Update boost if needed
BOOST_VERSION = 1.78.0  # For better C++14 support
```

#### 2.2 Update SWIG Interfaces

**interfaces/session.i**
```cpp
// Update shared_ptr usage
%include <std_shared_ptr.i>
%shared_ptr(libtorrent::torrent_plugin)

// Update deprecated functions
%ignore libtorrent::session::load_state;  // Use read_session_params
%ignore libtorrent::session::save_state;  // Use write_session_params
```

**interfaces/add_torrent_params.i**
```cpp
// Handle resume data changes
%extend libtorrent::add_torrent_params {
    // Old method - mark deprecated
    void set_resume_data_deprecated(std::vector<char> const& data) {
        // Convert to new format
    }
}
```

**interfaces/torrent_handle.i**
```cpp
// Update for span<> usage
%include <std_span.i>

// Handle piece_index_t type
%template(piece_index) libtorrent::piece_index_t;
```

#### 2.3 Update memory_storage.hpp

**Critical Changes Required**:

```cpp
// 1. Replace boost with std
#include <memory>
#include <mutex>

// Replace:
// boost::shared_ptr -> std::shared_ptr
// boost::mutex -> std::mutex
// boost::unique_lock -> std::unique_lock

// 2. Update readv/writev signatures
int readv(lt::span<lt::iovec_t const> bufs,
          lt::piece_index_t piece, int offset,
          lt::open_mode_t mode, lt::storage_error& ec) override
{
    // Update implementation for span<>
    int piece_idx = static_cast<int>(piece);
    // ... rest of implementation
}

// 3. Update storage_params handling
memory_storage(lt::storage_params const& params, lt::file_pool& pool)
    : lt::storage_interface(params)
{
    // New constructor signature
}
```

#### 2.4 Update upload_plugin.hpp

```cpp
// Replace boost::shared_ptr
#include <memory>

TORRENT_EXPORT std::shared_ptr<torrent_plugin>
    create_upload_plugin(torrent_handle const&, void*);
```

---

### Phase 3: Elementum Updates (Week 2)

#### 3.1 Settings Updates

**service.go** - Remove deprecated settings:
```go
// REMOVE these lines:
// settings.SetBool("lazy_bitfields", true)        // line 234
// settings.SetBool("use_dht_as_fallback", false)  // line 242

// UPDATE for 2.0.x - remove bittyrant:
// settings.SetInt("choking_algorithm", lt.SettingsPackBittyrantChoker) // line 334
// Use SettingsPackFixedSlotsChoker instead
```

#### 3.2 Resume Data Handling

**service.go** - Update resume data API:
```go
// OLD approach (lines 800-807):
fastResumeVector := lt.NewStdVectorChar()
for _, c := range fastResumeData {
    fastResumeVector.Add(c)
}
torrentParams.SetResumeData(fastResumeVector)

// NEW approach for 1.2.x:
// Use read_resume_data() to create add_torrent_params directly
torrentParams = lt.ReadResumeData(fastResumeData, errorCode)
if errorCode.Failed() {
    // Handle error
}
```

#### 3.3 Info Hash Handling (for 2.0.x)

**Multiple files** - Update info hash access:
```go
// OLD:
infoHash := ts.GetInfoHash().ToString()

// NEW (2.0.x):
infoHashes := ts.GetInfoHashes()
infoHashV1 := infoHashes.GetV1().ToString()  // SHA-1
// For backwards compatibility, use V1 hash
```

#### 3.4 Alert Handling Updates

Some alert types changed in 1.2.x:
```go
// Verify these alert types still exist:
// - lt.StateChangedAlertAlertType ✓
// - lt.SaveResumeDataAlertAlertType ✓
// - lt.MetadataReceivedAlertAlertType ✓

// stats_alert is deprecated in 2.0.x
// Use session::post_torrent_updates() instead
```

---

### Phase 4: Build System Updates (Week 2)

#### 4.1 Docker Updates

**docker/linux-x64.Dockerfile**:
```dockerfile
# Update libtorrent version
ARG LIBTORRENT_VERSION=v1.2.20

# For 2.0.x, add C++14 flag
ENV LT_CXXFLAGS="-std=c++14 -fPIC"
```

#### 4.2 build-libtorrent.sh Updates

```bash
# Update branch
LIBTORRENT_BRANCH="RC_1_2"  # or "RC_2_0" for 2.0.x

# Update cmake flags for 2.0.x
cmake -DCMAKE_CXX_STANDARD=14 ...
```

---

### Phase 5: Testing & Validation (Week 3)

#### 5.1 Unit Tests

Create test file: `test/upgrade_test.go`

```go
package test

import (
    "testing"
    lt "github.com/ElementumOrg/libtorrent-go"
)

func TestSessionCreation(t *testing.T) {
    settings := lt.NewSettingsPack()
    defer lt.DeleteSettingsPack(settings)

    session := lt.NewSession(settings, 0)
    defer lt.DeleteSession(session)

    if session.Swigcptr() == 0 {
        t.Fatal("Failed to create session")
    }
}

func TestResumeDataNewAPI(t *testing.T) {
    // Test new resume data API
    resumeData := []byte{...} // Sample resume data

    errorCode := lt.NewErrorCode()
    defer lt.DeleteErrorCode(errorCode)

    params := lt.ReadResumeData(resumeData, errorCode)
    if errorCode.Failed() {
        t.Fatalf("Failed to read resume data: %s", errorCode.Message())
    }
}

func TestMemoryStorage(t *testing.T) {
    // Test memory storage still works
    // Test lookbehind buffer functionality
}

func TestPiecePrioritization(t *testing.T) {
    // Test piece priorities still work as expected
}
```

#### 5.2 Integration Tests

```bash
# Test with real torrent
./test_lookbehind.sh

# Test backward seeking
# Test memory limits
# Test resume data persistence
```

#### 5.3 Performance Benchmarks

Compare before/after:
- Memory usage
- CPU usage
- Piece download speed
- Seek latency

---

### Phase 6: Deployment & Rollback Plan (Week 3)

#### 6.1 Staged Rollout

1. **Alpha**: Internal testing
2. **Beta**: Limited user testing with verbose logging
3. **Release**: Full deployment

#### 6.2 Rollback Procedure

```bash
# If issues found, rollback to previous version
git checkout main
git revert --no-commit feature/libtorrent-1.2-upgrade
```

#### 6.3 Monitoring

- Monitor crash reports
- Monitor memory usage patterns
- Monitor user-reported seeking issues

---

## 4. Specific Code Changes Required

### 4.1 libtorrent-go Repository

| File | Changes Required | Effort |
|------|-----------------|--------|
| `Makefile` | Update LIBTORRENT_VERSION | Low |
| `memory_storage.hpp` | Rewrite for new storage API | **High** |
| `upload_plugin.hpp` | boost→std shared_ptr | Low |
| `interfaces/session.i` | Update deprecated functions | Medium |
| `interfaces/add_torrent_params.i` | Resume data API | Medium |
| `interfaces/torrent_handle.i` | span<> support | Medium |
| `libtorrent_cgo.go` | Update compiler flags | Low |
| All Docker files | Update libtorrent build | Medium |

### 4.2 Elementum Repository

| File | Changes Required | Effort |
|------|-----------------|--------|
| `bittorrent/service.go` | Remove deprecated settings, update resume API | Medium |
| `bittorrent/torrent.go` | Update status getters if API changed | Low |
| `bittorrent/lookbehind.go` | Verify memory_storage API compatibility | Low |
| `config/config.go` | Remove deprecated config options | Low |

---

## 5. Risk Assessment

### 5.1 High Risk Areas

1. **memory_storage.hpp rewrite**
   - Risk: Break streaming functionality
   - Mitigation: Extensive testing, keep backup of working version

2. **Resume data API change**
   - Risk: Lose saved torrent state
   - Mitigation: Support both old and new formats during transition

3. **Cross-compilation**
   - Risk: Build failures on some platforms
   - Mitigation: Test all 13 platforms before release

### 5.2 Medium Risk Areas

1. **Settings changes**
   - Risk: Unexpected behavior
   - Mitigation: Document all changed settings

2. **Alert type changes**
   - Risk: Miss important events
   - Mitigation: Log all alerts during testing

### 5.3 Low Risk Areas

1. **Type changes (boost→std)**
   - Risk: Compilation errors
   - Mitigation: Systematic replacement

---

## 6. Benefits of Upgrade

### 6.1 libtorrent 1.2.x Benefits

- Bug fixes accumulated over 5 years
- Better memory management
- Improved piece caching
- Enhanced DHT support
- Better Windows support
- Security fixes

### 6.2 libtorrent 2.0.x Additional Benefits

- BitTorrent v2 support (SHA-256 hashes)
- Improved disk I/O subsystem
- Better encryption support
- Modern C++14 features
- Further performance improvements

---

## 7. Timeline Summary

| Phase | Duration | Tasks |
|-------|----------|-------|
| Phase 1: Preparation | Week 1 | Tests, documentation, branch setup |
| Phase 2: libtorrent-go | Week 1-2 | SWIG updates, memory_storage rewrite |
| Phase 3: Elementum | Week 2 | Settings, resume data, alerts |
| Phase 4: Build System | Week 2 | Docker, Makefile updates |
| Phase 5: Testing | Week 3 | Unit tests, integration, benchmarks |
| Phase 6: Deployment | Week 3 | Staged rollout, monitoring |

**Total Estimated Time**: 3 weeks

---

## 8. Decision: 1.2.x vs 2.0.x

### Recommended: Start with 1.2.x

**Reasons**:
1. Smaller jump (fewer breaking changes)
2. Still actively maintained (v1.2.20 released Jan 2025)
3. C++11 compatible (no build system overhaul)
4. Proven stability in production (qBittorrent uses it)

### Future: Consider 2.0.x

**When to upgrade to 2.0.x**:
1. After 1.2.x is stable
2. When BitTorrent v2 adoption increases
3. When C++14 is standard across all build platforms

---

## 9. Validation Checklist

### Pre-Upgrade
- [ ] All current tests pass
- [ ] Baseline performance recorded
- [ ] Backup of working version

### Post-Upgrade
- [ ] All tests pass on new version
- [ ] Performance is same or better
- [ ] Backward seeking works (lookbehind)
- [ ] Resume data loads correctly
- [ ] All 13 platforms build successfully
- [ ] Memory usage within limits
- [ ] No crash reports

### User Acceptance
- [ ] Alpha testers report no issues
- [ ] Beta testers report no issues
- [ ] Public release stable for 1 week

---

## 10. Resources

### Official Documentation
- [libtorrent 1.2 Upgrade Guide](https://www.libtorrent.org/upgrade_to_1.2-ref.html)
- [libtorrent 2.0 Upgrade Guide](https://www.libtorrent.org/upgrade_to_2.0-ref.html)
- [libtorrent API Reference](https://www.libtorrent.org/reference.html)

### Related Projects
- [qBittorrent](https://github.com/qbittorrent/qBittorrent) - Uses libtorrent 1.2.x/2.0.x
- [Deluge](https://github.com/deluge-torrent/deluge) - Python bindings for libtorrent

### ElementumOrg Repositories
- [libtorrent-go](https://github.com/ElementumOrg/libtorrent-go)
- [elementum](https://github.com/elgatito/elementum)
