# Bug Fix Plan: _DEFAULT_SOURCE Feature Test Macro Timing Conflict (Issue #48)

## Assessment

**Bug status: NOT currently exploitable, but structurally fragile.**

The `_DEFAULT_SOURCE` / `_DARWIN_C_SOURCE` / `_GNU_SOURCE` macros in `fd_shmem_user.c`
(lines 1-15) are correctly placed before the `fd_shmem_private.h` include. The transitive
include chain (`fd_shmem_private.h` -> `fd_shmem.h` -> `fd_log.h` -> `fd_env.h` + `fd_io.h`)
does not currently pull in `<unistd.h>` or any other header requiring these feature-test
macros. The `<unistd.h>` include points are all in `.c` files (fd_log.c, fd_backtrace.c,
fd_io.c), not in any header.

However, the pattern is fragile: adding a standard header to any intermediate header in the
chain would silently reintroduce the bug. On Xcode 16+ / macOS 15+, feature-test macro
timing is particularly sensitive.

## Root Cause Pattern

Feature-test macros (`_DEFAULT_SOURCE`, `_DARWIN_C_SOURCE`, `_GNU_SOURCE`) must be defined
BEFORE the standard header that needs them is parsed by the preprocessor. Any standard
header pulled in transitively through the include chain before the macro definition will
not expose the needed symbols.

## Proposed Fix

Centralize feature-test macro definitions in `fd_shmem_private.h` (the single include point
for all shmem module code). This ensures every translation unit that includes the private
header gets the macros set before any standard headers are transitively pulled in.

### Changes

1. **`src/util/shmem/fd_shmem_private.h`** — Add feature-test macro definitions at the top
   of the file, before `#include "fd_shmem.h"`:

```c
#ifndef HEADER_fd_src_util_shmem_fd_shmem_private_h
#define HEADER_fd_src_util_shmem_fd_shmem_private_h

/* Feature-test macros — must precede ALL includes including fd_shmem.h */
#if defined(__APPLE__)
#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE
#endif
#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE
#endif
#endif

#if FD_HAS_HOSTED
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#endif

#include "fd_shmem.h"
...
```

2. **`src/util/shmem/fd_shmem_user.c`** — Remove the feature-test macro block (lines 1-15),
   keeping the comment for documentation purposes but moving the actual defines to the
   private header.

3. **`src/util/shmem/fd_shmem_admin.c`** — Move `_GNU_SOURCE` from the top of the file
   (before `fd_shmem_private.h`) into `fd_shmem_private.h` where it belongs. The file can
   keep the `#if FD_HAS_THREADS` guard since that maps to `FD_HAS_HOSTED` for this purpose,
   but the macro itself moves to the private header.

4. **`src/util/shmem/fd_numa_linux.c`** — Remove the top-of-file `_GNU_SOURCE` define
   since it is now in the private header. Keep the comment.

### Verification

- `fd_shmem_private.h` is the single include point for all shmem `.c` files. Verify this
  with: `grep -r 'fd_shmem_private.h' src/util/shmem/*.c`
- After the change, no `.c` file should define `_DEFAULT_SOURCE`, `_DARWIN_C_SOURCE`, or
  `_GNU_SOURCE` above its includes (they are centralized in the private header).
- Build on both Linux and macOS targets to confirm no regressions.
