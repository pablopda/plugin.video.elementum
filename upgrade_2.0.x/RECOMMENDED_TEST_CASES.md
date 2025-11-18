# RECOMMENDED TEST CASES FOR IMPLEMENTATION
## Priority Testing Guide for libtorrent 2.0.x Upgrade

---

## 1. BLOCKING CRITICAL TESTS (Implement First - Week 1)

### A. Concurrent Session Creation Race Condition
**File**: `tests/concurrency_test.go` (NEW)
**Severity**: CRITICAL
**Lines of Test Code**: ~50

```go
func TestConcurrentSessionCreation(t *testing.T) {
    // Reproduce the global pointer race condition
    const numSessions = 5
    sessions := make([]*lt.Session, numSessions)
    
    // Create sessions concurrently
    for i := 0; i < numSessions; i++ {
        go func(index int) {
            settings := lt.NewSettingsPack()
            params := lt.NewSessionParams()
            params.SetSettings(settings)
            params.SetMemoryDiskIO(50 * 1024 * 1024)
            
            session, err := lt.CreateSessionWithParams(params)
            if err != nil {
                t.Errorf("Failed to create session %d: %v", index, err)
            }
            sessions[index] = session
        }(i)
    }
    
    // Cleanup
    for _, session := range sessions {
        if session != nil {
            lt.DeleteSession(session)
        }
    }
    
    // VERIFY: If test crashes or hangs, global pointer bug exists
}
```

**What It Tests**:
- Multiple sessions with global g_memory_disk_io pointer
- Concurrent writes to global pointer
- Each session should have isolated memory_disk_io
- If fails: CRITICAL bug preventing multi-session usage

**Run With**:
```bash
go test -race ./... -run TestConcurrentSessionCreation -v
```

---

### B. Lookbehind UpdatePosition Core Functionality
**File**: `tests/lookbehind_test.go` (NEW)
**Severity**: CRITICAL
**Lines of Test Code**: ~100

```go
func TestLookbehindUpdatePosition(t *testing.T) {
    // Test the core streaming feature
    config := &bittorrent.LookbehindConfig{
        BufferSize: 5,
        MinBuffer:  3,
        Enabled:    true,
    }
    
    // Create mock torrent
    torrent := &bittorrent.Torrent{
        // ... mock fields
    }
    
    mgr := bittorrent.NewLookbehindManager(torrent, config)
    
    // Test 1: Update position forward
    mgr.UpdatePosition(10)
    protected := mgr.GetProtectedPieces()
    if len(protected) != 5 { // Should protect pieces 5-9
        t.Errorf("Expected 5 pieces, got %d", len(protected))
    }
    if protected[0] != 5 || protected[4] != 9 {
        t.Errorf("Protected pieces incorrect: %v", protected)
    }
    
    // Test 2: Update position again
    mgr.UpdatePosition(15)
    protected = mgr.GetProtectedPieces()
    if len(protected) != 5 { // Should protect pieces 10-14
        t.Errorf("Expected 5 pieces, got %d", len(protected))
    }
    
    // Test 3: Clear lookbehind
    mgr.Clear()
    protected = mgr.GetProtectedPieces()
    if len(protected) != 0 {
        t.Errorf("Expected 0 pieces after clear, got %d", len(protected))
    }
}
```

**What It Tests**:
- Protected pieces calculated correctly
- Buffer size respected
- Pieces advance as position moves
- Clear actually empties protected list

**Expected Outcome**: Verifies lookbehind math is correct

---

### C. Service AddTorrent Basic Path
**File**: `tests/service_test.go` (NEW)
**Severity**: CRITICAL
**Lines of Test Code**: ~80

```go
func TestServiceAddTorrent(t *testing.T) {
    config := &bittorrent.ServiceConfig{
        DownloadPath:     t.TempDir(),
        TorrentsPath:     t.TempDir(),
        MemorySize:       100 * 1024 * 1024,
        ConnectionsLimit: 200,
    }
    
    service, err := bittorrent.NewBTService(config)
    if err != nil {
        t.Fatalf("Failed to create service: %v", err)
    }
    defer service.Close()
    
    // Test adding a torrent
    // NOTE: This test assumes we can create a valid torrent file or magnet
    torrentHash := "0123456789abcdef0123456789abcdef01234567"
    
    torrent, err := service.AddTorrent(
        "magnet:?xt=urn:btih:"+torrentHash,
        config.DownloadPath,
    )
    
    if err != nil {
        // Check if error is expected or a real failure
        t.Errorf("AddTorrent failed: %v", err)
    }
    
    if torrent == nil && err == nil {
        t.Error("AddTorrent returned nil torrent with no error")
    }
    
    // Verify torrent was tracked
    retrieved := service.GetTorrent(torrentHash)
    if torrent != nil && retrieved == nil {
        t.Error("Added torrent not found in service")
    }
}
```

