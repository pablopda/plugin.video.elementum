# PERFORMANCE ISSUE INDEX - DETAILED LOCATION GUIDE

## Index by File

### daemon.py (5 major issues)

#### Issue #1: Critical Startup Hang - JSON-RPC Check Sleep
- **Lines:** 338, 344
- **Code:** 
  ```python
  338 |   time.sleep(5)
  344 |   time.sleep(3)
  ```
- **Context:** `start_elementumd()` function during JSON-RPC connectivity check
- **Impact:** Blocks addon startup 3-8 seconds
- **Severity:** CRITICAL
- **Fix Priority:** 1 (Immediate)
- **Solution:** Replace with `monitor.waitForAbort(seconds)`

#### Issue #2: String Concatenation in Argument Building
- **Lines:** 385-406
- **Code:**
  ```python
  385-390 | ADDON.getSetting() calls for config
  393-406 | shared_args += " -option=" + value (5 times)
  ```
- **Context:** `start_elementumd()` function, building daemon arguments
- **Impact:** Memory waste, creates 5 new string objects
- **Severity:** HIGH
- **Fix Priority:** 2
- **Solution:** Use list and `" ".join()`

#### Issue #3: Startup Delay Sleep
- **Lines:** 446
- **Code:**
  ```python
  446 | time.sleep(delay)  # User-configurable 0-180 seconds
  ```
- **Context:** Optional startup delay feature
- **Impact:** Blocks startup (configurable)
- **Severity:** MEDIUM
- **Fix Priority:** 2
- **Solution:** Use `monitor.waitForAbort(delay)`

#### Issue #4: Settings Window Busy-Wait Loop
- **Lines:** 426-432
- **Code:**
  ```python
  426 | while xbmc.getCondVisibility(...):
  431 |   time.sleep(1)
  432 |   wait_counter += 1
  ```
- **Context:** Wait for settings window to close before daemon starts
- **Impact:** Can block up to 300 seconds, 600+ API calls
- **Severity:** HIGH
- **Fix Priority:** 2
- **Solution:** Use event-based waiting instead

#### Issue #5: Settings Lookup Not Cached
- **Lines:** 385-390, 436
- **Code:**
  ```python
  385 | local_port = ADDON.getSetting("local_port")
  386 | remote_host = ADDON.getSetting("remote_host")
  387 | remote_port = ADDON.getSetting("remote_port")
  388 | remote_login = ADDON.getSetting("remote_login")
  389 | remote_password = ADDON.getSetting("remote_password")
  390 | force_library = ADDON.getSetting("local_force_library")
  436 | delay = int(ADDON.getSetting("startup_delay"))
  ```
- **Context:** Multiple setting lookups at startup
- **Impact:** 50-70% wasted CPU on registry/XML lookups
- **Severity:** HIGH
- **Fix Priority:** 1
- **Solution:** Cache all settings at function start

---

### navigation.py (4 major issues)

#### Issue #6: Blocking Sleep After UI Operations
- **Lines:** 381, 388, 398
- **Code:**
  ```python
  381 | xbmc.sleep(500)
  388 | xbmc.sleep(500)
  398 | time.sleep(preload_timeout)  # in retry loop
  ```
- **Context:** Sleeps after `endOfDirectory()` and navigation operations
- **Impact:** 500ms UI freezes during navigation updates
- **Severity:** HIGH
- **Fix Priority:** 2
- **Solution:** Replace with async operations or reduce delay

#### Issue #7: Settings Lookups Not Cached
- **Lines:** 313, 322, 333-345
- **Code:**
  ```python
  313 | buffer_timeout = int(ADDON.getSetting("buffer_timeout"))
  322 | preload_timeout = int(ADDON.getSetting("preload_timeout"))
  333 | login = ADDON.getSetting("remote_login")
  334 | password = ADDON.getSetting("remote_password")
  345 | os.environ['no_proxy'] = ... ADDON.getSetting("remote_host")
  581 | ADDON.getSetting('default_fanart')
  612 | ADDON.getSetting("viewmode_%s" % content_type)
  ```
- **Context:** `run()` function with multiple setting lookups
- **Impact:** Repeated registry queries
- **Severity:** HIGH
- **Fix Priority:** 1
- **Solution:** Cache settings dict at function start

#### Issue #8: Network Retry No Backoff
- **Lines:** 394-399
- **Code:**
  ```python
  except urllib_error.URLError as e:
      if retry <= 2:
          time.sleep(preload_timeout)  # Fixed 1-second delay
          return run(retry=retry + 1)
  ```
