# Bug Fix 50 — fd_shmem_private_getrandom() error path silently swallowed

**Severity:** Medium — silent failure on transient Linux signals, short reads leave memory uninitialized for the retry loop's next attempt.

**Source:** Audit #50, macOS platform port review (V2.22.S1).

## Current behavior

`fd_shmem_private_getrandom()` in `src/util/shmem/fd_shmem_user.c` (lines 27-42):

- **Linux**: calls `syscall(SYS_getrandom, ...)`, discards the return via `(void)n` (dead code), then returns `(int)n`. No EINTR retry, no short-read loop.
- **macOS**: calls `arc4random_buf()`, which never fails per OpenBSD/macOS docs. Returns `(int)buflen`. This path is correct.
- **Fallback**: returns `-1/ENOSYS`.

The caller (`fd_shmem_private_map_rand`, line 142) checks `n != sizeof(ret_addr)` and logs `FD_LOG_ERR`, but the stub should handle EINTR and short reads — it's a framework utility that callers should not need to know about syscall-level error semantics.

## Impact

- **Linux**: a single signal during the syscall causes the entire `fd_shmem_join()` to abort with `FD_LOG_ERR`. No retry, no recovery.
- **Short reads**: `getrandom()` can return 2 bytes on a 47-bit address request, leaving 6 bytes uninitialized. The next iteration re-overwrites them, so data corruption is limited to one iteration of garbage, but the behavior is non-deterministic and platform-dependent.

## Fix

Replace the Linux path with the industry-standard `getrandom()` loop (EINTR retry + short-read retry):

```c
#if defined(FD_HAS_LINUX)
  {
    long n;
    do {
      n = syscall( SYS_getrandom, buf, buflen, flags );
    } while ( n < 0 && errno == EINTR );
    if ( n < 0 ) {
      errno = -n;
      return -1;
    }
    /* Short read: retry for remaining bytes */
    char *p = (char *)buf;
    size_t off = (size_t)n;
    while ( off < buflen ) {
      long m = syscall( SYS_getrandom, p + off, buflen - off, flags );
      if ( m < 0 ) {
        if ( errno == EINTR ) continue;
        errno = -m;
        return -1;
      }
      off += (size_t)m;
    }
    return (int)buflen;
  }
#elif defined(FD_HAS_MACOS)
  if ( FD_UNLIKELY( buflen == 0 ) ) {
    errno = EINVAL;
    return -1;
  }
  (void)flags;
  arc4random_buf( buf, buflen );
  return (int)buflen;
```

### Changes

| File | Change |
|------|--------|
| `src/util/shmem/fd_shmem_user.c` | Replace Linux `getrandom()` path with EINTR + short-read retry loop. Add `buflen == 0` guard on macOS. |

No other files affected. The caller at line 142 already has the `FD_LOG_ERR` guard and does not need modification.

## Verification

1. Build on Linux: `zig build` completes clean.
2. Build on macOS: `zig build` completes clean.
3. No new `FD_LOG_ERR` or warning needed — the fix makes failure extremely unlikely (only happens when `/dev/urandom` is exhausted or unavailable, which would indicate a system-level emergency). The existing caller's `FD_LOG_ERR` at line 142 covers the remaining failure case.

## Rollback

Single-file change. Revert the function body to the original 3-branch `#if`/`#elif`/`#else` pattern.
