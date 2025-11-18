# DETAILED ISSUES LIST - LOGGING AND DEBUGGING ANALYSIS

## CRITICAL ISSUES

### Issue C-001: Bare Except in Addon Initialization (CRITICAL)
- **File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/addon.py`
- **Line:** 15
- **Code:** `except:`
- **Severity:** CRITICAL
- **Description:** Bare except clause masks critical addon initialization failures. Could hide ImportErrors, AttributeErrors, or other critical failures.
- **Impact:** Makes debugging addon startup failures impossible
- **Fix:** Specify exception types: `except (AttributeError, RuntimeError):`
- **Testing:** Trigger addon initialization with missing dependencies

---

### Issue C-002: Credentials Exposure in Shared Args
- **File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/daemon.py`
- **Lines:** 405-406
- **Code:**
```python
if remote_password != "":
    args.append("-localPassword=" + remote_password)
    shared_args += " -localPassword=" + remote_password
```
- **Severity:** CRITICAL
- **Description:** Password added to `shared_args` without sanitization. If logged elsewhere, credentials leak.
- **Impact:** Credentials exposure in logs and potential security breach
- **Mitigation:** Ensure `shared_args` is sanitized before ANY logging
- **Current Status:** Line 434 sanitizes args but shared_args could still leak elsewhere
- **Fix:** Sanitize shared_args: 
```python
shared_args_sanitized = re.sub(r'-localPassword=[^\s]+', '-localPassword=***', shared_args)
```

---

### Issue C-003: Exception Context Missing - repr() Only
- **File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/daemon.py`
- **Lines:** 321, 365, 367, 376
- **Code Examples:**
  - Line 321: `log.error(repr(e))`
  - Line 365: `log.error(repr(e))`
  - Line 367: `log.error(repr(e))`
  - Line 376: `log.error(repr(e))`
- **Severity:** CRITICAL
- **Description:** Logs only exception repr without context about what operation failed
- **Impact:** Makes debugging nearly impossible - no understanding of context
- **Fix Example:**
```python
# Line 321 - In jsonrpc_enabled()
log.error("Failed to connect to Kodi JSON-RPC at 127.0.0.1:9090: %s", e, exc_info=True)

# Line 365 - In start_elementumd() - OSError handling
if e.errno != 3 and e.errno != 22:
    log.error("OSError (errno=%d) while killing stale process %s: %s", e.errno, pid, e, exc_info=True)

# Line 367 - Generic Exception in lockfile handling
log.error("Exception while processing lockfile %s: %s", lockfile, e, exc_info=True)

# Line 376 - Windows library.db.lock handling
log.error("Exception while removing library.db.lock: %s", e, exc_info=True)
```

---

### Issue C-004: No Structured Exception Logging Across Codebase
- **File:** Multiple files
- **Description:** Exception handling lacks consistent context and stack traces
- **Severity:** CRITICAL
- **Impact:** Makes production debugging and issue diagnosis extremely difficult
- **Fix:** Implement exc_info=True parameter for all exception logs

---

## HIGH SEVERITY ISSUES

### Issue H-001: Bare Except Clauses in osarch.py
- **File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/osarch.py`
- **Lines:** 18, 71, 105, 110, 118, 123
- **Code Examples:**
  - Line 18: `except:` (after ADDON.getSetting)
  - Line 71: `except:` (in get_platform_legacy)
  - Line 105: `except:` (after platform.release())
  - Line 110: `except:` (after platform.machine())
  - Line 118: `except:` (after platform.system())
  - Line 123: `except:` (after platform.platform())
- **Severity:** HIGH
- **Description:** Bare excepts hide platform detection errors
- **Impact:** Silently ignores platform detection failures, making debugging difficult
- **Fix:** Specify exception types for each:
```python
# Line 18
except (AttributeError, RuntimeError):
# Lines 105, 110, 118, 123
except (OSError, AttributeError, TypeError):
```

---

