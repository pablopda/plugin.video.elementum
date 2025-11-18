# Thread Safety Quick Reference - Libtorrent 2.0.x

## Critical Issues at a Glance

### Issue 1: Use-After-Free in Lambda (session.i:74-81)
```
┌─────────────────────────────────────────────────┐
│ CRITICAL: Raw pointer to unique_ptr ownership   │
├─────────────────────────────────────────────────┤
│ g_memory_disk_io = dio.get()                    │
│     ↑                                            │
│     └─ Points to object inside unique_ptr       │
│        If unique_ptr destroyed → DANGLING!      │
└─────────────────────────────────────────────────┘

Thread A: Go code calls GetLookbehind()
          ↓
          Acquires g_memory_disk_io_mutex
          ↓
          Dereferences g_memory_disk_io → SEGFAULT
          (if session already destroyed)
```

**Files Affected:**
- `/home/user/plugin.video.elementum/upgrade_2.0.x/libtorrent-go/interfaces/session.i` (lines 74-81)

---

### Issue 2: Unprotected Global (memory_disk_io.hpp:49)
```
┌──────────────────────────────────────────────┐
│ CRITICAL: Data race on global variable        │
├──────────────────────────────────────────────┤
│ std::int64_t memory_disk_memory_size = 0;    │
│ (no synchronization)                         │
│                                               │
│ Thread A: memory_disk_memory_size = 1GB      │
│ Thread B: memory_disk_memory_size = 2GB      │
│ Thread C: capacity = memory_disk_memory_size │
│           ↑ May read stale/torn value!       │
└──────────────────────────────────────────────┘
```

**Files Affected:**
- `/home/user/plugin.video.elementum/upgrade_2.0.x/libtorrent-go/memory_disk_io.hpp` (line 49)

---

### Issue 3: Dangling Global Pointer (disk_interface.i:29-42)
```
┌───────────────────────────────────────────┐
│ CRITICAL: No lifetime guarantee            │
├───────────────────────────────────────────┤
│ memory_disk_io* g_memory_disk_io;          │
│                                            │
│ Session destructor:                        │
│   unique_ptr<memory_disk_io> deleted       │
│   ↓ g_memory_disk_io still points to it! │
│   ↓ Go code still tries to use it         │
│   → USE-AFTER-FREE                        │
└───────────────────────────────────────────┘
```

**Files Affected:**
- `/home/user/plugin.video.elementum/upgrade_2.0.x/libtorrent-go/interfaces/disk_interface.i` (lines 29-42)

---

## Important Issues Summary

| Line | Issue | Impact | Fix |
|------|-------|--------|-----|
| session.i:79 | set_global_memory_disk_io(dio.get()) | Dangling ptr | Use shared_ptr |
| memory_disk_io.hpp:49 | Unprotected global | Data race | Add mutex |
| memory_disk_io.hpp:350 | m_abort unprotected | Data race | Use atomic<bool> |
| memory_disk_io.hpp:419+ | Capture `this` in lambda | Use-after-free | Use shared_ptr |
| disk_interface.i:45+ | g_memory_disk_io_mutex serialization | Bottleneck | Per-storage locks |

---

## Execution Flow - Thread Safety Issues

```
SCENARIO: Multi-threaded streaming with lookbehind buffer

Timeline:

T0: Go thread calls SetLookbehindPieces(storage=5, [1,2,3])
    ↓
    Enter memory_disk_set_lookbehind()
    ↓
    Acquire g_memory_disk_io_mutex ─────┐
                                         │
T1: Another Go thread calls             │
    GetLookbehindStats(storage=7)      │
    ↓                                   │
    Blocked on g_memory_disk_io_mutex ──┤ LOCK CONTENTION
    (waiting for T0)                    │
                                         │
T2: Session being destroyed (main thread)
    ↓
    Session destructor runs
    ↓
    unique_ptr<memory_disk_io> deleted  │
    ↓                                   │
    g_memory_disk_io = 0x0 (should be) │
    BUT: g_memory_disk_io still = old  │
         pointer until clear() is called│
                                         │
T3: T0 releases lock                   ├─
    ↓
    Returns with outdated pointer
    
    Pending callbacks still running in io_context
    ↓
    Call handler(disk_buffer_holder(*this, ...))
    ↓
    Dereference freed memory → CRASH!

```

---

## Per-File Issue Breakdown

### `/home/user/plugin.video.elementum/upgrade_2.0.x/libtorrent-go/memory_disk_io.hpp`

