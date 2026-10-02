/* Cross-platform shared memory for Firedancer.
   Windows backend: CreateFileMapping + MapViewOfFile.
   Replaces the previous stubs that returned ENOTSUP. */

#define _CRT_SECURE_NO_WARNINGS
#include "fd_shmem.h"
#include "../fd_platform_runtime_caps.h"
#include <windows.h>
#include <errno.h>
#include <string.h>

/* ── Windows shmem state ──────────────────────────────────────────── */

/* Each region is stored once; joins are reference-counted. */
#define WIN_SHMEM_MAX_REGIONS 256
#define WIN_SHMEM_MAX_JOINS   1024
#define WIN_SHMEM_NAME_MAX_LEN 255

typedef struct win_shmem_region {
    char           name[FD_SHMEM_NAME_MAX];
    HANDLE         mapping_handle;
    ulong          page_sz;
    ulong          page_cnt;
    int            ref_cnt;   /* >0 when mapped by someone */
    int            created;   /* 1 after fd_shmem_create_multi succeeds */
    int            unlink_pending; /* 1 after fd_shmem_unlink (destroy when ref_cnt==0) */
} win_shmem_region_t;

static win_shmem_region_t win_shmem_regions[WIN_SHMEM_MAX_REGIONS];
static int win_shmem_region_cnt = 0;

typedef struct win_shmem_join {
    void * addr;
    int    region_idx;
} win_shmem_join_t;

static win_shmem_join_t win_shmem_joins[WIN_SHMEM_MAX_JOINS];

/* ── Helpers ──────────────────────────────────────────────────────── */

static int win_shmem_find_region(const char *name, ulong page_sz, int *idx_out) {
    for (int i = 0; i < win_shmem_region_cnt; i++) {
        if (win_shmem_regions[i].created &&
            strcmp(win_shmem_regions[i].name, name) == 0 &&
            win_shmem_regions[i].page_sz == page_sz) {
            if (idx_out) *idx_out = i;
            return 1;
        }
    }
    return 0;
}

static int win_shmem_find_or_create(const char *name, ulong page_sz, int *idx_out) {
    int idx;
    if (win_shmem_find_region(name, page_sz, &idx)) {
        if (idx_out) *idx_out = idx;
        return 1;
    }
    if (win_shmem_region_cnt >= WIN_SHMEM_MAX_REGIONS) return 0;
    idx = win_shmem_region_cnt++;
    win_shmem_regions[idx].created = 0;
    win_shmem_regions[idx].ref_cnt = 0;
    win_shmem_regions[idx].mapping_handle = NULL;
    win_shmem_regions[idx].unlink_pending = 0;
    if (idx_out) *idx_out = idx;
    return 1;
}

static void win_shmem_update_info(const char *name, ulong page_sz, fd_shmem_info_t *opt_info) {
    if (!opt_info) return;
    for (int i = 0; i < win_shmem_region_cnt; i++) {
        if (win_shmem_regions[i].created &&
            strcmp(win_shmem_regions[i].name, name) == 0 &&
            win_shmem_regions[i].page_sz == page_sz) {
            opt_info->page_sz  = win_shmem_regions[i].page_sz;
            opt_info->page_cnt = win_shmem_regions[i].page_cnt;
            return;
        }
    }
}

/* ── Parsing APIs (shared with POSIX) ─────────────────────────────── */

int
fd_cstr_to_shmem_lg_page_sz(char const *cstr) {
    if (!cstr) return FD_SHMEM_UNKNOWN_LG_PAGE_SZ;
    if (!fd_cstr_casecmp(cstr, "normal"))   return FD_SHMEM_NORMAL_LG_PAGE_SZ;
    if (!fd_cstr_casecmp(cstr, "huge"))     return FD_SHMEM_HUGE_LG_PAGE_SZ;
    if (!fd_cstr_casecmp(cstr, "gigantic")) return FD_SHMEM_GIGANTIC_LG_PAGE_SZ;
    return FD_SHMEM_UNKNOWN_LG_PAGE_SZ;
}

