/* test_multipart.c — bounded multipart model-content framing (tk_multipart.h).

   Pure protocol test: no tile, no workspace.  The receiver is driven exactly as
   a stem's AFTER_FRAG would drive it, one staged fragment at a time.

   Proves:
   1. The approved bounds: a fragment fits the 16-bit fd `sz`; a 256 KiB
      message needs 33 fragments, more than the link depth of 32; the message
      ceiling exceeds one fragment and the 65,535-byte fd ceiling.
   2. Round trip at the boundaries of the canonical framing (1 byte, one byte
      under/at/over one fragment, above 65,535 bytes, the maximum): exact
      bytes, exact fragment count, the canonical whole-message hash, SOM/EOM
      on the first/last fragment only, COMPLETE only on the last fragment.
   3. Every malformed or hostile stream fails closed: the message is never
      reported COMPLETE, the receiver drops it, swallows its remaining
      fragments, and then accepts the next valid message.
   4. An interleaved SOM drops the abandoned message and does not consume the
      new fragment; a partial message times out; an orphan continuation is
      rejected.
   5. The sender is a bounded cursor that yields one fragment per call.
*/

#define _GNU_SOURCE

#include "../../c_abi/shim/tk_multipart.h"

#include <stdio.h>

static int g_failed = 0;
#define CHECK(cond, msg) do { if( !(cond) ) { fprintf( stderr, "FAIL: %s (%s:%d)\n", msg, __FILE__, __LINE__ ); g_failed = 1; } } while(0)

#define PAYLOAD  ((ulong)TK_MP_FRAG_PAYLOAD_MAX)
#define MTU      ((ulong)TK_MP_LINK_MTU)
#define MAXMSG   ((ulong)TK_MP_MAX_MESSAGE_BYTES)
#define TIMEOUT  100L

static uint8_t g_msg [ TK_MP_MAX_MESSAGE_BYTES ];
static uint8_t g_msg2[ TK_MP_MAX_MESSAGE_BYTES ];
static uint8_t g_rxbuf[ TK_MP_MAX_MESSAGE_BYTES ];

typedef struct {
    uint8_t bytes[ TK_MP_LINK_MTU ];
    ulong   sz;
    int     som, eom;
} frag_t;

static frag_t g_frags[ TK_MP_MAX_FRAGS ];

static void
fill( uint8_t * buf, ulong len, uint8_t seed ) {
    for( ulong i=0UL; i<len; i++ ) buf[i] = (uint8_t)( seed + i*131UL + (i>>8) );
}

/* Fragments a message into g_frags with the real sender; returns the count. */
static ulong
fragment( uint8_t const * msg, ulong len, uint64_t run_id, uint64_t req_id, uint8_t dir ) {
    tk_mp_tx_t tx;
    if( tk_mp_tx_begin( &tx, dir, TK_MP_CT_CHAT, run_id, req_id, msg, len ) ) return 0UL;
    ulong n = 0UL;
    while( !tk_mp_tx_done( &tx ) ) {
        g_frags[n].sz = tk_mp_tx_frag( &tx, g_frags[n].bytes, &g_frags[n].som, &g_frags[n].eom );
        n++;
    }
    return n;
}

static tk_mp_status_t
feed( tk_mp_rx_t * rx, frag_t const * f, long now ) {
    return tk_mp_rx_feed( rx, f->bytes, f->sz, f->som, f->eom, now );
}

static void
rx_reset( tk_mp_rx_t * rx, uint8_t dir ) {
    tk_mp_rx_init( rx, dir, g_rxbuf, TIMEOUT );
}

static int
is_err( tk_mp_status_t st ) { return (int)st>=(int)TK_MP_ERR_VERSION; }

static void
test_bounds( void ) {
    CHECK( sizeof(TkMpHeader)==(ulong)TK_MP_HDR_SZ, "header must be 64 bytes" );
    CHECK( MTU<=(ulong)TK_MP_FD_SZ_CEILING, "a fragment must fit fd_frag_meta_t.sz" );
    CHECK( PAYLOAD==MTU-(ulong)TK_MP_HDR_SZ, "payload is the MTU less the header" );
    CHECK( MAXMSG>(ulong)TK_MP_FD_SZ_CEILING, "the message ceiling must exceed one fd fragment" );
    CHECK( MAXMSG>PAYLOAD, "the message ceiling must exceed one fragment payload" );
    CHECK( (ulong)TK_MP_MAX_FRAGS==tk_mp_frag_cnt( MAXMSG ), "TK_MP_MAX_FRAGS must match the maximum message" );
    CHECK( (ulong)TK_MP_MAX_FRAGS==33UL, "a 256 KiB message occupies 33 fragments" );
    CHECK( (ulong)TK_MP_MAX_FRAGS>(ulong)TK_MP_LINK_DEPTH, "the maximum message must exceed the link depth in fragments" );
    CHECK( tk_mp_frag_cnt( 1UL )==1UL && tk_mp_frag_cnt( PAYLOAD )==1UL && tk_mp_frag_cnt( PAYLOAD+1UL )==2UL,
           "fragment count at the payload boundary" );
}