**Line 49**: `std::int64_t memory_disk_memory_size = 0;`
- ❌ NO synchronization
- ✅ Should be: `std::atomic<std::int64_t>` or protected by mutex

**Line 350**: `bool m_abort = false;`
- ❌ Data races possible
- ✅ Should be: `std::atomic<bool>`

**Lines 419, 446, 469, 491, 501, 542, 559, 567, 584**: Callbacks capture `this`
- ❌ Use-after-free if memory_disk_io destroyed
- ✅ Should use: `std::shared_ptr` via `enable_shared_from_this`

**Lines 285-298**: `set_lookbehind_pieces()` 
- ⚠️ Called with m_mutex held (OK)
- ❌ Internal bitset access not synchronized
- ✅ OK as long as only called from protected context

---

### `/home/user/plugin.video.elementum/upgrade_2.0.x/libtorrent-go/interfaces/session.i`

**Lines 72-82**: `set_memory_disk_io()` lambda
- ❌ Stores raw ptr to unique_ptr: `set_global_memory_disk_io(dio.get())`
- ❌ No guarantee clear() will be called
- ✅ Should: Transfer shared ownership

```cpp
// CURRENT (BROKEN):
auto dio = std::make_unique<libtorrent::memory_disk_io>(ioc);
libtorrent::set_global_memory_disk_io(dio.get());  // ← RAW PTR
return dio;

// FIXED:
auto dio = std::make_shared<libtorrent::memory_disk_io>(ioc);
{
    std::lock_guard lock(g_disk_io_factory_mutex);
    g_disk_io_instance = dio;  // ← SHARED OWNERSHIP
}
return dio;
```

---

### `/home/user/plugin.video.elementum/upgrade_2.0.x/libtorrent-go/interfaces/disk_interface.i`

**Lines 29-30**: Global variables
```cpp
std::mutex g_memory_disk_io_mutex;
memory_disk_io* g_memory_disk_io = nullptr;  // ← RAW PTR, NO OWNERSHIP
```
- ❌ No lifetime guarantee
- ✅ Should be: `std::shared_ptr<memory_disk_io>`

**Lines 45-82**: Wrapper functions
- ❌ All serialize on single mutex
- ⚠️ Performance bottleneck under high concurrency
- ✅ Consider: RCU pattern or thread-local caching

---

## Compilation Check

To verify thread safety improvements, compile with:

```bash
# Enable thread safety warnings
g++ -std=c++17 -Wall -Wthread-safety \
    -Watomic-properties \
    -Wliterals-with-mixed-signs \
    memory_disk_io.hpp

# Enable TSAN (Thread Sanitizer)
clang++ -std=c++17 -fsanitize=thread -g \
    memory_disk_io.hpp
```

---

## Testing Recommendations

### Test 1: Multiple Goroutines Accessing Lookbehind
```go
// Spawn 10 goroutines, each calling lookbehind operations
// Should not crash, even with concurrent access
```

### Test 2: Rapid Session Create/Destroy
```go
// Create/destroy session in loop
// Ensure no memory leaks or dangling pointers
```

### Test 3: Callbacks During Shutdown
```go
// Post async operations, then immediately destroy session
// Verify no use-after-free
```

### Test 4: TSAN Run
```bash
LD_PRELOAD=libtsan.so.0 go test -race ./...
```

---

## Patch Priority

1. **P0 - IMMEDIATE**: Fix raw pointer issues (issues 1, 3)
   - Use shared_ptr instead of raw ptrs
   - File: session.i, disk_interface.i

2. **P1 - URGENT**: Fix unprotected globals (issue 2, 5)
   - Protect memory_disk_memory_size
   - Make m_abort atomic
   - Files: memory_disk_io.hpp

3. **P2 - HIGH**: Fix callback lifetimes
   - Use shared_from_this() for 'this' captures
   - File: memory_disk_io.hpp

4. **P3 - MEDIUM**: Optimize lock contention
   - Consider per-storage mutexes or RCU
   - File: disk_interface.i

---

## External References

- C++ Memory Model: https://en.cppreference.com/w/cpp/thread/memory_model
- Boost ASIO: https://www.boost.org/doc/libs/1_80_0/doc/html/boost_asio.html
- Go/C++ FFI: https://golang.org/cmd/cgo/
- Thread Sanitizer: https://github.com/google/sanitizers/wiki/ThreadSanitizerCppManual