char const *
fd_shmem_lg_page_sz_to_cstr(int lg_page_sz) {
    switch (lg_page_sz) {
    case FD_SHMEM_NORMAL_LG_PAGE_SZ:   return "normal";
    case FD_SHMEM_HUGE_LG_PAGE_SZ:     return "huge";
    case FD_SHMEM_GIGANTIC_LG_PAGE_SZ: return "gigantic";
    default:                           return "unknown";
    }
}

ulong
fd_cstr_to_shmem_page_sz(char const *cstr) {
    if (!cstr) return FD_SHMEM_UNKNOWN_PAGE_SZ;
    if (!fd_cstr_casecmp(cstr, "normal"))   return FD_SHMEM_NORMAL_PAGE_SZ;
    if (!fd_cstr_casecmp(cstr, "huge"))     return FD_SHMEM_HUGE_PAGE_SZ;
    if (!fd_cstr_casecmp(cstr, "gigantic")) return FD_SHMEM_GIGANTIC_PAGE_SZ;
    return FD_SHMEM_UNKNOWN_PAGE_SZ;
}

char const *
fd_shmem_page_sz_to_cstr(ulong page_sz) {
    switch (page_sz) {
    case FD_SHMEM_NORMAL_PAGE_SZ:   return "normal";
    case FD_SHMEM_HUGE_PAGE_SZ:     return "huge";
    case FD_SHMEM_GIGANTIC_PAGE_SZ: return "gigantic";
    default:                        return "unknown";
    }
}

ulong
fd_shmem_name_len(char const *name) {
    if (!name) return 0UL;
    ulong len = strlen(name);
    return ((0UL < len) && (len < FD_SHMEM_NAME_MAX)) ? len : 0UL;
}

/* ── Administrative APIs ──────────────────────────────────────────── */

int
fd_shmem_create_multi(char const *name,
                      ulong page_sz,
                      ulong sub_cnt,
                      ulong const *sub_page_cnt,
                      ulong const *sub_cpu_idx,
                      ulong mode) {
    (void)mode;

    /* Validate name */
    if (!fd_shmem_name_len(name)) {
        FD_LOG_WARNING(("fd_shmem_create_multi: bad name (%s)", name ? name : "NULL"));
        return EINVAL;
    }

    /* Validate page size — on Windows, only normal pages are supported */
    if (page_sz != FD_SHMEM_NORMAL_PAGE_SZ) {
        /* huge/gigantic fall back to normal on Windows */
        if (page_sz != FD_SHMEM_HUGE_PAGE_SZ && page_sz != FD_SHMEM_GIGANTIC_PAGE_SZ) {
            FD_LOG_WARNING(("fd_shmem_create_multi: bad page_sz (%lu)", page_sz));
            return EINVAL;
        }
        /* Huge/gigantic: log warning and continue with normal pages */
        FD_LOG_WARNING(("fd_shmem_create_multi: huge/gigantic pages not supported on Windows, using normal 4KB pages"));
    }

    /* Validate subregion count and pointers */
    if (sub_cnt == 0 || !sub_page_cnt || !sub_cpu_idx) {
        FD_LOG_WARNING(("fd_shmem_create_multi: invalid sub_cnt or NULL pointers"));
        return EINVAL;
    }

    /* Compute total pages */
    ulong total_pages = 0;
    for (ulong i = 0; i < sub_cnt; i++) {
        if (sub_page_cnt[i] > 0) {
            total_pages += sub_page_cnt[i];
        }
    }
    if (total_pages == 0) {
        FD_LOG_WARNING(("fd_shmem_create_multi: zero total pages"));
        return EINVAL;
    }

    /* Find or create region entry */
    int idx;
    if (!win_shmem_find_or_create(name, page_sz, &idx)) {
        FD_LOG_WARNING(("fd_shmem_create_multi: max regions reached"));
        return ENOMEM;
    }

    /* Check if region already exists (O_EXCL semantics) */
    if (win_shmem_regions[idx].created) {
        FD_LOG_WARNING(("fd_shmem_create_multi: region already exists (%s)", name));
        return EEXIST;
    }

    /* Use normal pages on Windows regardless of requested size */
    ulong actual_page_sz = FD_SHMEM_NORMAL_PAGE_SZ;
    ulong total_bytes = actual_page_sz * total_pages;

    /* Create the named shared memory mapping */
    HANDLE mapping_handle = CreateFileMappingA(
        INVALID_HANDLE_VALUE,
        NULL,
        PAGE_READWRITE,
        (DWORD)(total_bytes >> 32),
        (DWORD)(total_bytes & 0xFFFFFFFF),
        name
    );
    if (mapping_handle == NULL) {
        DWORD err = GetLastError();
        FD_LOG_WARNING(("fd_shmem_create_multi: CreateFileMapping failed (%lu)", (unsigned long)err));
        return err == ERROR_ALREADY_EXISTS ? EEXIST : EINVAL;
    }

    /* Zero-initialize the memory by mapping and memset */
    void *base = MapViewOfFile(
        mapping_handle,
        FILE_MAP_ALL_ACCESS,
        0, 0,
        total_bytes
    );
    if (base == NULL) {
        DWORD err = GetLastError();
        CloseHandle(mapping_handle);
        FD_LOG_WARNING(("fd_shmem_create_multi: MapViewOfFile failed (%lu)", (unsigned long)err));
        return EINVAL;
    }
    memset(base, 0, total_bytes);
    UnmapViewOfFile(base);

    /* Store the region */
    strncpy(win_shmem_regions[idx].name, name, FD_SHMEM_NAME_MAX - 1);
    win_shmem_regions[idx].name[FD_SHMEM_NAME_MAX - 1] = '\0';
    win_shmem_regions[idx].mapping_handle = mapping_handle;
    win_shmem_regions[idx].page_sz = actual_page_sz;
    win_shmem_regions[idx].page_cnt = total_pages;
    win_shmem_regions[idx].ref_cnt = 0;
    win_shmem_regions[idx].created = 1;
    win_shmem_regions[idx].unlink_pending = 0;

    FD_LOG_INFO(("fd_shmem_create_multi: created region %s (%lu pages, %lu KiB)",
                 name, total_pages, (total_bytes >> 10)));
    return 0;
}