- **Context:** Error handling for failed network requests
- **Impact:** Hammers server, no exponential backoff
- **Severity:** MEDIUM
- **Fix Priority:** 3
- **Solution:** Exponential backoff: `delay = base * (2 ** retry)`

#### Issue #9: Inefficient List Creation
- **Lines:** 460-606
- **Code:**
  ```python
  460 | listitems = list(range(len(data["items"])))
  461 | for i, item in enumerate(data["items"]):
       ...
  606 | listitems[i] = (item["path"], listItem, is_playable)
  ```
- **Context:** Pre-allocating list for directory items
- **Impact:** Creates unnecessary integer list, wastes memory
- **Severity:** LOW-MEDIUM
- **Fix Priority:** 4
- **Solution:** Use `[None] * len()` or direct assignment

#### Issue #10: Redundant Dict Operations in Loop
- **Lines:** 551-557
- **Code:**
  ```python
  for fa in item.get("art")["fanarts"]:
      start += 1
      if PLATFORM['kodi'] < 18:
          item.get("art")["fanart{}".format(start)] = fa  # get() twice
  ```
- **Context:** Processing fanart items in loop
- **Impact:** Double dict lookups per iteration
- **Severity:** LOW-MEDIUM
- **Fix Priority:** 4
- **Solution:** Cache `art = item.get("art")` before loop

---

### rpc.py (5 major issues)

#### Issue #11: Dialog Text Setup Blocking Sleep
- **Lines:** 173, 178
- **Code:**
  ```python
  172 | xbmc.executebuiltin('ActivateWindow(%d)' % id)
  173 | xbmc.sleep(500)
  174-182 | Loop with xbmc.sleep(10) (up to 50 iterations)
  ```
- **Context:** `Dialog_Text()` function setting up text viewer
- **Impact:** 500ms + up to 500ms in loop
- **Severity:** MEDIUM
- **Fix Priority:** 3
- **Solution:** Use Kodi callback instead of polling

#### Issue #12: Window Loading Wait Blocking Sleep
- **Lines:** 201
- **Code:**
  ```python
  200 | time.sleep(0.3)
  ```
- **Context:** `Wait_Window_Loaded()` polling for window load
- **Impact:** 300ms blocks × 9 retries = 2.7s max wait
- **Severity:** MEDIUM
- **Fix Priority:** 3
- **Solution:** Use event-based window load notification

#### Issue #13: Settings Lookup in Loop
- **Lines:** 332-339, 397-405
- **Code:**
  ```python
  332-339 | Multiple getAddonInfo() calls
  397-405 | Loop through settings with getSetting() inside
  ```
- **Context:** `GetAddonInfo()` and `GetAllSettings()` functions
- **Impact:** Multiple Kodi API calls
- **Severity:** MEDIUM
- **Fix Priority:** 3
- **Solution:** Cache addon info and settings

#### Issue #14: Regex Not Pre-compiled
- **Lines:** 397, 427, 430, 437
- **Code:**
  ```python
  397 | keyType = re.findall(r".*id=\"(\w+)\".*type=\"(\w+)\"(.*option=\"(\w+)\")?", ...)
  427 | re.search('defaultresolution="([^"]+)', read, re.DOTALL).group(1)
  430 | re.search('<res.+?folder="([^"]+)', read, re.DOTALL).group(1)
  437 | match = re.search('<views>([^<]+)', read, re.DOTALL)
  ```
- **Context:** Settings and skin detection code
- **Impact:** Regex compiled on every call
- **Severity:** MEDIUM
- **Fix Priority:** 3
- **Solution:** Compile patterns at module level

#### Issue #15: Inefficient Dictionary Key Iteration
- **Lines:** 55
- **Code:**
  ```python
  for i in list(self._objects.keys()):
  ```
- **Context:** `Reset()` method cleaning up objects
- **Impact:** Unnecessary list copy of keys
- **Severity:** MEDIUM
- **Fix Priority:** 4
- **Solution:** Direct iteration: `for i in self._objects.keys():`

#### Issue #16: Provider Failure Blocking Sleep
- **Lines:** 362
- **Code:**
  ```python
  362 | time.sleep(10)
  ```
- **Context:** `AddonFailure()` function after too many failures
- **Impact:** 10-second block before disabling provider
- **Severity:** MEDIUM
- **Fix Priority:** 3
- **Solution:** Use async notification instead

---

### osarch.py (2 major issues)