**What It Tests**:
- Service initialization
- AddTorrent basic flow
- Torrent tracking in service
- Error handling for failures

**Expected Outcome**: Confirms torrent add/tracking works

---

## 2. HIGH PRIORITY TESTS (Week 2)

### D. Lookbehind Buffer Edge Cases
**File**: `tests/lookbehind_test.go`
**Severity**: HIGH
**Lines of Test Code**: ~120

Test cases for:
- Piece < 0 (should clamp to 0)
- Piece > total_pieces (should handle gracefully)
- Buffer size > total pieces (all pieces protected)
- Buffer size = 0 (no protection)
- Buffer size = 1 (single piece)
- Rapid position updates (stress test)

```go
func TestLookbehindBoundaryConditions(t *testing.T) {
    tests := []struct {
        name         string
        position     int
        bufferSize   int
        expectedMin  int
        expectedMax  int
    }{
        {"Negative position", -5, 5, 0, 0},
        {"Zero position", 0, 5, 0, 0},
        {"Small position small buffer", 5, 3, 2, 4},
        {"Large position", 1000, 10, 990, 999},
        {"Buffer larger than position", 5, 20, 0, 4},
    }
    
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            config := &bittorrent.LookbehindConfig{
                BufferSize: tt.bufferSize,
                Enabled:    true,
            }
            mgr := bittorrent.NewLookbehindManager(nil, config)
            mgr.UpdatePosition(tt.position)
            
            protected := mgr.GetProtectedPieces()
            if len(protected) > 0 {
                if protected[0] != tt.expectedMin {
                    t.Errorf("Expected min %d, got %d", tt.expectedMin, protected[0])
                }
                if protected[len(protected)-1] != tt.expectedMax {
                    t.Errorf("Expected max %d, got %d", tt.expectedMax, protected[len(protected)-1])
                }
            }
        })
    }
}
```

---

### E. Service RemoveTorrent Cleanup
**File**: `tests/service_test.go`
**Severity**: HIGH
**Lines of Test Code**: ~70

```go
func TestServiceRemoveTorrent(t *testing.T) {
    config := &bittorrent.ServiceConfig{
        DownloadPath:     t.TempDir(),
        TorrentsPath:     t.TempDir(),
        MemorySize:       100 * 1024 * 1024,
        ConnectionsLimit: 200,
    }
    
    service, err := bittorrent.NewBTService(config)
    if err != nil {
        t.Fatalf("Failed to create service: %v", err)
    }
    defer service.Close()
    
    // Add torrent first
    torrentHash := "0123456789abcdef0123456789abcdef01234567"
    torrent, _ := service.AddTorrent(
        "magnet:?xt=urn:btih:"+torrentHash,
        config.DownloadPath,
    )
    if torrent == nil {
        t.Skip("Cannot test remove - add failed")
    }
    
    // Verify torrent exists
    if retrieved := service.GetTorrent(torrentHash); retrieved == nil {
        t.Error("Added torrent not found before remove")
    }
    
    // Remove torrent
    err = service.RemoveTorrent(torrentHash, false)
    if err != nil {
        t.Errorf("RemoveTorrent failed: %v", err)
    }
    
    // Verify torrent is gone
    if retrieved := service.GetTorrent(torrentHash); retrieved != nil {
        t.Error("Removed torrent still accessible")
    }
}
```

---

### F. Info Hash v1/v2 Type Handling
**File**: `tests/info_hash_test.go` (NEW)
**Severity**: HIGH
**Lines of Test Code**: ~100