int
fd_shmem_update_multi(char const *name,
                      ulong page_sz,
                      ulong sub_cnt,
                      ulong const *sub_page_cnt,
                      ulong const *sub_cpu_idx,
                      ulong mode) {
    /* Update is not supported on Windows — delete and recreate instead.
       For compatibility, just return the same error as create. */
    (void)page_sz; (void)sub_cnt; (void)sub_page_cnt; (void)sub_cpu_idx; (void)mode;
    (void)name;
    FD_LOG_WARNING(("fd_shmem_update_multi: not supported on Windows, use create then unlink"));
    return ENOTSUP;
}

int
fd_shmem_unlink(char const *name, ulong page_sz) {
    if (!fd_shmem_name_len(name)) {
        FD_LOG_WARNING(("fd_shmem_unlink: bad name (%s)", name ? name : "NULL"));
        return EINVAL;
    }

    /* On Windows, unlink marks the region for destruction when refs drop to zero.
       If no refs exist, destroy immediately. */
    int idx;
    if (!win_shmem_find_region(name, page_sz, &idx) &&
        !win_shmem_find_region(name, FD_SHMEM_NORMAL_PAGE_SZ, &idx)) {
        FD_LOG_WARNING(("fd_shmem_unlink: region not found (%s)", name));
        return ENOENT;
    }

    if (win_shmem_regions[idx].ref_cnt > 0) {
        /* Defer destruction */
        win_shmem_regions[idx].unlink_pending = 1;
        FD_LOG_INFO(("fd_shmem_unlink: region %s marked for deletion (pending %d refs)",
                     name, win_shmem_regions[idx].ref_cnt));
        return 0;
    }

    /* No refs — destroy immediately */
    CloseHandle(win_shmem_regions[idx].mapping_handle);
    win_shmem_regions[idx].created = 0;
    win_shmem_regions[idx].mapping_handle = NULL;
    win_shmem_regions[idx].unlink_pending = 0;
    FD_LOG_INFO(("fd_shmem_unlink: destroyed region %s", name));
    return 0;
}

