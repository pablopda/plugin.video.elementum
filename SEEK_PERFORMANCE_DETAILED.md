# Elementum Seek/Rewind Performance - Detailed Technical Investigation

## 1. SEEK REQUEST FLOW - CODE TRACE

### Step 1: User Seeks in Kodi Player
Kodi native player handles the UI and sends seek request internally.

### Step 2: Python RPC Method - Player_Seek()

**FILE:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/rpc.py`
**LINES:** 286-292

```python
def Player_Seek(self, position):
    ret = ""
    try:
        XBMC_PLAYER.seekTime(position)  # ← Direct call to Kodi native seekTime
    except Exception as e:
        ret = repr(e)
    return ret
```

CRITICAL FINDING: This method does NOT communicate with the daemon at all. It only calls Kodi's native `seekTime()`. All actual seeking is handled by:
- Kodi's player engine
- HTTP Range requests to streaming server
- The daemon's piece selection and download prioritization

### Step 3: Playback Time Tracking - Player_WatchTimes()

**FILE:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/rpc.py`
**LINES:** 268-284

```python
def Player_WatchTimes(self):
    error = ""
    watchedTime = "0"
    videoDuration = "0"
    try:
        watchedTime = str(XBMC_PLAYER.getTime())         # Current position in seconds
        videoDuration = str(XBMC_PLAYER.getTotalTime())  # Total duration in seconds
        log.debug("Watched: %s, duration: %s" % (watchedTime, videoDuration))
    except Exception as e:
        error = "Stopped playing: %s" % repr(e)

    watchTimes = {
        "watchedTime": watchedTime,
        "videoDuration": videoDuration,
        "error": error
    }
    return watchTimes
```

This method is READ-ONLY - it just reports current position. Does not affect seeking.

### Step 4: Initial Stream Setup - Streaming URL Generation

**FILE:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/navigation.py`
**LINES:** 305-388 (run() function)

```python
def run(url_suffix="", retry=0):
    # Get buffer settings that affect playback
    try:
        buffer_timeout = int(ADDON.getSetting("buffer_timeout"))
        if buffer_timeout < 60:
            buffer_timeout = 60
    except:
        buffer_timeout = 60
    
    # CRITICAL: Timeout is doubled here!
    buffer_timeout = buffer_timeout * 2  # DEFAULT 60s becomes 120s
    
    # Set socket timeout for HTTP requests
    socket.setdefaulttimeout(buffer_timeout)
    
    # Get preload timeout for retry logic
    try:
        preload_timeout = int(ADDON.getSetting("preload_timeout"))
        if preload_timeout < 1:
            preload_timeout = 1
    except:
        preload_timeout = 1

    # ... HTTP opener setup ...
    
    # Convert plugin:// URL to http:// URL pointing to daemon
    url = sys.argv[0].replace("plugin://%s" % ADDON_ID, ELEMENTUMD_HOST + url_suffix) + encoded_url
    
    # Request streaming info from daemon
    try:
        data = _json(url)
    except PlayerException as e:
        # This exception signals HTTP 300 response
        redirect_url = e.__str__()
        log.debug("Launching player with %s" % (redirect_url))
        xbmcplugin.endOfDirectory(HANDLE, succeeded=True)
        xbmc.sleep(500)
        # Open streaming URL directly in Kodi player
        xbmc.executeJSONRPC('{"jsonrpc":"2.0","method":"Player.Open","params":{"item":{"file":"%s"}},"id":"1"}' % (redirect_url))
        return
    except RedirectException as e:
        # This exception signals HTTP 301 response (redirect)
        redirect_url = e.__str__()
        # This redirect contains the actual streaming URL
        log.debug("Redirecting Kodi with %s" % (redirect_url))
        xbmcplugin.endOfDirectory(HANDLE, succeeded=True)
        xbmc.sleep(500)
        xbmc.executebuiltin('Container.Update(%s)' % (redirect_url))
        return
```

CRITICAL PATH FOUND:
1. Python plugin constructs URL request to daemon at `http://127.0.0.1:65220`
2. Daemon responds with HTTP 300/301 containing streaming URL
3. Streaming URL is directly handed to Kodi player
4. Kodi player makes HTTP Range requests to daemon
5. **Daemon handles actual seeking via Range request responses**