```go
func TestInfoHashV1V2Handling(t *testing.T) {
    // Test v1-only torrent
    params := lt.NewAddTorrentParams()
    params.SetInfoHashV1("0123456789abcdef0123456789abcdef01234567")
    
    hashes := params.GetInfoHashes()
    if !hashes.HasV1() {
        t.Error("Expected v1 hash to be present")
    }
    if hashes.HasV2() {
        t.Error("Unexpected v2 hash")
    }
    
    // Test hybrid torrent (v1 and v2)
    params2 := lt.NewAddTorrentParams()
    params2.SetInfoHashV1("0123456789abcdef0123456789abcdef01234567")
    params2.SetInfoHashV2("abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789")
    
    hashes2 := params2.GetInfoHashes()
    if !hashes2.HasV1() || !hashes2.HasV2() {
        t.Error("Expected hybrid torrent to have both v1 and v2")
    }
    if !hashes2.IsHybrid() {
        t.Error("IsHybrid() should return true")
    }
}

func TestInfoHashStringConversions(t *testing.T) {
    // Test ToString() returns v1 for compatibility
    params := lt.NewAddTorrentParams()
    v1 := "fedcba9876543210fedcba9876543210fedcba98"
    params.SetInfoHashV1(v1)
    
    hashes := params.GetInfoHashes()
    if hashes.ToString() != v1 {
        t.Errorf("ToString() mismatch: expected %s, got %s", 
                 v1, hashes.ToString())
    }
    if hashes.V1Hex() != v1 {
        t.Errorf("V1Hex() mismatch: expected %s, got %s",
                 v1, hashes.V1Hex())
    }
}
```

---

### G. Error Handling: Invalid Inputs
**File**: `tests/error_handling_test.go` (NEW)
**Severity**: HIGH
**Lines of Test Code**: ~150

```go
func TestAddTorrentWithInvalidInputs(t *testing.T) {
    config := &bittorrent.ServiceConfig{
        DownloadPath:     t.TempDir(),
        TorrentsPath:     t.TempDir(),
        MemorySize:       100 * 1024 * 1024,
        ConnectionsLimit: 200,
    }
    
    service, _ := bittorrent.NewBTService(config)
    defer service.Close()
    
    tests := []struct {
        name   string
        uri    string
        path   string
        expect error
    }{
        {"Empty URI", "", config.DownloadPath, io.EOF}, // or similar
        {"Invalid magnet", "magnet:?invalid", config.DownloadPath, nil},
        {"Invalid path", "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567", 
         "/nonexistent/path/that/wont/exist", os.ErrNotExist},
    }
    
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            _, err := service.AddTorrent(tt.uri, tt.path)
            if tt.expect != nil && err == nil {
                t.Errorf("Expected error for %s", tt.name)
            }
        })
    }
}

func TestSessionWithInvalidMemorySize(t *testing.T) {
    tests := []int64{
        -1,      // Negative
        0,       // Zero
        1,       // Too small
    }
    
    for _, memSize := range tests {
        t.Run(fmt.Sprintf("MemorySize=%d", memSize), func(t *testing.T) {
            settings := lt.NewSettingsPack()
            params := lt.NewSessionParams()
            params.SetSettings(settings)
            params.SetMemoryDiskIO(memSize)
            
            session, err := lt.CreateSessionWithParams(params)
            if err != nil {
                t.Logf("Expected behavior: %v", err)
            }
            if session != nil {
                lt.DeleteSession(session)
            }
        })
    }
}
```

---

## 3. MEDIUM PRIORITY TESTS (Week 3-4)

### H. Concurrent Torrent Operations
**File**: `tests/concurrency_test.go`
**Severity**: MEDIUM
**Lines of Test Code**: ~120