int
fd_shmem_info(char const *name, ulong page_sz, fd_shmem_info_t *opt_info) {
    if (!fd_shmem_name_len(name)) {
        FD_LOG_WARNING(("fd_shmem_info: bad name (%s)", name ? name : "NULL"));
        return EINVAL;
    }

    /* If page_sz is 0, try all sizes */
    if (page_sz == 0) {
        fd_shmem_info_t tmp;
        if (!fd_shmem_info(name, FD_SHMEM_GIGANTIC_PAGE_SZ, &tmp)) return 0;
        if (!fd_shmem_info(name, FD_SHMEM_HUGE_PAGE_SZ, &tmp)) return 0;
        if (!fd_shmem_info(name, FD_SHMEM_NORMAL_PAGE_SZ, &tmp)) return 0;
        return ENOENT;
    }

    if (!fd_shmem_is_page_sz(page_sz)) {
        FD_LOG_WARNING(("fd_shmem_info: bad page_sz (%lu)", page_sz));
        return EINVAL;
    }

    /* Check this specific page size */
    int idx;
    if (!win_shmem_find_region(name, page_sz, &idx) &&
        !win_shmem_find_region(name, FD_SHMEM_NORMAL_PAGE_SZ, &idx)) {
        return ENOENT;
    }

    if (opt_info) {
        opt_info->page_sz = win_shmem_regions[idx].page_sz;
        opt_info->page_cnt = win_shmem_regions[idx].page_cnt;
    }
    return 0;
}

/* ── User APIs ────────────────────────────────────────────────────── */