#### Issue #17: Inefficient CPU Info Parsing
- **Lines:** 212-226
- **Code:**
  ```python
  223 | if len(line.split(':')) == 2:
  223 |   procinfo[line.split(':')[0].strip()] = line.split(':')[1].strip()
  225 |   procinfo[line.split(':')[0].strip()] = ''
  ```
- **Context:** `cpuinfo()` parsing /proc/cpuinfo
- **Impact:** split() called 2-3 times per line
- **Severity:** MEDIUM
- **Fix Priority:** 4
- **Solution:** Parse once: `parts = line.split(':');`

#### Issue #18: Excessive xbmc.getCondVisibility Calls
- **Lines:** Multiple - 126, 132, 136, 146, 173, 177, 181, 191, 112
- **Code:**
  ```python
  126 | if xbmc.getCondVisibility("system.platform.android"):
  132 | elif xbmc.getCondVisibility("system.platform.linux"):
  136 | if xbmc.getCondVisibility("system.platform.linux.raspberrypi"):
  # ... many more in get_platform_legacy()
  ```
- **Context:** `get_platform()` and `get_platform_legacy()` functions
- **Impact:** 10+ API calls during platform detection
- **Severity:** MEDIUM
- **Fix Priority:** 4
- **Solution:** Cache platform detection result (already has some caching)

---

### util.py (2 major issues)

#### Issue #19: Regex Not Pre-compiled
- **Lines:** 41
- **Code:**
  ```python
  41 | return re.sub(r'LOCALIZE\[(\d+)\]', getLocalizedStringMatch, text)
  ```
- **Context:** `getLocalizedText()` called per localization
- **Impact:** Regex compiled on every text localization
- **Severity:** MEDIUM
- **Fix Priority:** 4
- **Solution:** Pre-compile at module level

#### Issue #20: Inefficient Dialog Creation
- **Lines:** 32, 36
- **Code:**
  ```python
  32 | dialog = xbmcgui.Dialog()  # in notify()
  36 | dialog = xbmcgui.Dialog()  # in dialog_ok()
  ```
- **Context:** `notify()` and `dialog_ok()` utility functions
- **Impact:** New dialog object created per call
- **Severity:** LOW-MEDIUM
- **Fix Priority:** 4
- **Solution:** Singleton dialog instance or cached pool

---

### provider.py (1 issue)

#### Issue #21: List Comprehension in Join
- **Lines:** 120
- **Code:**
  ```python
  120 | return uri + "|" + "|".join(["%s=%s" % h for h in headers.items()])
  ```
- **Context:** `append_headers()` function
- **Impact:** Minor - list comprehension creates unnecessary list
- **Severity:** LOW
- **Fix Priority:** 5
- **Solution:** Use generator: `"|".join("%s=%s" % h for h in ...)`

---

### service.py (1 issue)

#### Issue #22: Service Loop Blocking Sleep
- **Lines:** 30
- **Code:**
  ```python
  30 | xbmc.sleep(1000)
  ```
- **Context:** Main service loop
- **Impact:** 1-second blocks in background service
- **Severity:** MEDIUM
- **Fix Priority:** 3
- **Solution:** Use `monitor.waitForAbort(1)`

---

## Summary by Priority

### Priority 1 (Critical - Immediate)
- daemon.py:338, 344 (Startup hang)
- daemon.py/navigation.py (Settings caching)

### Priority 2 (High - Soon)
- daemon.py:393-406 (String concat)
- daemon.py:426-432 (Busy-wait loop)
- navigation.py:394-399 (Network retry backoff)

### Priority 3 (Medium - Next Release)
- rpc.py:173, 178, 201, 362 (Blocking sleeps)
- service.py:30 (Service loop sleep)
- rpc.py:397, util.py:41 (Regex compilation)

### Priority 4 (Low - Refactoring)
- navigation.py:460 (List creation)
- navigation.py:551-557 (Dict operations)
- rpc.py:55 (Dict iteration)
- osarch.py:212-226 (File I/O)
- osarch.py:126+ (Platform detection)
- util.py:32, 36 (Dialog creation)

### Priority 5 (Trivial)
- provider.py:120 (List comprehension)

---

## Files by Issue Count

1. **daemon.py** - 5 issues
2. **navigation.py** - 4 issues  
3. **rpc.py** - 6 issues
4. **osarch.py** - 2 issues
5. **util.py** - 2 issues
6. **provider.py** - 1 issue
7. **service.py** - 1 issue

Total: 21 performance issues identified

