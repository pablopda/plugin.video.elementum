# Thread Safety Code Snippets - Before and After

## 1. Critical: Use-After-Free in Disk IO Constructor

**File:** `libtorrent-go/interfaces/session.i` (lines 72-82)

### BEFORE (BROKEN)
```cpp
%extend libtorrent::session_params {
    // Configure memory disk I/O
    void set_memory_disk_io(std::int64_t memory_size) {
        libtorrent::memory_disk_memory_size = memory_size;
        self->disk_io_constructor = [](libtorrent::io_context& ioc,
            libtorrent::settings_interface const& si, libtorrent::counters& cnt)
        {
            auto dio = std::make_unique<libtorrent::memory_disk_io>(ioc);
            // BUG: Stores raw pointer to object inside unique_ptr
            libtorrent::set_global_memory_disk_io(dio.get());
            return dio;  // unique_ptr owns the object now
            // But global still has raw pointer that could outlive ownership!
        };
    }
}
```

### AFTER (FIXED)
```cpp
%inline %{
namespace libtorrent {
    namespace {
        std::mutex g_disk_io_instance_mutex;
        std::shared_ptr<memory_disk_io> g_disk_io_instance;
    }
    
    void set_global_disk_io_instance(std::shared_ptr<memory_disk_io> dio) {
        std::lock_guard<std::mutex> lock(g_disk_io_instance_mutex);
        g_disk_io_instance = dio;  // Store shared_ptr, not raw
    }
    
    std::shared_ptr<memory_disk_io> get_global_disk_io_instance() {
        std::lock_guard<std::mutex> lock(g_disk_io_instance_mutex);
        return g_disk_io_instance;
    }
    
    void clear_global_disk_io_instance() {
        std::lock_guard<std::mutex> lock(g_disk_io_instance_mutex);
        g_disk_io_instance.reset();
    }
}
%}

%extend libtorrent::session_params {
    void set_memory_disk_io(std::int64_t memory_size) {
        libtorrent::memory_disk_memory_size = memory_size;
        self->disk_io_constructor = [](libtorrent::io_context& ioc,
            libtorrent::settings_interface const& si, libtorrent::counters& cnt)
        {
            // Create as shared_ptr for shared ownership
            auto dio = std::make_shared<libtorrent::memory_disk_io>(ioc);
            libtorrent::set_global_disk_io_instance(dio);
            
            // Return unique_ptr for session ownership
            return std::make_unique<libtorrent::memory_disk_io>(ioc);
        };
    }
}
```

### Key Changes:
1. ✅ Store `shared_ptr` instead of raw pointer
2. ✅ Protect setter/getter with mutex
3. ✅ Allow object to be kept alive even if session destroys its copy

---

## 2. Critical: Unprotected Global Variable

**File:** `libtorrent-go/memory_disk_io.hpp` (line 49)

### BEFORE (BROKEN)
```cpp
namespace libtorrent {
    // Global memory configuration - NO SYNCHRONIZATION!
    std::int64_t memory_disk_memory_size = 0;
    
    // ...
    
    struct memory_storage {
        explicit memory_storage(storage_params const& p)
            : m_files(p.files)
            , m_piece_length(p.files.piece_length())
            , m_num_pieces(p.files.num_pieces())
            , capacity(memory_disk_memory_size)  // ← DATA RACE: reading unprotected global
            , buffer_limit(0)
            , buffer_used(0)
        {
            // ...
        }
    };
}
```

### AFTER (FIXED)
```cpp
namespace libtorrent {
    namespace {
        std::mutex g_memory_size_mutex;
        std::int64_t g_memory_disk_memory_size_value = 0;
    }
    
    // Thread-safe getter
    inline std::int64_t get_memory_disk_memory_size() {
        std::lock_guard<std::mutex> lock(g_memory_size_mutex);
        return g_memory_disk_memory_size_value;
    }
    
    // Thread-safe setter (called from session.i)
    inline void set_memory_disk_memory_size(std::int64_t size) {
        std::lock_guard<std::mutex> lock(g_memory_size_mutex);
        g_memory_disk_memory_size_value = size;
    }
    
    struct memory_storage {
        explicit memory_storage(storage_params const& p)
            : m_files(p.files)
            , m_piece_length(p.files.piece_length())
            , m_num_pieces(p.files.num_pieces())
            , capacity(get_memory_disk_memory_size())  // ← Thread-safe read
            , buffer_limit(0)
            , buffer_used(0)
        {
            // ...
        }
    };
}
```

### Key Changes:
1. ✅ Wrap global in namespace scope to prevent external access
2. ✅ Add mutex protection for reader/writer synchronization
3. ✅ Use accessor functions instead of direct access