void *
fd_shmem_join(char const *name,
              int mode,
              int dump,
              fd_shmem_joinleave_func_t join_func,
              void *context,
              fd_shmem_join_info_t *opt_info) {
    (void)dump; (void)join_func; (void)context;

    if (!fd_shmem_name_len(name)) {
        FD_LOG_WARNING(("fd_shmem_join: bad name (%s)", name ? name : "NULL"));
        return NULL;
    }

    if (mode != FD_SHMEM_JOIN_MODE_READ_ONLY && mode != FD_SHMEM_JOIN_MODE_READ_WRITE) {
        FD_LOG_WARNING(("fd_shmem_join: invalid mode (%d)", mode));
        return NULL;
    }

    /* Find region — try each page size until we find a match.  The local
       registry is only a cache: tile processes have their own registry, but
       they must still be able to join a mapping created by the supervisor. */
    int idx = -1;
    ulong found_page_sz = 0;

    /* Try normal pages first (Windows default) */
    if (win_shmem_find_region(name, FD_SHMEM_NORMAL_PAGE_SZ, &idx)) {
        found_page_sz = FD_SHMEM_NORMAL_PAGE_SZ;
    }

    if (idx < 0) {
        HANDLE mapping_handle = OpenFileMappingA(
            FILE_MAP_READ | (mode == FD_SHMEM_JOIN_MODE_READ_WRITE ? FILE_MAP_WRITE : 0),
            FALSE,
            name
        );
        if (mapping_handle == NULL) {
            FD_LOG_WARNING(("fd_shmem_join: region not found (%s), OpenFileMapping failed (%lu)",
                            name, (unsigned long)GetLastError()));
            return NULL;
        }

        /* Map the complete named mapping so the child can discover its size.
           CreateFileMapping does not expose the size through the handle, but
           VirtualQuery reports the size of the mapped view. */
        void *probe = MapViewOfFile(mapping_handle,
                                    FILE_MAP_READ,
                                    0, 0, 0);
        if (probe == NULL) {
            CloseHandle(mapping_handle);
            FD_LOG_WARNING(("fd_shmem_join: MapViewOfFile probe failed for %s (%lu)",
                            name, (unsigned long)GetLastError()));
            return NULL;
        }
        MEMORY_BASIC_INFORMATION mbi;
        SIZE_T queried = VirtualQuery(probe, &mbi, sizeof(mbi));
        SIZE_T mapped_bytes = 0;
        void *cursor = probe;
        void *allocation_base = queried != 0 ? mbi.AllocationBase : NULL;
        while (queried != 0 && allocation_base != NULL &&
               mbi.AllocationBase == allocation_base &&
               mbi.State == MEM_COMMIT && mbi.RegionSize != 0) {
            mapped_bytes += mbi.RegionSize;
            cursor = (void *)((char *)cursor + mbi.RegionSize);
            queried = VirtualQuery(cursor, &mbi, sizeof(mbi));
        }
        UnmapViewOfFile(probe);
        if (mapped_bytes == 0 ||
            ((ulong)mapped_bytes % FD_SHMEM_NORMAL_PAGE_SZ) != 0) {
            CloseHandle(mapping_handle);
            FD_LOG_WARNING(("fd_shmem_join: could not determine mapping size for %s", name));
            return NULL;
        }

        if (!win_shmem_find_or_create(name, FD_SHMEM_NORMAL_PAGE_SZ, &idx)) {
            CloseHandle(mapping_handle);
            FD_LOG_WARNING(("fd_shmem_join: max regions reached"));
            return NULL;
        }
        win_shmem_regions[idx].mapping_handle = mapping_handle;
        win_shmem_regions[idx].page_sz = FD_SHMEM_NORMAL_PAGE_SZ;
        win_shmem_regions[idx].page_cnt = (ulong)mapped_bytes / FD_SHMEM_NORMAL_PAGE_SZ;
        win_shmem_regions[idx].ref_cnt = 0;
        win_shmem_regions[idx].created = 1;
        win_shmem_regions[idx].unlink_pending = 0;
        strncpy(win_shmem_regions[idx].name, name, FD_SHMEM_NAME_MAX - 1);
        win_shmem_regions[idx].name[FD_SHMEM_NAME_MAX - 1] = '\0';
        found_page_sz = FD_SHMEM_NORMAL_PAGE_SZ;
    }

    /* Increment reference count */
    win_shmem_regions[idx].ref_cnt++;

    /* Map the region into our address space */
    HANDLE mapping_handle = win_shmem_regions[idx].mapping_handle;
    ulong page_cnt = win_shmem_regions[idx].page_cnt;
    ulong page_sz = win_shmem_regions[idx].page_sz;
    ulong total_bytes = page_sz * page_cnt;
    /* A cross-process join maps the complete section.  The size discovered
       by VirtualQuery is metadata only; it can describe a partial view and
       must not be used to truncate the actual workspace mapping. */
    if (found_page_sz != 0 && idx >= 0 &&
        win_shmem_regions[idx].mapping_handle != NULL &&
        win_shmem_regions[idx].ref_cnt == 1) {
        total_bytes = 0;
    }

    void *shmem = MapViewOfFile(
        mapping_handle,
        (mode == FD_SHMEM_JOIN_MODE_READ_WRITE) ? FILE_MAP_ALL_ACCESS : FILE_MAP_READ,
        0, 0,
        total_bytes
    );
    if (shmem == NULL) {
        DWORD err = GetLastError();
        win_shmem_regions[idx].ref_cnt--;
        FD_LOG_WARNING(("fd_shmem_join: MapViewOfFile failed for %s (%lu)", name, (unsigned long)err));
        return NULL;
    }
    for (int i = 0; i < WIN_SHMEM_MAX_JOINS; i++) {
        if (win_shmem_joins[i].addr == NULL) {
            win_shmem_joins[i].addr = shmem;
            win_shmem_joins[i].region_idx = idx;
            break;
        }
        if (i == WIN_SHMEM_MAX_JOINS - 1) {
            UnmapViewOfFile(shmem);
            win_shmem_regions[idx].ref_cnt--;
            FD_LOG_WARNING(("fd_shmem_join: max joins reached"));
            return NULL;
        }
    }
    FD_LOG_INFO(("fd_shmem_join: joined %s at %p (%lu pages, map_bytes=%lu)",
                 name, shmem, page_cnt, total_bytes));

    /* Fill in opt_info if requested */
    if (opt_info) {
        opt_info->ref_cnt = (long)win_shmem_regions[idx].ref_cnt;
        opt_info->join = shmem;
        opt_info->shmem = shmem;
        opt_info->page_sz = page_sz;
        opt_info->page_cnt = page_cnt;
        opt_info->mode = mode;
        opt_info->hash = (uint)fd_hash(0UL, name, FD_SHMEM_NAME_MAX);
        strncpy(opt_info->name, name, FD_SHMEM_NAME_MAX);
        opt_info->name[FD_SHMEM_NAME_MAX - 1] = '\0';
    }

    return shmem;
}

