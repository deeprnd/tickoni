/* tk_multipart_wire.h — wire contract for bounded multipart model content.

   One C definition, shared with Zig through audit_schema.h's translate-c step
   (audit_mod.TK_MP_* / audit_mod.TkMpHeader); nothing mirrors it by hand.

   Why this exists.  A Firedancer fragment's `sz` is 16 bits, so one fragment
   carries at most 65,535 bytes, and the Tickoni stems accept one fixed-size
   record per fragment.  Model prompts, responses and embedding vectors can be
   larger, so the tkagnt <-> tkmodl links carry one LOGICAL message as a
   contiguous stream of fragments, each led by a TkMpHeader.  The receiver
   reassembles into a bounded buffer and accepts the message only after every
   byte, the boundaries and the whole-message hash verify.  The body-free
   tkmodl -> tkaudt record is a separate contract and never carries content.

   The numeric bounds are the approved values in the tkagnt fd_stem migration
   plan ("Chosen numeric bounds"); change them there first.

   Framing is canonical so a receiver can derive everything it checks:
     * every fragment except the last carries exactly TK_MP_FRAG_PAYLOAD_MAX
       payload bytes; the last carries the remainder (>= 1);
     * frag_off == frag_idx * TK_MP_FRAG_PAYLOAD_MAX;
     * frag_cnt == ceil(total_len / TK_MP_FRAG_PAYLOAD_MAX);
     * the first fragment has SOM set and frag_idx 0; the last has EOM set and
       frag_idx == frag_cnt-1; a single-fragment message has both;
     * fragments of one message are contiguous on their link (one producer per
       link, no interleaving). */
#ifndef __TK_MULTIPART_WIRE_H__
#define __TK_MULTIPART_WIRE_H__

#include <stddef.h>
#include <stdint.h>

#define TK_MP_WIRE_VERSION  1

/* Numeric bounds are enumerators (not macros) so both C and Zig see them as
   typed-free integer constants. */
enum {
    TK_MP_HDR_SZ             = 64,
    TK_MP_LINK_MTU           = 8192,                          /* whole fragment: header + payload */
    TK_MP_FRAG_PAYLOAD_MAX   = 8192 - 64,                     /* 8128 */
    TK_MP_MAX_MESSAGE_BYTES  = 262144,                        /* 256 KiB logical message */
    TK_MP_MAX_FRAGS          = (262144 + (8192-64) - 1) / (8192-64), /* 33 */
    TK_MP_LINK_DEPTH         = 32,                            /* measured in fragments */
    TK_MP_MAX_PROMPT_MESSAGES = 16,
    TK_MP_PARTIAL_TIMEOUT_MS = 2000,
    TK_MP_FD_SZ_CEILING      = 65535                          /* fd_frag_meta_t.sz is 16 bits */
};

enum {
    TK_MP_DIR_REQUEST = 1,      /* tkagnt -> tkmodl */
    TK_MP_DIR_RESULT  = 2       /* tkmodl -> tkagnt */
};

enum {
    TK_MP_CT_CHAT          = 1, /* chat/completion messages or response text */
    TK_MP_CT_EMBEDDING     = 2, /* embedding input text or vector bytes */
    TK_MP_CT_LAST          = 2
};

/* Domain-separated SipHash-1-3 keys for the whole-message hash.  Distinct from
   the audit-record keys in audit_consts.h so a content hash can never be
   mistaken for a chain hash. */
static const uint64_t TK_MP_HASH_K0 = 0x00504d4b54ULL;        /* "TKMP" LE */
static const uint64_t TK_MP_HASH_K1 = 1;                      /* wire version */

typedef struct {
    uint16_t  version;           /* 0  - TK_MP_WIRE_VERSION */
    uint8_t   direction;         /* 2  - TK_MP_DIR_* */
    uint8_t   content_type;      /* 3  - TK_MP_CT_* */
    uint32_t  total_len;         /* 4  - logical message bytes, headers excluded */
    uint32_t  frag_off;          /* 8  - this fragment's payload offset in the message */
    uint32_t  frag_len;          /* 12 - payload bytes in this fragment */
    uint32_t  frag_idx;          /* 16 */
    uint32_t  frag_cnt;          /* 20 */
    uint64_t  run_id;            /* 24 */
    uint64_t  model_request_id;  /* 32 - deterministic dispatch id; with run_id the correlation key */
    uint64_t  message_hash;      /* 40 - SipHash-1-3 of the whole message, declared by the sender and
                                         verified by the receiver against the reassembled bytes */
    uint8_t   reserved[16];      /* 48 - zero */
} TkMpHeader;                    /* 64 */

_Static_assert( sizeof(TkMpHeader)==64UL, "TkMpHeader wire size drift" );
_Static_assert( offsetof(TkMpHeader, total_len)==4UL,        "TkMpHeader.total_len ABI drift" );
_Static_assert( offsetof(TkMpHeader, run_id)==24UL,          "TkMpHeader.run_id ABI drift" );
_Static_assert( offsetof(TkMpHeader, message_hash)==40UL,    "TkMpHeader.message_hash ABI drift" );
_Static_assert( TK_MP_HDR_SZ==64,                            "TK_MP_HDR_SZ must match TkMpHeader" );
_Static_assert( TK_MP_LINK_MTU<=TK_MP_FD_SZ_CEILING,         "a fragment must fit fd_frag_meta_t.sz" );
_Static_assert( TK_MP_FRAG_PAYLOAD_MAX>0,                    "fragment payload must be positive" );

#endif /* __TK_MULTIPART_WIRE_H__ */
