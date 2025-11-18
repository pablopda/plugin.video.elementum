# LOGGING AND DEBUGGING ANALYSIS REPORT
## plugin.video.elementum Kodi Addon

---

## EXECUTIVE SUMMARY

The codebase contains **178 logging statements** across **8 core files** with **153 occurrences** in elementum/. While logging is present, the implementation shows **moderate to critical issues** in:
- **Exception handling quality** (Poor context and visibility)
- **Inconsistent log formatting** (Mixed % and tuple formatting)
- **Bare exception handling** (17 instances without proper exception typing)
- **Sensitive data exposure risks** (Credentials in logs)
- **Performance concerns** (No log rotation or management)
- **Debug information gaps** (Missing context in error logs)

**Overall Rating: 6/10** - Logging exists but lacks maturity in critical areas

---

## 1. LOG LEVEL APPROPRIATENESS

### Issues Found:

#### 1.1 Inappropriate Use of log.info() for Errors (SEVERITY: MEDIUM)
**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/daemon.py`
- **Line 31:** `log.info("Cannot import ctypes: %s" % e)` - Should be WARNING or ERROR
- **Line 91:** `log.info("exception reading checksum path %s: %s" % (path, e))` - Should be WARNING
- **Recommendation:** Use log.warning() for recoverable errors, log.error() for critical failures

#### 1.2 Debug Logging of Expected Failures (SEVERITY: MEDIUM)
**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/monitor.py`
- **Line 59:** `log.debug("Restart request failed (expected on timeout): %s" % e)` - GOOD (correct level)
- **Line 121:** `log.debug("Notification forwarding failed: %s" % e)` - Contextually appropriate

**Verdict:** Generally GOOD for expected timeouts, but inconsistent with similar patterns elsewhere.

#### 1.3 Bare repr() for Exception Details (SEVERITY: HIGH)
**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/daemon.py`
- **Line 321:** `log.error(repr(e))` - No context, just exception repr
- **Line 365:** `log.error(repr(e))` - Lockfile exception handling
- **Line 367:** `log.error(repr(e))` - Duplicate pattern
- **Line 376:** `log.error(repr(e))` - File operation error
- **Impact:** Makes debugging difficult - no understanding of WHERE or WHAT was being attempted

---

## 2. LOG MESSAGE QUALITY

### Issues Found:

#### 2.1 Insufficient Context in Error Messages (SEVERITY: HIGH)
Multiple error logs lack operation context:

**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/daemon.py`
- **Line 143:** `log.error("Unable to copy to destination path for update: %s" % e)` 
  - Missing: Source path, destination path, file being copied
  - **Fix:** Include full operation details: `log.error("Unable to copy from %s to %s: %s" % (src, dst, e))`

- **Line 253:** `log.error("Unable to remove destination path for update: %s" % e)`
  - Missing: Which path failed to remove
  - **Fix:** Include path: `log.error("Unable to remove %s: %s" % (dest_binary_dir, e))`

- **Line 258:** `log.error("Unable to create destination path for update: %s" % e)`
  - Missing: Full path that failed
  - **Fix:** `log.error("Unable to create directory %s: %s" % (dest_binary_dir, e))`

- **Line 270:** `log.error("Unable to copy to destination path for update: %s" % e)`
  - Duplicate of line 143, missing context

#### 2.2 Traceback Logging Anti-Pattern (SEVERITY: MEDIUM)
**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/navigation.py`
- **Line 412:** `log.debug(traceback.print_exc())`
  - **Problem:** print_exc() returns None, log message will be empty
  - **Lines 404-407, 411-415:** Manual traceback formatting

**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/rpc.py`
- **Lines 601-604:** Correct pattern (iterates traceback lines)