int
fd_shmem_leave(void *join,
               fd_shmem_joinleave_func_t leave_func,
               void *context) {
    (void)leave_func; (void)context;

    if (!join) {
        FD_LOG_WARNING(("fd_shmem_leave: NULL join"));
        return 1;
    }

    /* The process can have several simultaneous views.  Track the exact
       returned address so leaving one view decrements its own region. */
    for (int j = 0; j < WIN_SHMEM_MAX_JOINS; j++) {
        if (win_shmem_joins[j].addr != join) continue;
        int i = win_shmem_joins[j].region_idx;
        win_shmem_joins[j].addr = NULL;
        win_shmem_regions[i].ref_cnt--;
        UnmapViewOfFile(join);

        /* If region was unlinked and ref count reached zero, destroy it */
        if (win_shmem_regions[i].ref_cnt == 0 && win_shmem_regions[i].unlink_pending) {
            CloseHandle(win_shmem_regions[i].mapping_handle);
            win_shmem_regions[i].created = 0;
            win_shmem_regions[i].mapping_handle = NULL;
            win_shmem_regions[i].unlink_pending = 0;
            FD_LOG_INFO(("fd_shmem_leave: destroyed region %s (final ref)",
                         win_shmem_regions[i].name));
        }
        return 0;
    }

    FD_LOG_WARNING(("fd_shmem_leave: join handle not recognized"));
    return 1;
}

int
fd_shmem_join_query_by_name(char const *name, fd_shmem_join_info_t *opt_info) {
    if (!fd_shmem_name_len(name)) return EINVAL;

    int idx;
    if (!win_shmem_find_region(name, FD_SHMEM_NORMAL_PAGE_SZ, &idx)) {
        return ENOENT;
    }

    if (opt_info) {
        opt_info->ref_cnt = (long)win_shmem_regions[idx].ref_cnt;
        opt_info->join = NULL; /* We don't track individual join pointers */
        opt_info->shmem = NULL;
        opt_info->page_sz = win_shmem_regions[idx].page_sz;
        opt_info->page_cnt = win_shmem_regions[idx].page_cnt;
        opt_info->mode = FD_SHMEM_JOIN_MODE_READ_WRITE;
        opt_info->hash = (uint)fd_hash(0UL, name, FD_SHMEM_NAME_MAX);
        strncpy(opt_info->name, name, FD_SHMEM_NAME_MAX);
        opt_info->name[FD_SHMEM_NAME_MAX - 1] = '\0';
    }
    return 0;
}

int
fd_shmem_join_query_by_join(void const *join, fd_shmem_join_info_t *opt_info) {
    (void)join;
    return ENOENT; /* Windows doesn't support this efficiently */
}

int
fd_shmem_join_query_by_addr(void const *addr, ulong sz, fd_shmem_join_info_t *opt_info) {
    (void)addr; (void)sz;
    return ENOENT; /* Windows doesn't support this efficiently */
}

int
fd_shmem_join_anonymous(char const *name,
                        int mode,
                        void *join,
                        void *mem,
                        ulong page_sz,
                        ulong page_cnt) {
    (void)name; (void)mode; (void)join; (void)mem; (void)page_sz; (void)page_cnt;
    FD_LOG_WARNING(("fd_shmem_join_anonymous: not supported on Windows"));
    return ENOTSUP;
}

int
fd_shmem_leave_anonymous(void *join, fd_shmem_join_info_t *opt_info) {
    (void)join; (void)opt_info;
    FD_LOG_WARNING(("fd_shmem_leave_anonymous: not supported on Windows"));
    return ENOTSUP;
}

/* ── NUMA APIs (no-ops on Windows) ───────────────────────────────── */