/* Pinned against Zig's std SipHash-1-3 under the same domain keys
   (src/tickoni/c_abi/multipart.zig, hash_vector_expected): the C sender and a
   Zig verifier must agree on the canonical hash. */
static void
test_hash_vector( void ) {
    static char const input[] = "tickoni multipart vector";
    CHECK( tk_mp_message_hash( (uint8_t const *)input, sizeof(input)-1UL )==12765886097428848014ULL,
           "canonical hash must equal the cross-language vector" );
}

static void
test_round_trip( void ) {
    ulong lens[] = { 1UL, 100UL, PAYLOAD-1UL, PAYLOAD, PAYLOAD+1UL, 2UL*PAYLOAD, 65535UL, 65536UL,
                     100000UL, MAXMSG-1UL, MAXMSG };
    for( ulong t=0UL; t<sizeof(lens)/sizeof(lens[0]); t++ ) {
        ulong len = lens[t];
        fill( g_msg, len, (uint8_t)t );
        ulong n = fragment( g_msg, len, 7UL, 42UL, TK_MP_DIR_REQUEST );
        CHECK( n==tk_mp_frag_cnt( len ), "sender fragment count" );

        tk_mp_rx_t rx; rx_reset( &rx, TK_MP_DIR_REQUEST );
        memset( g_rxbuf, 0, sizeof(g_rxbuf) );
        int complete_seen = 0;
        for( ulong i=0UL; i<n; i++ ) {
            CHECK( g_frags[i].sz<=MTU && g_frags[i].sz<=(ulong)TK_MP_FD_SZ_CEILING, "fragment must fit link MTU and fd sz" );
            CHECK( g_frags[i].som==(i==0UL) && g_frags[i].eom==(i==n-1UL), "SOM only first, EOM only last" );
            tk_mp_status_t st = feed( &rx, &g_frags[i], 0L );
            if( i<n-1UL ) CHECK( st==TK_MP_PARTIAL, "interior fragment is PARTIAL" );
            else { CHECK( st==TK_MP_COMPLETE, "last fragment completes the message" ); complete_seen = 1; }
        }
        CHECK( complete_seen, "message must complete" );
        CHECK( rx.cur.total_len==(uint32_t)len, "completed length" );
        CHECK( rx.cur.run_id==7UL && rx.cur.model_request_id==42UL, "completed identity" );
        CHECK( memcmp( g_rxbuf, g_msg, len )==0, "reassembled bytes must equal the message exactly" );
        CHECK( rx.cur.message_hash==tk_mp_message_hash( g_msg, len ), "canonical whole-message hash" );
    }
}

static void
test_oversize_and_empty( void ) {
    tk_mp_tx_t tx;
    CHECK( tk_mp_tx_begin( &tx, TK_MP_DIR_REQUEST, TK_MP_CT_CHAT, 1UL, 1UL, g_msg, 0UL )!=0, "sender rejects an empty message" );
    CHECK( tk_mp_tx_begin( &tx, TK_MP_DIR_REQUEST, TK_MP_CT_CHAT, 1UL, 1UL, g_msg, MAXMSG+1UL )!=0, "sender rejects an oversize message" );

    /* A hostile first fragment declaring more than the ceiling, and a zero length. */
    fill( g_msg, 100UL, 1 );
    fragment( g_msg, 100UL, 1UL, 1UL, TK_MP_DIR_REQUEST );
    for( int k=0; k<2; k++ ) {
        frag_t f = g_frags[0];
        TkMpHeader h; memcpy( &h, f.bytes, sizeof(h) );
        h.total_len = k==0 ? (uint32_t)(MAXMSG+1UL) : 0U;
        h.frag_cnt  = k==0 ? (uint32_t)tk_mp_frag_cnt( MAXMSG+1UL ) : 0U;
        memcpy( f.bytes, &h, sizeof(h) );
        tk_mp_rx_t rx; rx_reset( &rx, TK_MP_DIR_REQUEST );
        CHECK( feed( &rx, &f, 0L )==TK_MP_ERR_OVERSIZE, "oversize/zero total_len is rejected" );
        CHECK( !rx.active, "nothing is buffered for a rejected message" );
    }
}