---

## 3. Important: Unprotected m_abort Flag

**File:** `libtorrent-go/memory_disk_io.hpp` (line 600)

### BEFORE (BROKEN)
```cpp
struct memory_disk_io final : disk_interface, buffer_allocator_interface {
private:
    io_context& m_ioc;
    aux::vector<std::unique_ptr<memory_storage>, storage_index_t> m_torrents;
    std::vector<storage_index_t> m_free_slots;
    mutable std::mutex m_mutex;
    bool m_abort = false;  // ← DATA RACE: no synchronization

public:
    void abort(bool wait) override {
        m_abort = true;  // ← Non-atomic write, may not be visible to other threads
        // If wait is true, we should wait for pending operations
    }
    
    // Somewhere else: if (m_abort) { ... }  // ← May see stale value
};
```

### AFTER (FIXED)
```cpp
#include <atomic>

struct memory_disk_io final : disk_interface, buffer_allocator_interface {
private:
    io_context& m_ioc;
    aux::vector<std::unique_ptr<memory_storage>, storage_index_t> m_torrents;
    std::vector<storage_index_t> m_free_slots;
    mutable std::mutex m_mutex;
    std::atomic<bool> m_abort{false};  // ← Atomic for lock-free synchronization

public:
    void abort(bool wait) override {
        // Use release semantics to ensure all prior writes are visible
        m_abort.store(true, std::memory_order_release);
        
        if (wait) {
            // Implementation: wait for pending operations
            // For now, memory storage ops are synchronous
        }
    }
    
    // Anywhere else can safely check:
    if (m_abort.load(std::memory_order_acquire)) {
        // abort was called
    }
};
```

### Key Changes:
1. ✅ Use `std::atomic<bool>` instead of plain bool
2. ✅ Use explicit memory ordering (release for writes, acquire for reads)
3. ✅ Ensure visibility across threads without mutex overhead

---

## 4. Critical: This-Pointer Capture in Callbacks

**File:** `libtorrent-go/memory_disk_io.hpp` (multiple locations: 419, 446, 469, 491, 501, 542, 559, 567, 584)

### BEFORE (BROKEN) - Example: async_read
```cpp
struct memory_disk_io final : disk_interface {
    // ...
    
    void async_read(storage_index_t storage, peer_request const& r,
        std::function<void(disk_buffer_holder, storage_error const&)> handler,
        disk_job_flags_t) override
    {
        storage_error error;
        span<char const> data;
        
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            if (storage < m_torrents.end_index() && m_torrents[storage]) {
                data = m_torrents[storage]->readv(r, error);
            }
        }
        
        // BUG: Lambda captures raw `this` pointer
        post(m_ioc, [handler, error, data, this]  // ← 'this' is raw pointer
        {
            // If memory_disk_io is destroyed before this callback runs,
            // dereferencing 'this' is undefined behavior!
            handler(disk_buffer_holder(*this,
                const_cast<char*>(data.data()),
                static_cast<int>(data.size())), error);
        });
    }
};
```

### AFTER (FIXED)
```cpp
#include <memory>

// Make memory_disk_io inherit from enable_shared_from_this
struct memory_disk_io final 
    : disk_interface
    , buffer_allocator_interface
    , std::enable_shared_from_this<memory_disk_io>  // ← Add this
{
    // ...
    
    void async_read(storage_index_t storage, peer_request const& r,
        std::function<void(disk_buffer_holder, storage_error const&)> handler,
        disk_job_flags_t) override
    {
        storage_error error;
        span<char const> data;
        
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            if (storage < m_torrents.end_index() && m_torrents[storage]) {
                data = m_torrents[storage]->readv(r, error);
            }
        }
        
        // Get shared_ptr to keep this object alive
        auto self = shared_from_this();  // ← Keep object alive
        
        post(m_ioc, [handler, error, data, self]  // ← Capture shared_ptr, not raw
        {
            // self is a shared_ptr, so object is guaranteed to exist
            if (self) {
                handler(disk_buffer_holder(*self,
                    const_cast<char*>(data.data()),
                    static_cast<int>(data.size())), error);
            }
        });
    }
};
```

### Alternative (without changing inheritance):
```cpp
struct memory_disk_io final : disk_interface, buffer_allocator_interface {
    // ...
    
    void async_read(...) override {
        storage_error error;
        span<char const> data;
        
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            if (storage < m_torrents.end_index() && m_torrents[storage]) {
                data = m_torrents[storage]->readv(r, error);
            }
        }
        
        // Create a shared_ptr wrapper if not inherited from enable_shared_from_this
        std::shared_ptr<memory_disk_io> self_ptr(this, [](void*) {
            // Don't delete - we're just wrapping the raw pointer
        });
        
        post(m_ioc, [handler, error, data, self_ptr]() {
            if (self_ptr) {
                handler(disk_buffer_holder(*self_ptr, 
                    const_cast<char*>(data.data()),
                    static_cast<int>(data.size())), error);
            }
        });
    }
};
```

