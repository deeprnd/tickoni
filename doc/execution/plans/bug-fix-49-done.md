# Bug #49 Fix Plan: Strict Aliasing Violation in fiat-crypto Call Sites

## Problem

`ulong*` to `uint64_t*` casts on struct field pointers passed to fiat-crypto functions violate strict aliasing rules.

- `fd_uint256_t` has `ulong limbs[4]` (typedef: `unsigned long` on macOS, `unsigned long long` on Windows)
- `fd_f25519_t` has `ulong el[5]` (non-32 mode) or `uint el[10]` (32 mode)
- fiat-crypto functions declare parameters as `uint64_t*` arrays
- `(uint64_t *)r->limbs` is UB under strict aliasing: `ulong` and `uint64_t` are different types

## Fix Strategy

Replace direct `(uint64_t *)` casts with `(uint64_t *)(uintptr_t)` intermediate casts to break the aliasing chain. This is the standard C idiom (C11 6.5/7) for this pattern.

## Scope

### File 1: src/ballet/bn254/fd_bn254_field_inl.h

7 call sites in fiat-crypto function calls:

| Line | Function | Current | Fix |
|------|----------|---------|-----|
| 103 | fiat_bn254_from_montgomery | `(uint64_t *)r->limbs` | `(uint64_t *)(uintptr_t)r->limbs` |
| 103 | fiat_bn254_from_montgomery | `(uint64_t const *)a->limbs` | `(uint64_t const *)(uintptr_t)a->limbs` |
| 110 | fiat_bn254_to_montgomery | `(uint64_t *)r->limbs` | `(uint64_t *)(uintptr_t)r->limbs` |
| 110 | fiat_bn254_to_montgomery | `(uint64_t const *)a->limbs` | `(uint64_t const *)(uintptr_t)a->limbs` |
| 147 | fiat_bn254_add | `(uint64_t *)r->limbs`, `(uint64_t const *)a->limbs`, `(uint64_t const *)b->limbs` | `(uint64_t *)(uintptr_t)` |
| 182 | fiat_bn254_sub | same pattern | `(uint64_t *)(uintptr_t)` |
| 189 | fiat_bn254_opp | same pattern | `(uint64_t *)(uintptr_t)` |
| 226-227 | fiat_bn254_to_montgomery (inv, s2n-bignum) | same pattern | `(uint64_t *)(uintptr_t)` |

### File 2: src/ballet/bn254/fd_bn254_scalar.h

5 call sites (lines 51, 58, 66, 76, 83):

| Line | Function | Fix |
|------|----------|-----|
| 51 | fiat_bn254_scalar_from_montgomery | `(uint64_t *)(uintptr_t)r->limbs` |
| 58 | fiat_bn254_scalar_to_montgomery | `(uint64_t *)(uintptr_t)r->limbs` |
| 66 | fiat_bn254_scalar_add | `(uint64_t *)(uintptr_t)` |
| 76 | fiat_bn254_scalar_mul | `(uint64_t *)(uintptr_t)` |
| 83 | fiat_bn254_scalar_square | `(uint64_t *)(uintptr_t)` |

### File 3: src/ballet/ed25519/ref/fd_f25519.h

13 call sites (lines 38, 46, 55, 56, 65, 66, 77, 88, 96, 104, 115, 126, 138):

All `(uint64_t *)r->el` and `(uint64_t *)a->el` / `(uint64_t *)b->el` etc. become `(uint64_t *)(uintptr_t)r->el`.

### Dependency: uintptr_t availability

`uintptr_t` requires `<stdint.h>`. None of the three files include it. Must add to each:

- fd_bn254_field_inl.h: add `#include <stdint.h>` after existing includes
- fd_bn254_scalar.h: add `#include <stdint.h>` after existing includes  
- fd_f25519.h: add `#include <stdint.h>` after existing includes

Alternatively, if `fd_ballet_base.h` or `fd_util.h` (transitive includes) already bring in stdint.h, this may be redundant but harmless.

## Execution Order

1. Add `#include <stdint.h>` to all three files
2. Patch fd_bn254_scalar.h (5 sites, simplest file)
3. Patch fd_bn254_field_inl.h (8 sites, most affected)
4. Patch fd_f25519.h (13 sites)
5. Build and verify no regressions

## Verification

- `zig build` succeeds on Linux
- `zig build` succeeds on macOS (if available)
- No new warnings from `-Wstrict-aliasing=2` or `-Wcast-align`
- Existing tests pass
- No changes to `fd_uint256.h` union definition (preserves existing ABI)
