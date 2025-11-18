# Elementum Kodi Plugin - Rewind/Seek Performance Analysis

## Executive Summary

The Elementum Kodi plugin is experiencing **slow rewind/seek performance** during video streaming. After a thorough investigation of the codebase, the issue is primarily a **daemon-side problem** (Go binary), as the Python plugin layer is extremely thin and merely acts as a wrapper/RPC client. However, there are configuration options in the plugin that directly impact seek performance.

## Architecture Overview

The plugin uses a **client-server architecture**:

```
Kodi Player (User seeks) 
    ↓
Kodi Native API (seekTime)
    ↓ (HTTP Range Requests)
Elementum Daemon (Port 65220) ← Streams torrent data with HTTP range support
    ↓
Libtorrent Library ← Downloads torrent pieces on-demand
```

### Key Components

1. **Kodi Python Plugin** (`plugin.video.elementum`) - UI and RPC wrapper
2. **Elementum Daemon** (Go binary) - Torrent downloading and HTTP streaming server
3. **Libtorrent-go** - Cross-compiled libtorrent library

## Seek/Rewind Flow

### 1. User Initiates Seek in Kodi Player

### 2. Kodi Calls Player_Seek RPC Method

**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/rpc.py`
**Lines:** 286-292

```python
def Player_Seek(self, position):
    ret = ""
    try:
        XBMC_PLAYER.seekTime(position)
    except Exception as e:
        ret = repr(e)
    return ret
```

This method simply delegates to Kodi's native `seekTime()` method. It does NOT directly communicate with the daemon about seeking.

### 3. Kodi Player Makes HTTP Range Requests

When Kodi seeks, it makes **HTTP Range requests** to the streaming server:

```
GET /stream/... HTTP/1.1
Range: bytes=1234567-2345678
```

The streaming server is the **Elementum Daemon** running on `http://127.0.0.1:65220` (configurable in settings).

### 4. Daemon Fetches Required Torrent Pieces

When receiving a Range request, the daemon must:
1. Calculate which torrent pieces are needed
2. Download those pieces (if not already cached)
3. Stream the data back to Kodi player

## Configuration Options Affecting Seek Performance

All of these settings are in `/home/user/plugin.video.elementum/resources/settings.xml`:

### A. Buffer Settings (BitTorrent Category)

**Lines 154-158** in `settings.xml`:

```xml
<setting id="buffer_size" label="30578" type="number" default="20" />
<setting id="end_buffer_size" label="30577" type="number" default="4" />
<setting id="auto_kodi_buffer_size" label="30502" type="bool" default="true" />
<setting id="buffer_timeout" label="30088" type="slider" option="int" range="10,5,600" default="60" />
```

**Impact on Seeks:**
- `buffer_size` (MB): Pieces downloaded ahead of playback position. **Directly affects seek time** - backward seeks are slow because less data is already cached
- `end_buffer_size` (MB): Buffer at the end of file
- `auto_kodi_buffer_size`: Whether to use Kodi's native buffer size detection
- `buffer_timeout` (seconds): How long to wait for buffering before starting playback (doubled in code to 120s default)

### B. Download Strategy

**Line 37** in `settings.xml`:

```xml
<setting id="download_file_strategy" type="enum" label="30653" lvalues="30654|30655|30656" default="0" />
```

This controls how pieces are prioritized when downloading. It affects which pieces are fetched when seeking.

### C. Storage Settings

**Lines 22-35** in `settings.xml`:

```xml
<setting id="auto_memory_size" label="30376" type="bool" default="true" />
<setting id="memory_size" label="30318" type="number" default="100" />
<setting id="auto_adjust_memory_size" label="30499" type="bool" default="true" />
```

Memory size directly affects how much can be cached. Smaller memory = smaller cache = slower seeks.

**Lines 200-201** in `settings.xml`:

```xml
<setting id="tuned_storage" label="30086" type="bool" default="true" />
<setting id="disk_cache_size" label="30597" type="number" enable="eq(-1,true)" default="12" />
```

Disk cache settings affect caching when using file storage.

### D. Socket Timeout

**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/navigation.py`
**Lines 311-316**

```python
try:
    buffer_timeout = int(ADDON.getSetting("buffer_timeout"))
    if buffer_timeout < 60:
        buffer_timeout = 60
except:
    buffer_timeout = 60
buffer_timeout = buffer_timeout * 2  # DOUBLED!

# ...
socket.setdefaulttimeout(buffer_timeout)
```

The socket timeout is **doubled** (60s setting becomes 120s timeout). This timeout is used for initial connection establishment and data transfer. If the daemon takes longer than this to respond to a Range request during a seek, the request will timeout.

## Identified Bottlenecks

### Bottleneck 1: Torrent Piece Fetching on Seek

**Location:** Daemon-side (Go code, not visible in Python)

When seeking backward, the daemon must:
1. Request those pieces from peers
2. Download them sequentially (if not available)
3. They may not be in the pre-buffered area

**Why Rewind is Slow:**
- Backward seeks go to pieces that likely haven't been downloaded yet
- Those pieces have the lowest priority in most torrent algorithms
- The daemon needs to re-prioritize downloads to fetch those pieces first
- This can take significant time if peers have low upload speed or the pieces are rare

### Bottleneck 2: Insufficient Buffer Size

**Current Default:** 20 MB

If rewinding to a position 50+ MB behind current playback, the data MUST be fetched from peers, which is slow.

### Bottleneck 3: Memory/Cache Limitations

**Current Default:** 100 MB auto-adjusted

Larger buffers = larger lookbehind window = faster rewinds within that buffer.

### Bottleneck 4: Download Prioritization Strategy

The `download_file_strategy` setting controls which pieces are prioritized. If it's not optimized for seeking patterns, backward seeks will be slow.

### Bottleneck 5: Libtorrent Piece Selection

**Location:** Go daemon using libtorrent-go library

Libtorrent's internal algorithms determine which pieces to request and from which peers. This is controlled by settings in the daemon but not directly exposed in the Python plugin.

## Code Paths for Playback Position Tracking

**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/rpc.py`
**Lines 268-284**