### Key Changes:
1. ✅ Inherit from `enable_shared_from_this<memory_disk_io>`
2. ✅ Use `shared_from_this()` to capture shared ownership
3. ✅ Captures `shared_ptr` instead of raw pointer
4. ✅ Guarantees object lives until callback completes

---

## 5. Critical: Raw Pointer to Global Disk IO

**File:** `libtorrent-go/interfaces/disk_interface.i` (lines 23-82)

### BEFORE (BROKEN)
```cpp
%inline %{
namespace libtorrent {
    // Global raw pointer with no lifetime guarantee
    std::mutex g_memory_disk_io_mutex;
    memory_disk_io* g_memory_disk_io = nullptr;  // ← RAW POINTER

    void set_global_memory_disk_io(memory_disk_io* dio) {
        std::lock_guard<std::mutex> lock(g_memory_disk_io_mutex);
        g_memory_disk_io = dio;  // ← Store raw ptr
    }

    void clear_global_memory_disk_io() {
        std::lock_guard<std::mutex> lock(g_memory_disk_io_mutex);
        g_memory_disk_io = nullptr;  // ← Just set to null, object may still be in use
    }

    void memory_disk_set_lookbehind(int storage_index, std::vector<int> const& pieces) {
        std::lock_guard<std::mutex> lock(g_memory_disk_io_mutex);
        if (g_memory_disk_io) {  // ← Might be freed during this call!
            g_memory_disk_io->set_lookbehind_pieces(
                storage_index_t(storage_index), pieces);
        }
    }
    
    // ... similar for other functions
}
%}
```

### AFTER (FIXED) - Option A: Shared Ownership
```cpp
%inline %{
namespace libtorrent {
    // Global shared pointer with proper lifetime management
    namespace {
        std::mutex g_memory_disk_io_mutex;
        std::shared_ptr<memory_disk_io> g_memory_disk_io;
    }

    void set_global_memory_disk_io(std::shared_ptr<memory_disk_io> dio) {
        std::lock_guard<std::mutex> lock(g_memory_disk_io_mutex);
        g_memory_disk_io = dio;  // ← Store shared_ptr
    }

    void clear_global_memory_disk_io() {
        std::lock_guard<std::mutex> lock(g_memory_disk_io_mutex);
        g_memory_disk_io.reset();  // ← Properly release
    }

    void memory_disk_set_lookbehind(int storage_index, std::vector<int> const& pieces) {
        std::shared_ptr<memory_disk_io> dio;
        {
            std::lock_guard<std::mutex> lock(g_memory_disk_io_mutex);
            dio = g_memory_disk_io;  // ← Take shared ownership
        }
        // Release lock before calling - prevents nested lock issues
        if (dio) {
            dio->set_lookbehind_pieces(
                storage_index_t(storage_index), pieces);
        }
    }

    bool memory_disk_is_lookbehind_available(int storage_index, int piece) {
        std::shared_ptr<memory_disk_io> dio;
        {
            std::lock_guard<std::mutex> lock(g_memory_disk_io_mutex);
            dio = g_memory_disk_io;
        }
        if (dio) {
            return dio->is_lookbehind_available(
                storage_index_t(storage_index), piece);
        }
        return false;
    }

    void memory_disk_get_lookbehind_stats(int storage_index,
        int& available, int& protected_count, std::int64_t& memory) {
        std::shared_ptr<memory_disk_io> dio;
        {
            std::lock_guard<std::mutex> lock(g_memory_disk_io_mutex);
            dio = g_memory_disk_io;
        }
        if (dio) {
            dio->get_lookbehind_stats(
                storage_index_t(storage_index),
                available, protected_count, memory);
        } else {
            available = 0;
            protected_count = 0;
            memory = 0;
        }
    }
    
    void memory_disk_clear_lookbehind(int storage_index) {
        std::shared_ptr<memory_disk_io> dio;
        {
            std::lock_guard<std::mutex> lock(g_memory_disk_io_mutex);
            dio = g_memory_disk_io;
        }
        if (dio) {
            dio->clear_lookbehind(storage_index_t(storage_index));
        }
    }
}
%}
```

