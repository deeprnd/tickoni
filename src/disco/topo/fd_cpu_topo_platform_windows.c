/* Windows CPU topology implementation.
 *
 * This provides real CPU and NUMA node discovery on Windows, replacing the
 * previous stub that reported a single CPU and NUMA node.
 *
 * Uses GetActiveProcessorCount + GetLogicalProcessorInformationEx(RelationNumaNode)
 * to enumerate CPUs and NUMA nodes. Falls back to GetSystemInfo on older systems.
 */

#include "fd_cpu_topo.h"
#include "../../util/shmem/fd_shmem_private.h"
#include "../../util/tile/fd_tile_private.h"

#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

/* ── Windows CPU/NUMA discovery ────────────────────────────────────────── */

static ulong
fd_topo_cpu_cnt( void ) {
    DWORD cnt = GetActiveProcessorCount( ALL_PROCESSOR_GROUPS );
    if( cnt == 0 ) {
        SYSTEM_INFO si;
        GetSystemInfo( &si );
        cnt = si.dwNumberOfProcessors;
        if( cnt == 0 )
            FD_LOG_ERR(( "fd_topo_cpus_init: unable to determine CPU count" ));
    }
    return (ulong)cnt;
}

static int
fd_topo_cpus_online( ulong cpu_idx ) {
    (void)cpu_idx;
    return 1;
}

void
fd_topo_cpus_init_platform( fd_topo_cpus_t * cpus ) {
    /* ── Count CPUs ──────────────────────────────────────────────────── */
    cpus->cpu_cnt = fd_topo_cpu_cnt();
    if( FD_UNLIKELY( cpus->cpu_cnt > FD_TILE_MAX ) )
        FD_LOG_ERR(( "unsupported system: Firedancer supports up to %lu CPUs", FD_TILE_MAX ));

    /* ── Detect NUMA topology via GetLogicalProcessorInformationEx ───── */
    /* RelationNumaNode returns SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX
     * with NUMA_NODE_RELATIONSHIP containing GroupMasks[].
     * Available on Windows Vista+. */
    ULONG numa_cnt = 1UL;
    ULONG node_ids[ FD_TILE_MAX ];
    ULONG node_cnt = 0;

    PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX buf = NULL;
    DWORD buf_sz = 0;

    if( GetLogicalProcessorInformationEx( RelationNumaNode, NULL, &buf_sz ) ||
        GetLastError() == ERROR_INSUFFICIENT_BUFFER ) {
        buf = (PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX)malloc( buf_sz );
        if( buf ) {
            if( GetLogicalProcessorInformationEx( RelationNumaNode, buf, &buf_sz ) ) {
                PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX cur = buf;
                while( (ULONG)((char*)cur - (char*)buf) < buf_sz ) {
                    if( cur->Relationship == RelationNumaNode ) {
                        ULONG node_num = cur->NumaNode.NodeNumber;
                        int found = 0;
                        for( ULONG j = 0UL; j < node_cnt; j++ )
                            if( node_num == node_ids[ j ] ) { found = 1; break; }
                        if( !found && node_cnt < FD_TILE_MAX )
                            node_ids[ node_cnt++ ] = node_num;
                    }
                    cur = (PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX)( (char*)cur + cur->Size );
                }
                if( node_cnt > 0 ) numa_cnt = node_cnt;
            }
            free( buf );
            buf = NULL;
        }
    }
    cpus->numa_node_cnt = (ulong)numa_cnt;

    /* ── Build per-CPU NUMA mapping ─────────────────────────────────── */
    if( numa_cnt > 1 ) {
        /* Re-fetch to walk the NUMA entries again */
        buf_sz = 0;
        buf = (PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX)malloc( buf_sz );
        if( !GetLogicalProcessorInformationEx( RelationNumaNode, buf, &buf_sz ) ||
            GetLastError() != ERROR_INSUFFICIENT_BUFFER ) {
            free( buf );
            buf = NULL;
        }

        /* Map each CPU to its NUMA node by checking GroupMasks[].
         * Each NUMA_NODE_RELATIONSHIP lists which processor groups belong
         * to that node. GetActiveProcessorCount per group maps CPUs. */
        if( buf ) {
            PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX cur = buf;
            DWORD offset = 0;
            while( (ULONG)((char*)cur - (char*)buf) < buf_sz ) {
                if( cur->Relationship == RelationNumaNode ) {
                    for( WORD g = 0; g < cur->NumaNode.GroupCount; g++ ) {
                        KAFFINITY mask = cur->NumaNode.GroupMasks[ g ].Mask;
                        for( ulong cpu_bit = 0; cpu_bit < 64; cpu_bit++ ) {
                            if( mask & (KAFFINITY)( 1ULL << cpu_bit ) ) {
                                ulong cpu_idx = offset + cpu_bit;
                                if( cpu_idx < cpus->cpu_cnt )
                                    cpus->cpu[ cpu_idx ].numa_node =
                                        cur->NumaNode.NodeNumber % numa_cnt;
                            }
                        }
                    }
                    offset += cur->NumaNode.GroupCount * 64;
                }
                cur = (PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX)( (char*)cur + cur->Size );
            }
            free( buf );
            buf = NULL;
        }
    }

    /* ── Fill per-CPU entries ───────────────────────────────────────── */
    for( ulong i = 0UL; i < cpus->cpu_cnt; i++ ) {
        cpus->cpu[ i ].idx      = i;
        cpus->cpu[ i ].online   = fd_topo_cpus_online( i );
        cpus->cpu[ i ].numa_node = 0UL; /* Default to node 0 */
        cpus->cpu[ i ].sibling  = ULONG_MAX;
    }
}

void
fd_topo_cpus_printf_platform( fd_topo_cpus_t * cpus ) {
    for( ulong i = 0UL; i < cpus->cpu_cnt; i++ ) {
        FD_LOG_NOTICE(( "cpu%lu: online=%i sibling=%lu numa_node=%lu",
                        i, cpus->cpu[ i ].online,
                        cpus->cpu[ i ].sibling,
                        cpus->cpu[ i ].numa_node ));
    }
}