### Step 5: HTTP Range Request Handling

When Kodi seeks, it sends:
```
GET /stream/torrentid/filename HTTP/1.1
Range: bytes=1234567-2345678
Host: 127.0.0.1:65220
```

The daemon must:
1. Parse the byte range
2. Map bytes to torrent piece indexes
3. Check if pieces are already cached
4. If not cached: download pieces from peers
5. Return the requested byte range

**This is where slowness occurs - in step 4!**

---

## 2. CONFIGURATION SETTINGS THAT AFFECT SEEK PERFORMANCE

### A. BUFFER SIZE SETTINGS

**FILE:** `/home/user/plugin.video.elementum/resources/settings.xml`
**LINES:** 154-158

```xml
<setting id="buffer_size" label="30578" type="number" default="20" />
<setting id="end_buffer_size" label="30577" type="number" default="4" />
<setting id="auto_kodi_buffer_size" label="30502" type="bool" default="true" />
<setting id="buffer_timeout" label="30088" type="slider" option="int" range="10,5,600" default="60" />
```

**Impact Analysis:**

| Setting | Default | Range | Impact on Seek |
|---------|---------|-------|---|
| `buffer_size` | 20 MB | N/A | Very significant - larger buffer = faster backward seeks within buffer |
| `end_buffer_size` | 4 MB | N/A | End-of-file buffer, less relevant for mid-stream seeking |
| `auto_kodi_buffer_size` | true | - | Should be enabled for Kodi's buffer detection |
| `buffer_timeout` | 60s | 10-600s | Doubled to 120s - timeout for buffering operations |

**RECOMMENDATION:** Users should increase `buffer_size` to 50-100 MB if they have memory available.

### B. MEMORY/CACHE SETTINGS

**FILE:** `/home/user/plugin.video.elementum/resources/settings.xml`
**LINES:** 22-35 (Storage Section, Memory Strategy)

```xml
<setting id="auto_memory_size" label="30376" type="bool" default="true" />
<setting id="memory_size" label="30318" type="number" default="100" />
<setting id="auto_adjust_memory_size" label="30499" type="bool" default="true" />
```

**Impact Analysis:**

| Setting | Default | Impact |
|---------|---------|--------|
| `auto_memory_size` | true | Automatically detect available memory |
| `memory_size` | 100 MB | Manual override if auto is disabled |
| `auto_adjust_memory_size` | true | Dynamically adjust during playback |

**RECOMMENDATION:** Keep auto-sizing enabled, or manually set to 200+ MB on systems with sufficient RAM.

### C. DISK CACHE SETTINGS

**FILE:** `/home/user/plugin.video.elementum/resources/settings.xml`
**LINES:** 200-201

```xml
<setting id="tuned_storage" label="30086" type="bool" default="true" />
<setting id="disk_cache_size" label="30597" type="number" enable="eq(-1,true)" default="12" />
```

**Impact Analysis:**

When using file-based storage instead of memory:
- `tuned_storage`: Enable for optimized file storage
- `disk_cache_size`: Disk cache in MB (default 12 MB) - very small!

**RECOMMENDATION:** If using disk storage, increase to 24-32 MB.

### D. DOWNLOAD STRATEGY SETTINGS

**FILE:** `/home/user/plugin.video.elementum/resources/settings.xml`
**LINE:** 37

```xml
<setting id="download_file_strategy" type="enum" label="30653" lvalues="30654|30655|30656" default="0" />
```

Controls how pieces are prioritized during download. The three options likely are:
- Sequential download
- Random download  
- Smart/adaptive download

**Impact:** For backward seeks, smart strategies perform better because they prioritize based on seek patterns.

### E. KEEP FILES ALIVE SETTINGS

**FILE:** `/home/user/plugin.video.elementum/resources/settings.xml`
**LINES:** 61-63

```xml
<setting id="keep_downloading" type="enum" label="30028" lvalues="30319|30320|30321" default="1" />
<setting id="keep_files_playing" type="enum" label="30312" lvalues="30309|30310|30311" default="1" />
<setting id="keep_files_finished" type="enum" label="30313" lvalues="30309|30310|30311" default="1" />
```

Controls whether torrent continues downloading during/after playback.