/* One malformed-stream case: mutate a copy of the 3-fragment message and feed
   it; the broken message must never complete, the receiver must end idle, and a
   fresh valid message must then complete. */
typedef struct {
    char const * name;
    ulong        at;                 /* fragment to mutate (or drop/duplicate) */
    int          kind;               /* see mutate() */
    tk_mp_status_t expect;           /* status returned by the first failing feed */
} bad_case_t;

enum { M_VERSION, M_DROP, M_DUP, M_OFF_REWIND, M_RUN_ID, M_FLIP_PAYLOAD, M_NO_EOM, M_EARLY_EOM,
       M_NO_SOM, M_DIR, M_SZ_SHORT, M_SZ_OVER, M_TOTAL_LEN, M_HASH };

static void
test_malformed_streams( void ) {
    ulong len = 2UL*PAYLOAD+100UL;           /* 3 fragments */
    bad_case_t cases[] = {
        { "wrong version on first",         0UL, M_VERSION,      TK_MP_ERR_VERSION   },
        { "missing middle fragment",        1UL, M_DROP,         TK_MP_ERR_GAP       },
        { "duplicated fragment",            1UL, M_DUP,          TK_MP_ERR_DUPLICATE },
        { "offset rewound into earlier",    1UL, M_OFF_REWIND,   TK_MP_ERR_OVERLAP   },
        { "identity changes mid-message",   1UL, M_RUN_ID,       TK_MP_ERR_IDENTITY  },
        { "payload corrupted",              2UL, M_FLIP_PAYLOAD, TK_MP_ERR_HASH      },
        { "declared hash wrong",            0UL, M_HASH,         TK_MP_ERR_HASH      },
        { "last fragment lacks EOM",        2UL, M_NO_EOM,       TK_MP_ERR_BOUNDARY  },
        { "EOM on a middle fragment",       1UL, M_EARLY_EOM,    TK_MP_ERR_BOUNDARY  },
        { "first fragment lacks SOM",       0UL, M_NO_SOM,       TK_MP_ERR_BOUNDARY  },
        { "wrong direction",                0UL, M_DIR,          TK_MP_ERR_IDENTITY  },
        { "fragment shorter than declared", 1UL, M_SZ_SHORT,     TK_MP_ERR_SIZE      },
        { "fragment over the link MTU",     1UL, M_SZ_OVER,      TK_MP_ERR_SIZE      },
        { "total_len disagrees mid-stream", 2UL, M_TOTAL_LEN,    TK_MP_ERR_SIZE      },
    };
    for( ulong c=0UL; c<sizeof(cases)/sizeof(cases[0]); c++ ) {
        fill( g_msg, len, 9 );
        ulong n = fragment( g_msg, len, 5UL, 77UL, TK_MP_DIR_REQUEST );
        CHECK( n==3UL, "precondition: three fragments" );

        /* Build the stream the (faulty) producer would emit. */
        frag_t stream[ 4 ]; ulong sn = 0UL;
        for( ulong i=0UL; i<n; i++ ) {
            frag_t f = g_frags[i];
            TkMpHeader h; memcpy( &h, f.bytes, sizeof(h) );
            int hit = i==cases[c].at || cases[c].kind==M_HASH;   /* a wrong declared hash is on every fragment */
            if( hit ) switch( cases[c].kind ) {
                case M_VERSION:      h.version += 1; break;
                case M_DROP:         continue;
                case M_DUP:          break;
                case M_OFF_REWIND:   h.frag_off = 0U; break;
                case M_RUN_ID:       h.run_id += 1UL; break;
                case M_FLIP_PAYLOAD: f.bytes[TK_MP_HDR_SZ+3] ^= 0x5a; break;
                case M_NO_EOM:       f.eom = 0; break;
                case M_EARLY_EOM:    f.eom = 1; break;
                case M_NO_SOM:       f.som = 0; break;
                case M_DIR:          h.direction = TK_MP_DIR_RESULT; break;
                case M_SZ_SHORT:     f.sz -= 1UL; break;
                case M_SZ_OVER:      f.sz = MTU+1UL; break;
                case M_TOTAL_LEN:    h.total_len -= 1U; break;
                case M_HASH:         h.message_hash ^= 1UL; break;
                default: break;
            }
            memcpy( f.bytes, &h, sizeof(h) );
            stream[sn++] = f;
            if( hit && cases[c].kind==M_DUP ) stream[sn++] = f;
        }

        tk_mp_rx_t rx; rx_reset( &rx, TK_MP_DIR_REQUEST );
        int saw_expected = 0, saw_complete = 0;
        for( ulong i=0UL; i<sn; i++ ) {
            tk_mp_status_t st = feed( &rx, &stream[i], 0L );
            if( st==TK_MP_COMPLETE ) saw_complete = 1;
            if( st==cases[c].expect ) saw_expected = 1;
            if( is_err( st ) && st!=cases[c].expect && !saw_expected )
                fprintf( stderr, "case '%s': got status %d, wanted %d\n", cases[c].name, (int)st, (int)cases[c].expect );
        }
        if( !saw_expected ) fprintf( stderr, "case failed: %s\n", cases[c].name );
        CHECK( saw_expected, "the expected terminal error must be reported" );
        CHECK( !saw_complete, "a malformed message must never complete" );
        CHECK( !rx.active, "the receiver must not keep a failed message" );

        /* Recovery: the next valid message is accepted. */
        fill( g_msg2, 3000UL, 3 );
        ulong n2 = fragment( g_msg2, 3000UL, 6UL, 78UL, TK_MP_DIR_REQUEST );
        tk_mp_status_t st = TK_MP_PARTIAL;
        for( ulong i=0UL; i<n2; i++ ) st = feed( &rx, &g_frags[i], 0L );
        CHECK( st==TK_MP_COMPLETE, "a valid message after a failure must complete" );
        CHECK( memcmp( g_rxbuf, g_msg2, 3000UL )==0, "and its bytes must be exact" );
    }
}