ulong fd_shmem_numa_cnt(void) { return 1; }
ulong fd_shmem_cpu_cnt(void) { return 1; }
ulong fd_shmem_numa_idx(ulong cpu_idx) { (void)cpu_idx; return 0; }
ulong fd_shmem_cpu_idx(ulong numa_idx) { (void)numa_idx; return 0; }

int
fd_shmem_numa_validate(void const *mem, ulong page_sz, ulong page_cnt, ulong cpu_idx) {
    (void)mem; (void)page_sz; (void)page_cnt; (void)cpu_idx;
    return 0; /* Always passes on Windows */
}

/* ── Raw page allocation (anonymous, not shared) ──────────────────── */

void *
fd_shmem_acquire_multi(ulong page_sz,
                       ulong sub_cnt,
                       ulong const *sub_page_cnt,
                       ulong const *sub_cpu_idx) {
    /* Use standard heap allocation on Windows — not shared memory */
    (void)page_sz; (void)sub_cpu_idx;

    if (!fd_shmem_is_page_sz(page_sz)) {
        FD_LOG_WARNING(("fd_shmem_acquire_multi: bad page_sz (%lu)", page_sz));
        return NULL;
    }
    if (sub_cnt == 0 || !sub_page_cnt) {
        FD_LOG_WARNING(("fd_shmem_acquire_multi: invalid sub_cnt or NULL pointer"));
        return NULL;
    }

    ulong total_pages = 0;
    for (ulong i = 0; i < sub_cnt; i++) {
        total_pages += sub_page_cnt[i];
    }
    if (total_pages == 0) {
        FD_LOG_WARNING(("fd_shmem_acquire_multi: zero total pages"));
        return NULL;
    }

    ulong total_bytes = page_sz * total_pages;
    void *mem = VirtualAlloc(NULL, total_bytes, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    if (mem == NULL) {
        FD_LOG_WARNING(("fd_shmem_acquire_multi: VirtualAlloc failed"));
        return NULL;
    }
    memset(mem, 0, total_bytes);
    return mem;
}

int
fd_shmem_release(void *mem, ulong page_sz, ulong page_cnt) {
    (void)page_sz; (void)page_cnt;

    if (!mem) {
        FD_LOG_WARNING(("fd_shmem_release: NULL mem"));
        return -1;
    }

    ulong total_bytes = page_sz * page_cnt;
    BOOL result = VirtualFree(mem, 0, MEM_RELEASE);
    if (!result) {
        FD_LOG_WARNING(("fd_shmem_release: VirtualFree failed"));
        return -1;
    }
    return 0;
}

/* ── Iterators ────────────────────────────────────────────────────── */

fd_shmem_join_info_t const *
fd_shmem_iter_begin(void) {
    /* Not fully supported on Windows — return NULL */
    return NULL;
}

fd_shmem_join_info_t const *
fd_shmem_iter_next(fd_shmem_join_info_t const *iter) {
    (void)iter;
    return NULL;
}

/* ── Boot/Halt ────────────────────────────────────────────────────── */

void
fd_shmem_private_boot(int *pargc, char ***pargv) {
    FD_LOG_INFO(("fd_shmem: booting on Windows"));
    (void)fd_env_strip_cmdline_cstr(pargc, pargv, "--shmem-path", "FD_SHMEM_PATH", "/tmp/.fd");
    FD_LOG_INFO(("fd_shmem: using Windows shared memory backend"));
    FD_LOG_INFO(("fd_shmem: boot success"));
}

void
fd_shmem_private_halt(void) {
    FD_LOG_INFO(("fd_shmem: halting on Windows"));

    /* Clean up all remaining regions */
    for (int i = 0; i < win_shmem_region_cnt; i++) {
        if (win_shmem_regions[i].created && win_shmem_regions[i].mapping_handle) {
            CloseHandle(win_shmem_regions[i].mapping_handle);
            win_shmem_regions[i].created = 0;
            win_shmem_regions[i].mapping_handle = NULL;
        }
    }
    win_shmem_region_cnt = 0;

    FD_LOG_INFO(("fd_shmem: halt success"));
}