---

## 3. SOCKET TIMEOUT BEHAVIOR

**FILE:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/navigation.py`
**LINES:** 311-325

```python
# Configuration read from settings
try:
    buffer_timeout = int(ADDON.getSetting("buffer_timeout"))
    if buffer_timeout < 60:
        buffer_timeout = 60
except:
    buffer_timeout = 60

# CRITICAL: TIMEOUT IS DOUBLED
buffer_timeout = buffer_timeout * 2

# Applied to all socket operations
socket.setdefaulttimeout(buffer_timeout)
```

**Impact on Seeking:**

- Default setting: 60 seconds
- Actual timeout: 120 seconds
- If daemon takes > 120s to fetch pieces for a Range request, connection times out
- This can happen when:
  - Peers have low upload speed
  - Pieces are rare in the swarm
  - Network is congested
  - Daemon is overloaded with other requests

**Bottleneck Identified:**
If a backward seek requires fetching rare pieces, and peers can only provide 1-2 MB/s, a 100 MB piece set could take 50-100 seconds. The 120s timeout may be hit!

---

## 4. STREAMING SERVER ARCHITECTURE

```
┌─────────────────────────────────────────┐
│         Kodi Media Player               │
│   (Native, handles seeking)             │
└────────────────┬────────────────────────┘
                 │
         HTTP Range Requests
         GET /stream/...
         Range: bytes=X-Y
                 │
                 ▼
┌─────────────────────────────────────────┐
│    Elementum Daemon (Go binary)         │
│    TCP Port: 65220                      │
│                                         │
│  ┌─────────────────────────────┐       │
│  │  HTTP Server Module         │       │
│  │  - Handles Range requests   │       │
│  │  - Maps bytes to pieces     │       │
│  │  - Streams cached data      │       │
│  └────────────┬────────────────┘       │
│               │                         │
│  ┌────────────▼────────────────┐       │
│  │  Piece Manager              │       │
│  │  - Tracks downloaded pieces │       │
│  │  - Memory cache (100 MB)    │       │
│  │  - Disk cache (12 MB)       │       │
│  └────────────┬────────────────┘       │
│               │                         │
│  ┌────────────▼────────────────┐       │
│  │  Libtorrent Library         │       │
│  │  - Piece selection algo     │       │
│  │  - Peer connections         │       │
│  │  - Download prioritization  │       │
│  └────────────┬────────────────┘       │
│               │                         │
└───────────────┼─────────────────────────┘
                │
        TCP/UDP Connections
        to Torrent Peers
                │
                ▼
        (Remote Torrent Swarm)
```

**The Bottleneck is in the Daemon:**
When seeking backward, the daemon's libtorrent must re-prioritize piece downloads. This can be slow if:
1. Pieces aren't available locally
2. Pieces are rare in the swarm
3. Peers have limited upload capacity
4. Network connectivity is poor

---

## 5. SEEK PERFORMANCE BOTTLENECKS - DETAILED ANALYSIS

### BOTTLENECK 1: Backward Seek Piece Prioritization
**Severity:** CRITICAL

When user seeks backward:
- Current cached buffer likely only has forward-looking data
- Required pieces may be at start of file
- Libtorrent must change piece priorities and re-request from peers
- This causes "stalling" while pieces are fetched

**Default Settings Make This Worse:**
- `buffer_size: 20 MB` - very small lookback window
- `memory_size: 100 MB` - auto-adjusted, might be smaller
- Large files requiring backward seek beyond cached area = SLOW

**Solution:** Increase buffer_size and memory_size

### BOTTLENECK 2: Insufficient Pre-Buffering for Streaming
**Severity:** HIGH

Current libtorrent configuration pre-buffers ahead, but:
- Doesn't pre-buffer backward
- Doesn't anticipate seeking patterns
- No "read-ahead" in reverse direction

**Why It Matters:**
Users often rewind to re-watch content. Optimal behavior would pre-buffer backward, but this doesn't happen.

### BOTTLENECK 3: Torrent Swarm Health
**Severity:** HIGH

Backward seeks depend on peer availability:
- If earlier pieces are rare (few peers have them), seeking is slow
- Popular streams might not have seeders for entire file
- VPN/proxy users may have worse peer connectivity

**Solution:** None at plugin level - user must improve network/swarm health

### BOTTLENECK 4: HTTP Range Request Handling
**Severity:** MEDIUM

The daemon must:
1. Parse HTTP Range header
2. Convert byte range to piece indices
3. Check cache
4. Fetch missing pieces
5. Serve them in order

If pieces need fetching, steps 3-5 are serial and slow.

### BOTTLENECK 5: Socket Timeout Sensitivity
**Severity:** MEDIUM

Timeout set to 120s (doubled from 60s setting):
- Sufficient for normal buffering
- Marginal for slow networks + rare pieces
- Could fail if daemon is unresponsive

**Risk:** Large backward seeks on slow networks might timeout!

---

## 6. CONFIGURATION RECOMMENDATIONS

### For Users Experiencing Slow Rewinds:

**TIER 1 - Easy Changes:**
```
Settings > BitTorrent:
- buffer_size: Change from 20 MB → 50 MB (or higher)
- buffer_timeout: Change from 60s → 120s
- auto_kodi_buffer_size: Ensure it's TRUE