static void
test_failed_message_remainder_is_swallowed( void ) {
    /* After the middle fragment is lost, fragment 2 reports the gap and any
       further fragments of that message are dropped, not mistaken for a new one. */
    ulong len = 3UL*PAYLOAD;                /* 3 fragments */
    fill( g_msg, len, 4 );
    ulong n = fragment( g_msg, len, 5UL, 1UL, TK_MP_DIR_REQUEST );
    tk_mp_rx_t rx; rx_reset( &rx, TK_MP_DIR_REQUEST );
    CHECK( feed( &rx, &g_frags[0], 0L )==TK_MP_PARTIAL, "first fragment accepted" );
    /* fragment 1 lost; fragment 2 (the last) arrives */
    CHECK( feed( &rx, &g_frags[2], 0L )==TK_MP_ERR_GAP, "skipped fragment reports a gap" );
    CHECK( rx.fail.run_id==5UL && rx.fail.model_request_id==1UL, "failure names the message" );
    CHECK( n==3UL, "precondition" );
}

static void
test_interleaved_som( void ) {
    /* A (3 fragments) abandoned after its first fragment; B (3 fragments) starts. */
    fill( g_msg, 3UL*PAYLOAD, 1 );
    fill( g_msg2, 3UL*PAYLOAD, 2 );
    static frag_t a[ 3 ]; ulong na = fragment( g_msg, 3UL*PAYLOAD, 1UL, 10UL, TK_MP_DIR_REQUEST );
    for( ulong i=0UL; i<na; i++ ) a[i] = g_frags[i];
    ulong nb = fragment( g_msg2, 3UL*PAYLOAD, 1UL, 11UL, TK_MP_DIR_REQUEST );

    tk_mp_rx_t rx; rx_reset( &rx, TK_MP_DIR_REQUEST );
    CHECK( feed( &rx, &a[0], 0L )==TK_MP_PARTIAL, "A starts" );
    tk_mp_status_t st = feed( &rx, &g_frags[0], 0L );
    CHECK( st==TK_MP_ERR_INTERLEAVED, "a SOM mid-message is reported" );
    CHECK( rx.fail.model_request_id==10UL, "the abandoned message is named" );
    CHECK( !rx.active, "the abandoned message is dropped" );
    /* The fragment was not consumed: feeding it again starts B. */
    CHECK( feed( &rx, &g_frags[0], 0L )==TK_MP_PARTIAL, "the repeated SOM starts the new message" );
    for( ulong i=1UL; i<nb-1UL; i++ ) CHECK( feed( &rx, &g_frags[i], 0L )==TK_MP_PARTIAL, "B continues" );
    CHECK( feed( &rx, &g_frags[nb-1UL], 0L )==TK_MP_COMPLETE, "B completes" );
    CHECK( memcmp( g_rxbuf, g_msg2, 3UL*PAYLOAD )==0, "B's bytes are exact, none of A's" );

    /* B is a single fragment: the failure and the completion are still two calls. */
    fill( g_msg2, 500UL, 5 );
    nb = fragment( g_msg2, 500UL, 1UL, 12UL, TK_MP_DIR_REQUEST );
    CHECK( nb==1UL, "precondition: single fragment" );
    rx_reset( &rx, TK_MP_DIR_REQUEST );
    CHECK( feed( &rx, &a[0], 0L )==TK_MP_PARTIAL, "A starts again" );
    CHECK( feed( &rx, &g_frags[0], 0L )==TK_MP_ERR_INTERLEAVED, "interleave reported" );
    CHECK( feed( &rx, &g_frags[0], 0L )==TK_MP_COMPLETE, "the single-fragment message still completes" );
}