**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/provider.py`
- **Lines 104-107, 204-208:** Correct pattern

**Fix for line 412:** Replace with `log.error(traceback.format_exc())`

#### 2.3 Inconsistent Message Formatting (SEVERITY: MEDIUM)
Mixed formatting styles reduce consistency and readability:

**Tuple-style formatting:**
- `log.debug("Failed to close/hide RPC object %s: %s", i, repr(e))` (RPC.py:64) - GOOD
- `log.debug("Failed to set dialog text controls: %s", repr(e))` (RPC.py:184) - GOOD

**%-style formatting:**
- `log.debug("Could not resolve TMDB item %s: %s" % (tmdb_id, repr(e)))` (Navigation.py:182) - OK
- `log.info("exception reading checksum path %s: %s" % (path, e))` (Daemon.py:91) - OK

**Recommendation:** Standardize on tuple-style formatting for consistency and safety (no string interpolation on user input risk)

---

## 3. SENSITIVE DATA IN LOGS

### Critical Issues Found:

#### 3.1 Credentials Exposure Risk (SEVERITY: CRITICAL)
**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/daemon.py`
- **Lines 404-406:** Password added to args without sanitization:
```python
if remote_password != "":
    args.append("-localPassword=" + remote_password)
    shared_args += " -localPassword=" + remote_password
```

- **Line 434:** Logging attempt includes shared_args:
```python
log.info("elementumd: start args: %s, kw: %s" % (sanitize_args_for_logging(args), kwargs))
```

**Positive Finding:** Line 434 DOES attempt sanitization via `sanitize_args_for_logging()` (lines 52-65)

**Potential Weakness:**
- **Line 405-406:** `shared_args` is built with unsanitized password
- If `shared_args` is logged elsewhere without sanitization, credentials leak
- **Line 503:** `log.info("Preparing start with args '%s' and log path: %s" % (sanitize_args_for_logging(args), log_path))`
  - Uses sanitization - GOOD

#### 3.2 Auth Token Logging (SEVERITY: MEDIUM)
**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/navigation.py`
- **Line 336:** `log.info("Setting auth to %s:***" % (login,))`
  - **Positive:** Login is shown, password is masked with ***
  - **Concern:** Login credentials might be sensitive in some contexts
  - **Improvement:** Could be `log.debug()` instead to reduce exposure

#### 3.3 Base64 Encoded Credentials (SEVERITY: MEDIUM)
**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/provider.py`
- **Lines 196-200:** Base64 encoding credentials and adding to headers
```python
callback_user = payload.get("callback_login")
callback_password = payload.get("callback_password")
if callback_user or callback_password:
    base64string = base64.b64encode('{}:{}'.format(callback_user, callback_password).encode())
    req.add_header("Authorization", "Basic %s" % base64string.decode('utf-8'))
```
- No sensitive log lines here, but credentials are in memory - acceptable

#### 3.4 Configuration Values (SEVERITY: MEDIUM)
**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/daemon.py`
- **Line 184:** `log.info("Using folder %s as xbmc_data_path. Using folder %s as xbmc_bin_path" % (xbmc_data_path, xbmc_bin_path))`
  - Full paths logged - could aid attackers in file system reconnaissance
  - **Recommendation:** Use relative or sanitized paths in logs

---

## 4. LOG FORMATTING CONSISTENCY

### Issues Found:

#### 4.1 Inconsistent Logger Initialization (SEVERITY: LOW)
**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/logger.py`
- **Line 47:** `handler.setFormatter(logging.Formatter('[%(name)s] %(message)s'))`
  - Missing timestamp, missing log level in format
  - No correlation IDs for request tracing
  - **Comparison:** Standard format should be: `%(asctime)s - %(name)s - %(levelname)s - %(message)s`

#### 4.2 Message Prefix Inconsistency (SEVERITY: LOW)
Some logs use "elementumd:" prefix, others don't:
- **Daemon.py:37:** `log.info("elementum: exiting elementumd")`
- **Daemon.py:349:** `log.info("Binary dir: %s, item: %s " % ...)` - No prefix
- **Daemon.py:425:** `log.debug("Checking for visible")` - No prefix
- **Daemon.py:568:** `log.info("elementumd: starting elementumd")` - With prefix

**Recommendation:** Standardize prefix usage or rely on logger name in format

#### 4.3 Exception Representation Inconsistency (SEVERITY: LOW)
- **Daemon.py:** Uses `repr(e)` for exceptions
- **Other files:** Mix of `repr(e)` and `str(e)` and context
- **Recommendation:** Use `str(e)` for user-facing logs, `repr(e)` for debug logs

---

## 5. DEBUG INFORMATION AVAILABILITY

### Issues Found:

#### 5.1 Missing Line Numbers in Exception Context (SEVERITY: MEDIUM)
**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/daemon.py`
- **Lines 321, 365, 367, 376:** `log.error(repr(e))` provides ONLY exception type/message
- No source line information
- Traceback should be logged instead

**Example Issue - Line 365-367:**
```python
except OSError as e:
    if e.errno != 3 and e.errno != 22:
        log.error(repr(e))  # <-- Missing errno context!
except Exception as e:
    log.error(repr(e))      # <-- Generic catch-all, no specificity
```
**Better approach:** `log.error("OSError (errno=%d) while handling lockfile: %s", e.errno, e, exc_info=True)`

#### 5.2 Missing Function/Method Context (SEVERITY: MEDIUM)
Many error logs don't indicate where they occurred:

**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/daemon.py`
- **Line 143:** `log.error("Unable to copy to destination path for update: %s" % e)`
  - Should be: `log.error("get_elementum_binary: Unable to copy from %s to %s: %s", src, dst, e, exc_info=True)`

- **Line 253, 258, 270:** Similar context issues in binary update operations

#### 5.3 Performance Logging Missing (SEVERITY: LOW)
No timing information for long-running operations:
- Binary download (lines 208-214)
- Folder migration (lines 139-146)
- Daemon startup (lines 434-489)

**Recommendation:** Add timing logs:
```python
import time
start = time.time()
# ... operation ...
elapsed = time.time() - start
log.info("Operation completed in %.2fs" % elapsed)
```

#### 5.4 Configuration Logging Missing (SEVERITY: MEDIUM)
Only partial settings are logged:
- JSON-RPC port not logged
- Platform detection process not fully logged
- Binary platform selection not logged clearly

**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/osarch.py`
- **Line 64:** `log.debug("Automatically detected platform: %s. Returning: %s" % (auto_platform, repr(ret)))`
  - GOOD! Provides full context

---

## 6. BARE EXCEPTION HANDLING

### Critical Issues Found:

**Total Bare Except Clauses: 17 instances**

#### 6.1 osarch.py - Platform Detection (SEVERITY: HIGH)
- **Line 18:** `except:` after `ADDON.getSetting("binary_platform")`
  - Should be: `except (AttributeError, RuntimeError):`
- **Line 71:** Same pattern in `get_platform_legacy()`
- **Lines 105, 110, 118, 123:** Bare except in platform detection
  - Should specify: `except (OSError, AttributeError, TypeError):`

#### 6.2 dialog_select.py - GUI Interaction (SEVERITY: MEDIUM)
- **Line 23, 27, 31:** Bare except clauses in dialog operations
  - Should be: `except (RuntimeError, AttributeError):`

#### 6.3 service.py - Service Startup (SEVERITY: HIGH)
- **Line 34:** Bare except in service initialization
  - Masks critical startup errors

#### 6.4 addon.py - Addon Initialization (SEVERITY: CRITICAL)
- **Line 15:** `except:` - Most critical location!
  - Should be: `except (AttributeError, RuntimeError):`
  - Could mask critical addon initialization failures

**Impact:** These bare excepts hide:
- AttributeErrors in unexpected API changes
- ImportErrors from missing dependencies
- SystemExit signals (which should propagate)
- KeyboardInterrupt (should allow graceful shutdown)

---

## 7. PERFORMANCE IMPACT OF LOGGING

### Issues Found:

#### 7.1 No Log Rotation (SEVERITY: MEDIUM)
**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/daemon.py`
- **Lines 468-472:** Manual log truncation on each daemon restart
  ```python
  log.info("elementumd: truncating log file: %s" % (log_path))
  with open(log_path, 'w') as f:
      pass
  ```
- **Problem:** Only truncates once per startup, no rotation strategy
- **Risk:** Logs can grow unbounded over long running sessions

#### 7.2 File I/O on Each Log (SEVERITY: LOW)
**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/logger.py`
- Uses XBMCHandler which calls `xbmc.log()` for every log statement
- XBMCHandler inherits from StreamHandler but redirects to Kodi's logging
- **Concern:** Performance acceptable for Kodi integration but not optimal

#### 7.3 Traceback Formatting Overhead (SEVERITY: LOW)
**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/provider.py`
- **Lines 104-107:** Traceback formatting in all code paths
  ```python
  import traceback
  for line in traceback.format_exc().split("\n"):
      if line:
          log.error(line)
  ```
