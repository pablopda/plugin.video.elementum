// Package config - Lookbehind configuration additions
//
// INTEGRATION: Add these fields and functions to your existing config.go
//
package config

// ============================================================================
// ADD TO Configuration STRUCT
// ============================================================================
//
// Add these fields to the Configuration struct in config/config.go:
//
// type Configuration struct {
//     // ... existing fields ...
//
//     // Lookbehind Buffer Settings
//     LookbehindEnabled    bool  `json:"lookbehind_enabled"`
//     LookbehindTime       int   `json:"lookbehind_time"`       // seconds to retain
//     LookbehindMaxSize    int64 `json:"lookbehind_max_size"`   // max bytes
//     AutoAdjustLookbehind bool  `json:"auto_adjust_lookbehind"`
// }

// ============================================================================
// ADD TO Reload() FUNCTION
// ============================================================================
//
// Add this code to the Reload() function in config/config.go:

/*
	// Lookbehind Buffer Settings
	c.LookbehindEnabled = xbmcHost.GetSettingBool("lookbehind_enabled", true)
	c.LookbehindTime = xbmcHost.GetSettingInt("lookbehind_time", 30)

	lookbehindMaxSizeMB := xbmcHost.GetSettingInt("lookbehind_max_size", 50)
	c.LookbehindMaxSize = int64(lookbehindMaxSizeMB) * 1024 * 1024

	c.AutoAdjustLookbehind = xbmcHost.GetSettingBool("auto_adjust_lookbehind", true)

	// Validate lookbehind memory constraints
	c.enforceLookbehindConstraints()
*/

// ============================================================================
// ADD NEW FUNCTION
// ============================================================================

// enforceLookbehindConstraints validates and adjusts lookbehind settings
// to fit within available memory. Add this function to config/config.go.
func (c *Configuration) enforceLookbehindConstraints() {
	if !c.LookbehindEnabled {
		return
	}

	// Calculate memory available for lookbehind
	// Total - Forward Buffer - End Buffer - Overhead
	reservedMemory := int64(c.BufferSize) + c.EndBufferSize + 8*1024*1024
	availableForLookbehind := int64(c.MemorySize) - reservedMemory

	// Cap at 50% of total memory to leave room for libtorrent internals
	maxAllowed := int64(c.MemorySize) / 2
	if availableForLookbehind > maxAllowed {
		availableForLookbehind = maxAllowed
	}

	// Enforce cap
	if c.LookbehindMaxSize > availableForLookbehind {
		log.Warningf("Lookbehind size %d MB exceeds available %d MB, capping",
			c.LookbehindMaxSize/1024/1024,
			availableForLookbehind/1024/1024)
		c.LookbehindMaxSize = availableForLookbehind
	}

	// Disable if too small to be useful (< 10 MB)
	if c.LookbehindMaxSize < 10*1024*1024 {
		log.Warning("Insufficient memory for lookbehind (<10MB), disabling")
		c.LookbehindEnabled = false
	}
}

// CalculateLookbehindSize determines actual lookbehind size based on video bitrate.
// Add this function to config/config.go.
func (c *Configuration) CalculateLookbehindSize(fileSize int64, durationSec float64) int64 {
	if !c.LookbehindEnabled || c.LookbehindTime == 0 {
		return 0
	}

	// Calculate bitrate from file size and duration
	var bitrateBps int64
	if durationSec > 0 {
		bitrateBps = int64(float64(fileSize) / durationSec)
	} else {
		// Fallback: assume 2.5 MB/s for 1080p content
		bitrateBps = 2500 * 1024
	}

	// Calculate needed size for configured time
	size := bitrateBps * int64(c.LookbehindTime)

	// Cap at configured maximum
	if size > c.LookbehindMaxSize {
		size = c.LookbehindMaxSize
	}

	return size
}