```go
func TestConcurrentAddRemoveTorrents(t *testing.T) {
    config := &bittorrent.ServiceConfig{
        DownloadPath:     t.TempDir(),
        TorrentsPath:     t.TempDir(),
        MemorySize:       200 * 1024 * 1024,
        ConnectionsLimit: 200,
    }
    
    service, _ := bittorrent.NewBTService(config)
    defer service.Close()
    
    const numTorrents = 20
    hashes := make([]string, numTorrents)
    
    // Generate hashes
    for i := 0; i < numTorrents; i++ {
        hashes[i] = fmt.Sprintf("%040x", i)
    }
    
    // Concurrent add
    var wg sync.WaitGroup
    for i := 0; i < numTorrents; i++ {
        wg.Add(1)
        go func(idx int) {
            defer wg.Done()
            uri := fmt.Sprintf("magnet:?xt=urn:btih:%s", hashes[idx])
            _, _ = service.AddTorrent(uri, config.DownloadPath)
        }(i)
    }
    wg.Wait()
    
    // Verify all added
    count := 0
    for i := 0; i < numTorrents; i++ {
        if service.GetTorrent(hashes[i]) != nil {
            count++
        }
    }
    if count == 0 {
        t.Skip("None of the torrents were added (AddTorrent not fully implemented)")
    }
    
    // Concurrent remove
    for i := 0; i < numTorrents; i++ {
        wg.Add(1)
        go func(idx int) {
            defer wg.Done()
            service.RemoveTorrent(hashes[idx], false)
        }(i)
    }
    wg.Wait()
    
    // Verify all removed
    for i := 0; i < numTorrents; i++ {
        if service.GetTorrent(hashes[i]) != nil {
            t.Errorf("Torrent %d still exists after removal", i)
        }
    }
}
```

---

### I. Session State Save/Load
**File**: `tests/session_test.go` (NEW)
**Severity**: MEDIUM
**Lines of Test Code**: ~100

```go
func TestSessionStatePersistenceRoundTrip(t *testing.T) {
    // Create first session with configuration
    settings1 := lt.NewSettingsPack()
    settings1.SetInt("connections_limit", 250)
    settings1.SetStr("user_agent", "TestAgent/2.0")
    
    params1 := lt.NewSessionParams()
    params1.SetSettings(settings1)
    
    session1, err := lt.CreateSessionWithParams(params1)
    if err != nil {
        t.Fatalf("Failed to create session: %v", err)
    }
    
    // Save state
    savedState, err := session1.SaveSessionState()
    if err != nil {
        t.Fatalf("Failed to save state: %v", err)
    }
    lt.DeleteSession(session1)
    
    // Restore state in new session
    params2, err := lt.RestoreSessionState(savedState)
    if err != nil {
        t.Fatalf("Failed to restore state: %v", err)
    }
    
    session2, err := lt.CreateSessionWithParams(params2)
    if err != nil {
        t.Fatalf("Failed to create restored session: %v", err)
    }
    defer lt.DeleteSession(session2)
    
    // Verify settings preserved
    settings2 := params2.GetSettings()
    if settings2.GetInt("connections_limit") != 250 {
        t.Error("connections_limit not preserved")
    }
}
```

---

### J. Torrent Priority Operations
**File**: `tests/torrent_test.go` (NEW)
**Severity**: MEDIUM
**Lines of Test Code**: ~100

```go
func TestTorrentPrioritySetting(t *testing.T) {
    // NOTE: Requires actual torrent to test properly
    // This is a skeleton test
    
    config := &bittorrent.ServiceConfig{
        DownloadPath:     t.TempDir(),
        TorrentsPath:     t.TempDir(),
        MemorySize:       100 * 1024 * 1024,
        ConnectionsLimit: 200,
    }
    
    service, _ := bittorrent.NewBTService(config)
    defer service.Close()
    
    // If we had a torrent:
    // torrent := service.GetTorrent(hash)
    // torrent.SetPiecePriority(0, 7) // High priority
    // priority := torrent.GetPiecePriority(0)
    // if priority != 7 {
    //     t.Error("Piece priority not set correctly")
    // }
}
```

---

## 4. INFRASTRUCTURE TESTS (Week 4-5)

### K. Memory Leak Detection
**Requires**: pprof, runtime.MemStats
**Lines of Test Code**: ~150

```go
func TestSessionMemoryLeaks(t *testing.T) {
    if testing.Short() {
        t.Skip("Skipping memory test in short mode")
    }
    
    var m1, m2 runtime.MemStats
    runtime.ReadMemStats(&m1)
    
    // Create and destroy many sessions
    for i := 0; i < 100; i++ {
        settings := lt.NewSettingsPack()
        params := lt.NewSessionParams()
        params.SetSettings(settings)
        params.SetMemoryDiskIO(50 * 1024 * 1024)
        
        session, _ := lt.CreateSessionWithParams(params)
        if session != nil {
            lt.DeleteSession(session)
        }
    }
    
    runtime.GC()
    runtime.ReadMemStats(&m2)
    
    // Check memory didn't grow excessively
    memGrowth := m2.Alloc - m1.Alloc
    if memGrowth > 10*1024*1024 { // 10 MB threshold
        t.Errorf("Excessive memory growth: %d bytes", memGrowth)
    }
}
```