- **Better:** Use `log.error(..., exc_info=True)` - more efficient

#### 7.4 String Interpolation Performance (SEVERITY: LOW)
Using %-formatting instead of lazy evaluation:
- `log.info("message %s" % expensive_function())`
- **Better:** `log.info("message %s", expensive_function())`
- Logger only calls format if log level is active

**Instances found:** Multiple in daemon.py and navigation.py

---

## 8. LOG ROTATION AND MANAGEMENT

### Issues Found:

#### 8.1 No Structured Log Rotation (SEVERITY: MEDIUM)
**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/daemon.py`
- **Lines 468-472:** Truncates log file on daemon restart
- No rotation by size
- No rotation by age/date
- No cleanup of old logs
- **Impact:** Logs can grow to many GBs on long-running systems

#### 8.2 No Log Level Configuration Validation (SEVERITY: LOW)
**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/logger.py`
- **Lines 31-35:** Reads log_level from settings
  ```python
  log_level_str = ADDON.getSetting("log_level")
  try:
      log_level = int(log_level_str)
  except (ValueError, TypeError):
      log_level = 3  # Default to DEBUG if conversion fails
  ```
- **Issue:** Default is DEBUG (most verbose), should be INFO
- **Impact:** Users get overly verbose logs by default

#### 8.3 No Timestamping in Format (SEVERITY: MEDIUM)
**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/logger.py`
- **Line 47:** `logging.Formatter('[%(name)s] %(message)s')`
  - Missing: asctime, levelname, process ID
  - Makes debugging timeline issues difficult
  - **Better format:** `[%(asctime)s] [%(levelname)-8s] [%(name)s] %(message)s`

#### 8.4 No Log Archival Strategy (SEVERITY: MEDIUM)
- Historical logs are not retained
- Only current session logs available
- Makes post-mortem debugging impossible

---

## TRACEABILITY ASSESSMENT

### Issues Found:

#### 9.1 Request/Correlation IDs Missing (SEVERITY: MEDIUM)
**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/rpc.py`
- **Line 593-605:** RPC server thread starts
  - No correlation IDs for tracking RPC calls through the system
  - Makes end-to-end tracing impossible

#### 9.2 Transaction Context Missing (SEVERITY: MEDIUM)
**File:** `/home/user/plugin.video.elementum/resources/site-packages/elementum/navigation.py`
- **Lines 104-150:** getInfoLabels() operation
  - No request ID to track from start to finish
  - Multiple HTTP calls with no correlation

#### 9.3 Process ID Logging (SEVERITY: LOW)
- No process ID in log format
- Multiple processes possible (daemon, service, provider)
- Makes concurrency issues hard to debug

#### 9.4 Thread ID Logging (SEVERITY: LOW)
- **File:** service.py, daemon.py - Multiple threads created
- No thread ID in log format
- Race conditions hard to diagnose

**Example:**
```python
# service.py:19-26
threads = [
    threading.Thread(target=server_thread),  # JSONRPC thread
    threading.Thread(target=elementumd_thread, args=[monitor])  # Elementumd thread
]
```
- Multiple concurrent threads but logs have no thread context

---

## SUMMARY OF ISSUES BY SEVERITY

### CRITICAL (4 issues):
1. Bare except in addon.py line 15 - masks critical initialization
2. Credentials exposure risk in daemon.py lines 404-406
3. Exception context missing in daemon.py lines 321, 365, 367, 376
4. No structured exception logging throughout

### HIGH (8 issues):
1. Multiple bare excepts in osarch.py (lines 18, 71, 105, 110, 118, 123)
2. Inappropriate log levels (info for errors)
3. Missing operation context in error messages
4. traceback.print_exc() logging failure (nav.py:412)
5. Path disclosure in logs (daemon.py:184)
6. Service.py bare except (line 34)
7. Dialog.py bare excepts (lines 23, 27, 31)

### MEDIUM (10+ issues):
1. Inconsistent message formatting
2. Missing function context in logs
3. No log rotation strategy
4. No timestamping in format
5. Missing debug information
6. Traceback formatting inefficiency
7. No correlation IDs for traceability
8. No process/thread ID logging
9. Default log level too verbose
10. Performance logging missing