### Issue H-002: Traceback Anti-Pattern in navigation.py
- **File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/navigation.py`
- **Line:** 412
- **Code:** `log.debug(traceback.print_exc())`
- **Severity:** HIGH
- **Description:** traceback.print_exc() returns None, log message will be empty
- **Impact:** Full traceback not logged when needed for debugging
- **Fix:** `log.error(traceback.format_exc())`

---

### Issue H-003: Insufficient Error Context - Copy Operations
- **File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/daemon.py`
- **Lines:** 143, 270
- **Code:** `log.error("Unable to copy to destination path for update: %s" % e)`
- **Severity:** HIGH
- **Description:** Missing source/destination paths in error message
- **Impact:** Cannot determine which file copy failed or where
- **Fix:** Add paths to log message:
```python
log.error("Unable to copy binary from %s to %s: %s", binary_path, dest_binary_path, e, exc_info=True)
```

---

### Issue H-004: Path Disclosure in Logs
- **File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/daemon.py`
- **Line:** 184
- **Code:** `log.info("Using folder %s as xbmc_data_path. Using folder %s as xbmc_bin_path" % (xbmc_data_path, xbmc_bin_path))`
- **Severity:** HIGH
- **Description:** Full absolute paths disclosed in logs, aids system reconnaissance
- **Impact:** Information disclosure vulnerability
- **Fix:** Use relative paths or sanitized names

---

### Issue H-005: Bare Excepts in Dialog Operations
- **File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/dialog_select.py`
- **Lines:** 23, 27, 31
- **Code:** `except:` in dialog initialization
- **Severity:** HIGH
- **Description:** GUI operation errors silently ignored
- **Impact:** UI issues not logged, making debugging difficult
- **Fix:** Specify `except (RuntimeError, AttributeError):`

---

### Issue H-006: Bare Except in Service Startup
- **File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/service.py`
- **Line:** 34
- **Code:** `except:`
- **Severity:** HIGH
- **Description:** Service startup errors masked
- **Impact:** Service failures not reported with context
- **Fix:** Specify exception types and add logging

---

### Issue H-007: Missing Context in Directory Operations
- **File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/daemon.py`
- **Lines:** 253, 258, 261
- **Code Examples:**
  - Line 253: `log.error("Unable to remove destination path for update: %s" % e)`
  - Line 258: `log.error("Unable to create destination path for update: %s" % e)`
  - Line 261: `log.error("Destination path for update does not exist: %s" % dest_binary_dir)`
- **Severity:** HIGH
- **Description:** Missing which specific path failed
- **Impact:** Cannot diagnose file system issues
- **Fix:** Include full path: `log.error("Unable to remove %s: %s", dest_binary_dir, e, exc_info=True)`

---

### Issue H-008: Inappropriate Log Levels
- **File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/daemon.py`
- **Lines:** 31, 91
- **Code Examples:**
  - Line 31: `log.info("Cannot import ctypes: %s" % e)` (should be WARNING)
  - Line 91: `log.info("exception reading checksum path %s: %s" % (path, e))` (should be WARNING)
- **Severity:** HIGH
- **Description:** Errors logged at INFO level instead of WARNING/ERROR
- **Impact:** Important events hidden in verbose logs
- **Fix:** Use appropriate levels based on severity

---

## MEDIUM SEVERITY ISSUES

### Issue M-001: No Log Rotation
- **File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/daemon.py`
- **Lines:** 468-472
- **Code:**
```python
with open(log_path, 'w') as f:
    pass
```
- **Severity:** MEDIUM
- **Description:** Manual truncation only on daemon restart, no ongoing rotation
- **Impact:** Logs can grow unbounded, consume disk space over time
- **Fix:** Implement RotatingFileHandler:
```python
from logging.handlers import RotatingFileHandler
handler = RotatingFileHandler(
    log_path,
    maxBytes=10485760,  # 10 MB
    backupCount=5       # Keep 5 backups
)
```

---