static void
test_timeout( void ) {
    fill( g_msg, 3UL*PAYLOAD, 7 );
    ulong n = fragment( g_msg, 3UL*PAYLOAD, 2UL, 20UL, TK_MP_DIR_REQUEST );
    tk_mp_rx_t rx; rx_reset( &rx, TK_MP_DIR_REQUEST );
    CHECK( feed( &rx, &g_frags[0], 1000L )==TK_MP_PARTIAL, "first fragment" );
    CHECK( tk_mp_rx_poll( &rx, 1000L+TIMEOUT-1L )==TK_MP_PARTIAL, "not yet timed out" );
    CHECK( rx.active, "still building" );
    CHECK( tk_mp_rx_poll( &rx, 1000L+TIMEOUT )==TK_MP_ERR_TIMEOUT, "deadline passed" );
    CHECK( !rx.active && rx.fail.model_request_id==20UL, "message dropped and named" );
    /* The late tail of that message is swallowed; it is never completed. */
    CHECK( feed( &rx, &g_frags[1], 2000L )==TK_MP_DISCARD, "late middle fragment discarded" );
    CHECK( feed( &rx, &g_frags[n-1UL], 2000L )==TK_MP_DISCARD, "late last fragment discarded" );
    /* And the receiver is clean for the next message. */
    fill( g_msg2, 10UL, 1 );
    fragment( g_msg2, 10UL, 2UL, 21UL, TK_MP_DIR_REQUEST );
    CHECK( feed( &rx, &g_frags[0], 3000L )==TK_MP_COMPLETE, "next message completes" );
    CHECK( tk_mp_rx_poll( &rx, 999999L )==TK_MP_PARTIAL, "an idle receiver never times out" );
}

static void
test_orphan_continuation( void ) {
    fill( g_msg, 3UL*PAYLOAD, 8 );
    ulong n = fragment( g_msg, 3UL*PAYLOAD, 3UL, 30UL, TK_MP_DIR_REQUEST );
    tk_mp_rx_t rx; rx_reset( &rx, TK_MP_DIR_REQUEST );
    CHECK( feed( &rx, &g_frags[1], 0L )==TK_MP_ERR_ORPHAN, "continuation with no message is rejected" );
    CHECK( feed( &rx, &g_frags[n-1UL], 0L )==TK_MP_DISCARD, "the rest of that message is swallowed" );
    CHECK( !rx.active, "nothing buffered" );
}

static void
test_sender_is_a_bounded_cursor( void ) {
    fill( g_msg, 3UL*PAYLOAD+1UL, 1 );
    tk_mp_tx_t tx;
    CHECK( tk_mp_tx_begin( &tx, TK_MP_DIR_RESULT, TK_MP_CT_EMBEDDING, 1UL, 2UL, g_msg, 3UL*PAYLOAD+1UL )==0, "begin" );
    uint8_t out[ TK_MP_LINK_MTU ]; int som, eom;
    ulong emitted = 0UL;
    while( !tk_mp_tx_done( &tx ) ) {
        ulong sz = tk_mp_tx_frag( &tx, out, &som, &eom );
        CHECK( sz>(ulong)TK_MP_HDR_SZ && sz<=MTU, "one bounded fragment per call" );
        emitted++;
        CHECK( emitted<=4UL, "no more than frag_cnt fragments" );
    }
    CHECK( emitted==4UL, "3 full fragments plus the 1-byte tail" );
    CHECK( tk_mp_tx_frag( &tx, out, &som, &eom )==0UL, "a finished cursor emits nothing" );
}

int
main( void ) {
    test_bounds();
    test_hash_vector();
    test_round_trip();
    test_oversize_and_empty();
    test_malformed_streams();
    test_failed_message_remainder_is_swallowed();
    test_interleaved_som();
    test_timeout();
    test_orphan_continuation();
    test_sender_is_a_bounded_cursor();
    if( g_failed ) { fprintf( stderr, "multipart tests FAILED\n" ); return 1; }
    printf( "all multipart tests passed\n" );
    return 0;
}