### LOW (5+ issues):
1. Inconsistent logger initialization
2. Message prefix inconsistency
3. No performance timing
4. String interpolation performance
5. No log archival strategy

---

## RECOMMENDED IMPROVEMENTS

### Priority 1: Fix Critical Issues (Immediate)
1. **Replace all bare excepts** with specific exception types
2. **Add exc_info=True** to all exception logs: `log.error("msg", exc_info=True)`
3. **Sanitize all args/kwargs** containing passwords before logging
4. **Implement logging context** (function name, operation type) for every error

### Priority 2: Improve Log Quality (Short-term)
1. **Standardize log format** to include: `[%(asctime)s] [%(levelname)-8s] [%(name)s:%(funcName)s:%(lineno)d] %(message)s`
2. **Change default log level** from DEBUG to INFO
3. **Use lazy evaluation** with tuple-style formatting: `log.info("msg %s", var)` not `log.info("msg %s" % var)`
4. **Add correlation IDs** for request/transaction tracking

### Priority 3: Implement Log Management (Medium-term)
1. **Implement RotatingFileHandler** for log rotation by size/time
2. **Add log level to settings validation** with proper range checking
3. **Implement log archival** with timestamp-based naming
4. **Add performance timing** to long-running operations

### Priority 4: Enhance Debugging (Long-term)
1. **Add structured logging** (JSON format option)
2. **Implement log aggregation** if multi-process deployment
3. **Add debug metadata** collection (system info, addon state)
4. **Create log analysis tools** for common error patterns

---

## CODE EXAMPLES FOR FIXES

### Fix 1: Exception Logging with Context
**Before:**
```python
except Exception as e:
    log.error(repr(e))
```

**After:**
```python
except Exception as e:
    log.error("Failed to process lockfile %s: %s", lockfile, e, exc_info=True)
```

### Fix 2: Bare Except with Specific Types
**Before:**
```python
try:
    binary_platform = ADDON.getSetting("binary_platform")
except:
    binary_platform = "auto"
```

**After:**
```python
try:
    binary_platform = ADDON.getSetting("binary_platform")
except (AttributeError, RuntimeError) as e:
    log.warning("Failed to get binary_platform setting, using default: %s", e)
    binary_platform = "auto"
```

### Fix 3: Formatting Consistency
**Before:**
```python
log.debug("JSON decode error: %s" % repr(e))
log.debug("Failed to close/hide RPC object %s: %s", i, repr(e))
```

**After (standardized):**
```python
log.debug("JSON decode error: %s", e, exc_info=True)
log.debug("Failed to close/hide RPC object %s: %s", i, e, exc_info=True)
```

### Fix 4: Log Format Enhancement
**Before:**
```python
handler.setFormatter(logging.Formatter('[%(name)s] %(message)s'))
```

**After:**
```python
handler.setFormatter(logging.Formatter(
    '[%(asctime)s] [%(levelname)-8s] [%(name)s] [%(funcName)s:%(lineno)d] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
))
```

### Fix 5: Log Rotation
**Before:**
```python
with open(log_path, 'w') as f:
    pass
```

**After:**
```python
from logging.handlers import RotatingFileHandler
handler = RotatingFileHandler(
    log_path,
    maxBytes=10485760,  # 10 MB
    backupCount=5        # Keep 5 backups
)
```

---

## TESTING RECOMMENDATIONS

1. **Log Format Test:** Verify all required fields in log output
2. **Sensitive Data Test:** Run with test passwords and verify non-exposure
3. **Exception Test:** Trigger all error conditions and verify context appears
4. **Performance Test:** Monitor log write throughput under load
5. **Integration Test:** Verify logs work across daemon/service/provider processes

---

## CONCLUSION

The logging infrastructure exists but requires **substantial improvement** for production readiness. The primary concerns are:

1. **Exception handling** lacks proper context and visibility
2. **Sensitive data** risks exposure in credential fields
3. **Log management** is not automated or scalable
4. **Debugging information** is insufficient for complex issues
5. **Consistency** in formatting and levels varies

**Implementing Priority 1 and 2 recommendations** would bring logging from **6/10 to 8/10** maturity.