---

### L. Race Detector Compliance
**File**: `tests/race_test.go` (NEW)
**Run With**: `go test -race ./...`
**Lines of Test Code**: ~100

```go
func TestRaceOnLookbehindManager(t *testing.T) {
    config := &bittorrent.LookbehindConfig{
        BufferSize: 10,
        Enabled:    true,
    }
    
    mgr := bittorrent.NewLookbehindManager(nil, config)
    
    // Concurrent reads and writes
    var wg sync.WaitGroup
    for i := 0; i < 10; i++ {
        wg.Add(3)
        
        // Reader
        go func(idx int) {
            defer wg.Done()
            for j := 0; j < 100; j++ {
                _ = mgr.GetProtectedPieces()
            }
        }(i)
        
        // Writer
        go func(idx int) {
            defer wg.Done()
            for j := 0; j < 100; j++ {
                mgr.UpdatePosition(idx*10 + j)
            }
        }(i)
        
        // Config modifier
        go func(idx int) {
            defer wg.Done()
            for j := 0; j < 10; j++ {
                mgr.SetBufferSize(5 + j)
            }
        }(i)
    }
    
    wg.Wait()
    // If there are data races, race detector will fail the test
}
```

---

## 5. ESTIMATED TESTING TIMELINE

### Week 1: Critical Path Tests
- [ ] TestConcurrentSessionCreation
- [ ] TestLookbehindUpdatePosition
- [ ] TestServiceAddTorrent
- **Goal**: Verify no crashes on basic operations

### Week 2: High Priority Features
- [ ] TestLookbehindBoundaryConditions
- [ ] TestServiceRemoveTorrent
- [ ] TestInfoHashV1V2Handling
- [ ] TestAddTorrentWithInvalidInputs
- **Goal**: Feature correctness and error handling

### Week 3-4: Concurrency & Integration
- [ ] TestConcurrentAddRemoveTorrents
- [ ] TestSessionStatePersistenceRoundTrip
- [ ] TestTorrentPrioritySetting
- [ ] Full integration tests
- **Goal**: Multi-operation reliability

### Week 4-5: Infrastructure & Quality
- [ ] Memory leak detection
- [ ] Race detector compliance
- [ ] Performance benchmarking
- [ ] Coverage reporting
- **Goal**: Production readiness

---

## 6. HOW TO RUN TESTS

### Run all tests:
```bash
cd /home/user/plugin.video.elementum/upgrade_2.0.x
go test ./tests -v
```

### Run with race detector:
```bash
go test -race ./tests -v
```

### Run specific test:
```bash
go test ./tests -run TestConcurrentSessionCreation -v
```

### Generate coverage:
```bash
go test ./tests -cover -coverprofile=coverage.out
go tool cover -html=coverage.out -o coverage.html
```

### Run benchmarks:
```bash
go test -bench=. -benchmem ./tests
```

---

## 7. SUCCESS CRITERIA

Tests are successful when:
1. ✓ All tests pass consistently
2. ✓ `go test -race` passes with zero race detector warnings
3. ✓ Memory usage is stable (no leaks)
4. ✓ Error paths properly handled
5. ✓ Code coverage > 80%
6. ✓ All critical paths exercised
7. ✓ Integration tests verify full workflows

---

## 8. ESTIMATED IMPLEMENTATION EFFORT

| Category | Tests | LOC | Effort |
|----------|-------|-----|--------|
| Critical | 3 | 230 | 1 week |
| High Priority | 4 | 440 | 1 week |
| Medium Priority | 3 | 320 | 1 week |
| Infrastructure | 2 | 250 | 1 week |
| **Total** | **12+** | **1,240+** | **4 weeks** |

---

**Next Steps**:
1. Implement critical tests first (Week 1)
2. Fix any bugs discovered
3. Continue with high priority tests
4. Ensure race detector compliance
5. Generate coverage report
6. Integrate into CI/CD pipeline

