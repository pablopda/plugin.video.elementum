# Seek/Rewind Performance - Final Evaluation

## Executive Summary

**The slow rewind issue is a known, acknowledged, and unfixed limitation of Elementum.**

The maintainer (elgatito) explicitly closed related issues stating "there is nothing we can do" within the current architecture.

## GitHub Issues Investigated

### Issue #837 - "Excessive piece redownloading when skipping"
- **Status**: Closed - "Not Planned"
- **Key Quote**: "I'm closing this issue as I believe there is nothing we can do."
- **Problem**: 10-second backward seek causes 20-25 second freeze
- **Proposed Fix**: "Recent Reserve Buffer" keeping last 30 seconds - NOT implemented

### Issue #709 - "Use Memory and seek for small steps"
- **Status**: Open
- **Key Quote**: "Elementum tries to use buffer for forward pieces, as much as possible, that is why seeking backwards will need to re-download pieces."
- **Note**: "This behavior is not configurable in version 0.1.x"

### Issue #845 - "Don't STOP torrent on Kodi seek timeout"
- **Status**: Closed - "Not Planned"
- **Workaround Found**: Use tmpfs + file storage instead of memory storage

## Root Cause Confirmed

The Go daemon (Elementumd) intentionally uses **forward-only buffering** to maximize memory for upcoming content. When seeking backward:

1. Pieces behind current position are not kept
2. Daemon must reconnect to peers
3. Re-download previously played pieces
4. Wait for enough buffer before playback resumes

This is a fundamental architectural decision, not a bug.

## Recommendations

### For Users

#### Option 1: Increase Buffer Settings (Marginal Improvement)
```
Settings → Storage:
- memory_size: 100 → 300-500 MB
- auto_memory_size_strategy: Maximum

Settings → BitTorrent:
- buffer_size: 20 → 75-100 MB
- buffer_timeout: 60 → 180+ seconds
```

#### Option 2: Use tmpfs + File Storage (Better - Linux Only)
```bash
# Create RAM disk
sudo mount -t tmpfs -o size=1G tmpfs /mnt/elementum-cache

# In Elementum settings:
# - Set download_path to /mnt/elementum-cache
# - Use "Download to selected path" storage option
```

Benefits:
- Pieces persist during playback
- Better seek stability
- Still uses RAM (no disk wear)

#### Option 3: Use File Storage on SSD (Best Seek Performance)
- Set download_path to SSD location
- Pieces remain on disk
- Fast seeks (no re-downloading)
- Tradeoff: Uses disk space and I/O

### For Developers (If Forking)

The proposed but unimplemented fix from Issue #837:

**"Recent Reserve Buffer"**
- Keep last 30 seconds of played content in memory
- Requires ~30-75 MB additional RAM
- Would need Go daemon modification
- Location: elgatito/elementum repository (not this Python plugin)

## Validation of Our Analysis

| Conclusion | GitHub Evidence | Status |
|------------|-----------------|--------|
| Python plugin is NOT bottleneck | All issues discuss daemon/libtorrent | ✓ Confirmed |
| Forward buffering only | Issue #709 developer statement | ✓ Confirmed |
| Settings are main mitigation | No code fixes provided | ✓ Confirmed |
| Would need daemon changes | Issue #837 closed unfixed | ✓ Confirmed |

## Final Reality Check

**Elementum development is stopped.** The maintainer has stated:
- This limitation is architectural
- No fix is planned
- Users should adjust settings or use file storage

The slow backward seek is an inherent tradeoff of torrent-based streaming with memory buffering. Forward seeks are always faster because content is pre-buffered. Backward seeks will always require re-fetching from peers unless using file-based storage.

## References

- Issue #837: https://github.com/elgatito/plugin.video.elementum/issues/837
- Issue #709: https://github.com/elgatito/plugin.video.elementum/issues/709
- Issue #845: https://github.com/elgatito/plugin.video.elementum/issues/845