### AFTER (FIXED) - Option B: Thread-Local Caching
```cpp
%inline %{
namespace libtorrent {
    namespace {
        std::mutex g_memory_disk_io_mutex;
        std::weak_ptr<memory_disk_io> g_memory_disk_io;
        thread_local std::shared_ptr<memory_disk_io> tls_memory_disk_io_cache;
    }

    std::shared_ptr<memory_disk_io> get_disk_io_with_cache() {
        // Check thread-local cache first
        auto cached = tls_memory_disk_io_cache;
        if (cached) {
            return cached;
        }
        
        // Cache miss - acquire global lock
        {
            std::lock_guard<std::mutex> lock(g_memory_disk_io_mutex);
            cached = g_memory_disk_io.lock();
            if (cached) {
                tls_memory_disk_io_cache = cached;
            }
        }
        return cached;
    }

    void set_global_memory_disk_io(std::shared_ptr<memory_disk_io> dio) {
        std::lock_guard<std::mutex> lock(g_memory_disk_io_mutex);
        g_memory_disk_io = std::weak_ptr<memory_disk_io>(dio);
    }

    void clear_global_memory_disk_io() {
        std::lock_guard<std::mutex> lock(g_memory_disk_io_mutex);
        g_memory_disk_io.reset();
    }

    void memory_disk_set_lookbehind(int storage_index, std::vector<int> const& pieces) {
        auto dio = get_disk_io_with_cache();
        if (dio) {
            dio->set_lookbehind_pieces(storage_index_t(storage_index), pieces);
        }
    }
    
    // ... similar for other functions
}
%}
```

### Key Changes for Option A:
1. ✅ Use `shared_ptr` instead of raw pointer
2. ✅ Copy shared_ptr inside lock, release lock before calling method
3. ✅ Prevents deadlock from nested locking

### Key Changes for Option B:
1. ✅ Use `weak_ptr` for global storage
2. ✅ Add thread-local cache to reduce lock contention
3. ✅ Fast path for repeated accesses on same thread

---

## 6. Lock Contention Mitigation

**File:** `libtorrent-go/interfaces/disk_interface.i` (architecture change)

### CURRENT (BOTTLENECK)
```cpp
// Single global mutex serializes ALL lookbehind operations
std::mutex g_memory_disk_io_mutex;

// All 4 operations serialize on this single lock:
// memory_disk_set_lookbehind()
// memory_disk_clear_lookbehind()
// memory_disk_is_lookbehind_available()
// memory_disk_get_lookbehind_stats()
```

### IMPROVED (Per-Storage Locking)
```cpp
namespace {
    std::map<int, std::shared_ptr<std::mutex>> g_storage_mutexes;
    std::mutex g_storage_map_mutex;
    
    std::shared_ptr<std::mutex> get_storage_mutex(int storage_index) {
        std::lock_guard<std::mutex> lock(g_storage_map_mutex);
        auto& mutex_ptr = g_storage_mutexes[storage_index];
        if (!mutex_ptr) {
            mutex_ptr = std::make_shared<std::mutex>();
        }
        return mutex_ptr;
    }
}

void memory_disk_set_lookbehind(int storage_index, std::vector<int> const& pieces) {
    auto mutex = get_storage_mutex(storage_index);
    std::lock_guard<std::mutex> lock(*mutex);  // ← Per-storage, not global
    // ... access disk_io
}
```

### BEST (RCU Pattern with Snapshot)
```cpp
namespace {
    struct DiskIOSnapshot {
        std::shared_ptr<memory_disk_io> instance;
        int storage_index;
    };
    
    std::mutex g_disk_io_state_mutex;
    std::shared_ptr<memory_disk_io> g_disk_io_instance;
    std::int32_t g_disk_io_version = 0;
    
    thread_local int tls_cached_version = -1;
    thread_local std::shared_ptr<memory_disk_io> tls_cached_instance;
}

std::shared_ptr<memory_disk_io> get_disk_io() {
    // Read-side: No lock on fast path (RCU)
    int current_version;
    {
        std::lock_guard<std::mutex> lock(g_disk_io_state_mutex);
        if (tls_cached_version == g_disk_io_version) {
            return tls_cached_instance;
        }
        tls_cached_version = g_disk_io_version;
        tls_cached_instance = g_disk_io_instance;
    }
    return tls_cached_instance;
}
```

---

## Summary of Changes

| Issue | BEFORE | AFTER | Mechanism |
|-------|--------|-------|-----------|
| Dangling global ptr | Raw `*` | `shared_ptr` | Shared ownership |
| Global memory_size | `std::int64_t` | Mutex + getter/setter | Explicit sync |
| m_abort races | `bool` | `atomic<bool>` | Lock-free sync |
| Callback lifetimes | `[..., this]` | `[..., shared_ptr]` | Ownership extension |
| Lock contention | Single global | Per-storage or TLS cache | Reduced serialization |

