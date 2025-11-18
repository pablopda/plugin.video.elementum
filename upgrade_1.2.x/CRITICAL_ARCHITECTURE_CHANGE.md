# CRITICAL: Storage Architecture Change in libtorrent 1.2.x

## BREAKING CHANGE - storage_interface is REPLACED

**This is the most significant finding of the evaluation.**

### What Changed

In libtorrent 1.2.x, the entire disk I/O customization architecture changed:

| Aspect | 1.1.x | 1.2.x |
|--------|-------|-------|
| Customization Point | Per-torrent `storage_interface` | Session-level `disk_interface` |
| Inheritance | `storage_interface` base class | `disk_interface` base class |
| Operations | Synchronous `readv`/`writev` | Async `async_read`/`async_write` |
| Scope | One storage per torrent | One disk I/O for entire session |
| Constructor | `storage_params` | `disk_io_constructor` in `session_params` |

### Impact on Our Implementation

**Our current memory_storage.hpp is based on the 1.1.x architecture and will NOT work in 1.2.x!**

Current approach (WRONG for 1.2.x):
```cpp
struct memory_storage : storage_interface
{
    memory_storage(storage_params const& params, file_pool& pool);
    int readv(span<iovec_t const> bufs, piece_index_t piece, ...);
    int writev(span<iovec_t const> bufs, piece_index_t piece, ...);
};

storage_interface* memory_storage_constructor(storage_params const& params, file_pool& pool);
```

Required approach for 1.2.x:
```cpp
// Storage data holder (not inheriting from anything special)
struct memory_storage
{
    span<char const> readv(peer_request const r, storage_error& ec) const;
    void writev(span<char const> const b, piece_index_t piece, int offset);
    sha1_hash hash(piece_index_t piece, ...) const;
};

// Session-level disk I/O handler
struct memory_disk_io : disk_interface, buffer_allocator_interface
{
    storage_holder new_torrent(storage_params const& p, shared_ptr<void> const&) override;
    void remove_torrent(storage_index_t) override;
    void async_read(storage_index_t, peer_request const&, function<void(...)>) override;
    bool async_write(storage_index_t, peer_request const&, ...) override;
    void async_hash(storage_index_t, piece_index_t, ...) override;
    // ... many more async methods
};

// Factory function for session_params
unique_ptr<disk_interface> memory_disk_constructor(
    io_context& ioc, settings_interface const&, counters&);
```

### Key Differences

1. **Storage is now data-only**: The storage class holds data but doesn't implement I/O interface
2. **disk_interface does all I/O**: Single instance per session handles all torrents
3. **Async operations**: All operations use callbacks, not return values
4. **storage_index_t**: Torrents are identified by index, not pointer
5. **io_context integration**: Uses Boost.Asio for async operation posting

### Required Changes

#### 1. Rewrite as disk_interface

We need to completely rewrite the memory storage as a disk_interface implementation:

```cpp
struct memory_disk_io final : lt::disk_interface, lt::buffer_allocator_interface
{
    explicit memory_disk_io(lt::io_context& ioc);

    // Storage management
    lt::storage_holder new_torrent(lt::storage_params const& params,
                                   std::shared_ptr<void> const&) override;
    void remove_torrent(lt::storage_index_t) override;

    // Async I/O
    void async_read(lt::storage_index_t storage, lt::peer_request const& r,
                    std::function<void(lt::disk_buffer_holder, lt::storage_error const&)> handler,
                    lt::disk_job_flags_t) override;

    bool async_write(lt::storage_index_t storage, lt::peer_request const& r,
                     char const* buf, std::shared_ptr<lt::disk_observer> o,
                     std::function<void(lt::storage_error const&)> handler,
                     lt::disk_job_flags_t) override;

    // All other disk_interface methods...
};
```

#### 2. Update Session Creation

Instead of setting storage per-torrent, set disk I/O for session:

```go
// OLD (1.1.x) - Per-torrent storage
params := lt.NewAddTorrentParams()
params.SetMemoryStorage(memorySize)  // Sets storage constructor
session.AddTorrent(params)

// NEW (1.2.x) - Session-level disk I/O
sessionParams := lt.NewSessionParams()
sessionParams.SetDiskIOConstructor(memoryDiskConstructor)
session := lt.NewSession(sessionParams)
// All torrents will use memory disk I/O
```

#### 3. Handle Multiple Torrents

Since one disk_interface handles all torrents:
- Use `storage_index_t` to identify torrents
- Maintain map of storage_index_t → memory_storage
- Coordinate buffer sharing across torrents

### Implementation Effort

This is a **MAJOR rewrite**, not a simple update:

| Component | Effort | Description |
|-----------|--------|-------------|
| memory_disk_io class | HIGH | New class implementing disk_interface (~400 lines) |
| memory_storage class | MEDIUM | Simplify to data-only holder |
| SWIG interfaces | HIGH | New bindings for disk_interface |
| Elementum integration | HIGH | Change from per-torrent to session-level |
| Testing | HIGH | Completely new test approach |

**Estimated additional time: 1-2 weeks**

### Options

#### Option A: Full 1.2.x Rewrite

Completely rewrite to use disk_interface architecture.
- Pros: Modern architecture, better performance, future-proof
- Cons: Significant effort, more testing needed

#### Option B: Stay on 1.1.x Longer

Keep using libtorrent 1.1.x until 1.2.x rewrite is complete.
- Pros: Working code now, less risk
- Cons: Missing 5 years of bug fixes and improvements

#### Option C: Check if storage_interface Still Exists

Some backwards compatibility may exist in 1.2.x. Need to verify if old-style storage_interface is still supported.
- Pros: Less work if compatible
- Cons: May be deprecated and removed in 2.0.x

### Recommendation

1. **Immediate**: Verify if storage_interface exists in 1.2.x headers
2. **If exists**: Try building with current code, may work with deprecation warnings
3. **If not**: Plan for disk_interface rewrite before proceeding

### Files Affected

- `memory_storage.hpp` - Complete rewrite as disk_interface
- `add_torrent_params.i` - Remove storage setting
- `session.i` - Add disk_io_constructor
- Service initialization in Elementum
- All memory storage access patterns

### Reference Implementation

The system message includes a complete example of `temp_disk_io` implementing disk_interface. Use this as a template for our memory_disk_io implementation.

Key patterns:
- Store torrents in `aux::vector<unique_ptr<storage>, storage_index_t>`
- Free slots tracking for storage reuse
- Post callbacks via `io_context`
- Return `disk_buffer_holder` for reads
- Implement `buffer_allocator_interface::free_disk_buffer`

### Conclusion

**The storage architecture change is the most critical finding.** Our current implementation is based on the 1.1.x model which may not work in 1.2.x.

Before proceeding with any build attempts:
1. Verify storage_interface existence in 1.2.x
2. If not present, plan for complete disk_interface rewrite
3. Consider staying on 1.1.x while developing 1.2.x version in parallel