### Issue M-002: Missing Timestamp in Log Format
- **File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/logger.py`
- **Line:** 47
- **Code:** `logging.Formatter('[%(name)s] %(message)s')`
- **Severity:** MEDIUM
- **Description:** No timestamp, level, or file information in logs
- **Impact:** Cannot determine when events occurred or which module logged them
- **Fix:**
```python
logging.Formatter(
    '[%(asctime)s] [%(levelname)-8s] [%(name)s:%(funcName)s:%(lineno)d] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
```

---

### Issue M-003: Inconsistent Log Formatting Style
- **File:** Multiple files
- **Examples:**
  - `log.debug("message %s", var)` (tuple style)
  - `log.info("message %s" % var)` (%-style)
- **Severity:** MEDIUM
- **Description:** Mixed formatting styles reduce consistency
- **Impact:** Harder to maintain and process logs
- **Fix:** Standardize on tuple-style for consistency and safety

---

### Issue M-004: Default Log Level Too Verbose
- **File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/logger.py`
- **Lines:** 31-35
- **Code:**
```python
except (ValueError, TypeError):
    log_level = 3  # Default to DEBUG if conversion fails
```
- **Severity:** MEDIUM
- **Description:** Default is DEBUG level, most verbose option
- **Impact:** Users get overly detailed logs by default
- **Fix:** Change default to INFO (level 2)

---

### Issue M-005: Missing Function Context in Error Messages
- **File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/daemon.py`
- **Multiple Lines:** Throughout error logging
- **Severity:** MEDIUM
- **Description:** No indication of which function/operation failed
- **Impact:** Difficult to trace errors back to source
- **Fix:** Add function name to context or include in format string:
```python
log.error("%s: Unable to process: %s", __name__, e, exc_info=True)
```

---

### Issue M-006: No Request/Correlation IDs
- **File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/rpc.py`
- **Lines:** 593-605
- **Severity:** MEDIUM
- **Description:** No correlation IDs for tracking RPC calls through system
- **Impact:** Cannot trace end-to-end request flow
- **Fix:** Implement request IDs in RPC context

---

### Issue M-007: No Thread ID in Log Format
- **File:** Multiple files (service.py, daemon.py)
- **Severity:** MEDIUM
- **Description:** No thread identification in logs despite multi-threaded architecture
- **Impact:** Race conditions hard to diagnose
- **Fix:** Add `%(threadName)s` to formatter

---

### Issue M-008: No Process ID in Log Format
- **File:** All logging
- **Severity:** MEDIUM
- **Description:** Multiple processes (daemon, service, provider) without process ID
- **Impact:** Cannot distinguish which process logged messages
- **Fix:** Add `%(process)d` to formatter

---

### Issue M-009: Inefficient Traceback Formatting
- **File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/provider.py`
- **Lines:** 104-107, 204-208
- **Code:**
```python
import traceback
for line in traceback.format_exc().split("\n"):
    if line:
        log.error(line)
```
- **Severity:** MEDIUM
- **Description:** Manual traceback formatting less efficient than built-in
- **Impact:** Code complexity and performance impact
- **Fix:** Use `log.error(..., exc_info=True)`

---

### Issue M-010: Missing Performance Timing
- **File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/daemon.py`
- **Operations:** Binary download, folder migration, daemon startup
- **Severity:** MEDIUM
- **Description:** No timing information for long-running operations
- **Impact:** Cannot identify performance bottlenecks
- **Fix:** Add timing logs for critical operations

---

## LOW SEVERITY ISSUES

### Issue L-001: Message Prefix Inconsistency
- **File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/daemon.py`
- **Examples:**
  - Line 37: `log.info("elementum: exiting elementumd")`
  - Line 349: `log.info("Binary dir: %s, item: %s " % ...)` (no prefix)
- **Severity:** LOW
- **Description:** Some logs have "elementumd:" prefix, others don't
- **Impact:** Inconsistent message formatting
- **Fix:** Standardize or rely on logger name in format

---

### Issue L-002: Missing Configuration Logging
- **File:** Multiple files
- **Severity:** LOW
- **Description:** Settings and configuration not logged during startup
- **Impact:** Harder to verify correct configuration in production
- **Fix:** Log all relevant settings at startup

---

### Issue L-003: No Log Archival Strategy
- **File:** All logging
- **Severity:** LOW
- **Description:** Historical logs not retained for post-mortem debugging
- **Impact:** Cannot investigate past issues
- **Fix:** Implement log archival with timestamp-based naming

---

### Issue L-004: String Interpolation Performance
- **File:** Multiple files
- **Examples:**
  - `log.info("msg %s" % expensive_function())`
- **Severity:** LOW
- **Description:** String interpolation happens even if log not displayed
- **Impact:** Minor performance impact
- **Fix:** Use tuple-style: `log.info("msg %s", expensive_function())`

---

### Issue L-005: Exception Representation Inconsistency
- **File:** Multiple files
- **Description:** Mix of `repr(e)` and `str(e)` without clear pattern
- **Severity:** LOW
- **Impact:** Inconsistent error message formatting
- **Fix:** Standardize on `str(e)` for clarity

---

## SUMMARY TABLE

| Issue ID | Severity | File | Line | Type | Status |
|----------|----------|------|------|------|--------|
| C-001 | CRITICAL | addon.py | 15 | Bare except | Not fixed |
| C-002 | CRITICAL | daemon.py | 405-406 | Credentials | Partially mitigated |
| C-003 | CRITICAL | daemon.py | 321,365,367,376 | Missing context | Not fixed |
| C-004 | CRITICAL | Multiple | - | No exc_info | Not fixed |
| H-001 | HIGH | osarch.py | 18,71,105,110,118,123 | Bare except | Not fixed |
| H-002 | HIGH | navigation.py | 412 | Bad traceback | Not fixed |
| H-003 | HIGH | daemon.py | 143,270 | Missing paths | Not fixed |
| H-004 | HIGH | daemon.py | 184 | Path disclosure | Not fixed |
| H-005 | HIGH | dialog_select.py | 23,27,31 | Bare except | Not fixed |
| H-006 | HIGH | service.py | 34 | Bare except | Not fixed |
| H-007 | HIGH | daemon.py | 253,258,261 | Missing paths | Not fixed |
| H-008 | HIGH | daemon.py | 31,91 | Wrong level | Not fixed |
| M-001 | MEDIUM | daemon.py | 468-472 | No rotation | Not fixed |
| M-002 | MEDIUM | logger.py | 47 | No timestamp | Not fixed |
| M-003 | MEDIUM | Multiple | - | Format inconsistency | Not fixed |
| M-004 | MEDIUM | logger.py | 31-35 | Verbose default | Not fixed |
| M-005 | MEDIUM | daemon.py | - | Missing context | Not fixed |
| M-006 | MEDIUM | rpc.py | 593-605 | No correlation | Not fixed |
| M-007 | MEDIUM | Multiple | - | No thread ID | Not fixed |
| M-008 | MEDIUM | Multiple | - | No process ID | Not fixed |
| M-009 | MEDIUM | provider.py | 104-107 | Bad format | Not fixed |
| M-010 | MEDIUM | daemon.py | - | No timing | Not fixed |
| L-001 | LOW | daemon.py | - | Prefix inconsistent | Not fixed |
| L-002 | LOW | Multiple | - | No config logging | Not fixed |
| L-003 | LOW | Multiple | - | No archival | Not fixed |
| L-004 | LOW | Multiple | - | Performance | Not fixed |
| L-005 | LOW | Multiple | - | Inconsistent repr | Not fixed |

---

## TOTAL ISSUES COUNT
- **CRITICAL:** 4
- **HIGH:** 8  
- **MEDIUM:** 10
- **LOW:** 5
- **TOTAL:** 27 specific issues identified

---