```python
def Player_WatchTimes(self):
    error = ""
    watchedTime = "0"
    videoDuration = "0"
    try:
        watchedTime = str(XBMC_PLAYER.getTime())
        videoDuration = str(XBMC_PLAYER.getTotalTime())
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

This tracks playback progress but does NOT directly affect seek behavior - it's just for logging/tracking.

## Streaming URL Flow

**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/navigation.py`
**Lines 355-377**

```python
# URL gets converted from plugin:// to http:// to daemon
url = sys.argv[0].replace("plugin://%s" % ADDON_ID, ELEMENTUMD_HOST + url_suffix) + encoded_url

# ...
try:
    data = _json(url)
except PlayerException as e:
    redirect_url = e.__str__()
    log.debug("Launching player with %s" % (redirect_url))
    xbmcplugin.endOfDirectory(HANDLE, succeeded=True)
    xbmc.sleep(500)
    xbmc.executeJSONRPC('{"jsonrpc":"2.0","method":"Player.Open","params":{"item":{"file":"%s"}},"id":"1"}' % (redirect_url))
    return
```

The daemon responds with a **301 redirect** containing the streaming URL (likely `http://127.0.0.1:65220/stream/...`), and Kodi plays that URL directly.

## Recommended Investigations/Solutions

### High Priority

1. **Check daemon logs** - The actual bottleneck is in the daemon's piece selection algorithm when handling Range requests for backward seeks
2. **Increase buffer size** - Try increasing `buffer_size` setting from 20 MB to 50-100 MB
3. **Monitor piece availability** - During rewind, check how many pieces are already available vs. need to be fetched
4. **Check peer swarm health** - Backward seeks depend on having peers that have those earlier pieces

### Medium Priority

5. **Verify download strategy** - Ensure `download_file_strategy` is optimized for seeking patterns
6. **Check Libtorrent piece selection** - The daemon may need libtorrent configuration tuning
7. **Optimize disk cache** - If using disk storage, increase `disk_cache_size`
8. **Monitor socket timeouts** - Ensure Range requests don't timeout during slow networks

### Low Priority (Python Side)

9. **Add seek progress monitoring** - The Python plugin could potentially show buffering progress during seeks
10. **Timeout adjustment** - Could make socket timeout configurable per-operation, though this is unlikely to be the issue

## Configuration Parameters to Test

To improve seek performance, users should try:

```
BitTorrent Settings:
- buffer_size: Increase from 20 to 50-100 MB
- buffer_timeout: Keep at default 60s (or adjust if experiencing timeouts)
- auto_kodi_buffer_size: Ensure it's enabled

Storage Settings:
- auto_memory_size: Keep enabled for auto-detection
- memory_size: Increase if needed (200+ MB recommended)
- disk_cache_size: Increase to 24-32 MB if using file storage

Download Settings:
- download_file_strategy: Test different strategies
- keep_files_playing: Ensure it's set to keep files during playback
```

## Summary of File Locations

| File | Purpose | Key Lines |
|------|---------|-----------|
| `/home/user/plugin.video.elementum/resources/site-packages/elementum/rpc.py` | RPC handler for Player_Seek | 286-292 |
| `/home/user/plugin.video.elementum/resources/site-packages/elementum/navigation.py` | Streaming URL setup, socket timeout | 305-388, 311-325 |
| `/home/user/plugin.video.elementum/resources/site-packages/elementum/monitor.py` | Settings change monitoring | Limited seek handling |
| `/home/user/plugin.video.elementum/resources/site-packages/elementum/service.py` | Service initialization | Starts RPC server |
| `/home/user/plugin.video.elementum/resources/site-packages/elementum/daemon.py` | Daemon management | Starts Go binary (where seek logic lives) |
| `/home/user/plugin.video.elementum/resources/settings.xml` | All settings | Lines 154-158, 200-201, 37 (key buffer settings) |

## Conclusion

The slow rewind/seek performance is primarily a **daemon-level issue** related to:
1. How torrent pieces are prioritized when seeking backward
2. How HTTP Range requests are handled
3. Buffer size and caching strategies

The Python plugin layer is thin and just acts as a wrapper around Kodi's native player and the daemon's HTTP streaming server. To resolve this issue, focus on:
1. Optimizing daemon settings (buffer size, download strategy)
2. Investigating daemon-side piece selection algorithms
3. Ensuring adequate bandwidth and peer availability for backward seeks