Settings > Storage:
- auto_memory_size: Ensure it's TRUE
- memory_size: If auto disabled, set to 200+ MB
```

**TIER 2 - Advanced Changes:**
```
Settings > Storage:
- download_file_strategy: Try different strategies
- disk_cache_size: If using files, increase to 24+ MB

Settings > Download:
- keep_files_playing: Set to "Keep downloading"
- autoyes_enabled: Set to TRUE for auto-selection
```

**TIER 3 - System Level:**
```
- Increase available RAM on device
- Ensure reliable network connection
- Use wired connection instead of WiFi
- Disable VPN if experiencing issues
- Check torrent swarm health
```

---

## 7. PERFORMANCE MONITORING

### Check These Logs:

**Kodi Log:** `~/.kodi/logs/kodi.log`
- Look for network errors during seeks
- Check for HTTP timeout messages

**Elementum Log:** (Location varies by platform)
- Check for piece download errors
- Monitor peer connections
- Track cache hit/miss rates

### Monitor These Metrics:

1. **Seek Latency:** Time from seek request to playback resume
2. **Piece Fetch Rate:** Pieces/second during seek recovery
3. **Cache Hit Rate:** Percentage of seeks fulfilled from cache
4. **Peer Availability:** Number of peers with required pieces

---

## 8. CODE LOCATIONS - QUICK REFERENCE

| Component | File | Lines | Purpose |
|-----------|------|-------|---------|
| **Seek Handler** | `rpc.py` | 286-292 | Delegates to Kodi's seekTime() |
| **Position Tracker** | `rpc.py` | 268-284 | Reports current playback position |
| **Socket Setup** | `navigation.py` | 311-325 | Sets timeout for HTTP connections |
| **Stream URL Gen** | `navigation.py` | 350-388 | Gets streaming URL from daemon |
| **HTTP Redirect** | `navigation.py` | 193-266 | Handles daemon redirects |
| **Buffer Settings** | `settings.xml` | 154-158 | All buffer-related configurations |
| **Memory Settings** | `settings.xml` | 22-35 | Cache and memory configuration |
| **Download Strategy** | `settings.xml` | 37 | Piece prioritization method |
| **Service Init** | `service.py` | 1-37 | Starts daemon and RPC server |
| **Daemon Launch** | `daemon.py` | 306-500 | Starts Go daemon binary |

---

## 9. CONCLUSION

The **rewind/seek slowness is primarily a daemon-level issue** related to how the Go binary's libtorrent integration handles piece selection and download prioritization during backward seeks.

**Python Plugin Limitations:**
- Does NOT directly handle seeking
- Only provides buffer size and timeout configuration
- Cannot influence piece selection algorithms
- Cannot pre-emptively buffer backward

**To Fix This Issue:**
1. Users should increase buffer_size and memory_size settings
2. Daemon developers should optimize piece selection for seek patterns
3. Network/swarm quality directly impacts performance
4. No quick fix at Python layer - must be daemon optimization

**If This Is Still Slow After Configuration:**
- Issue is in elementum daemon (Go code)
- May require changes to libtorrent integration
- Check daemon logs in Elementum repository
- Consider upgrading to latest daemon binary

