/* tkrepl_frag.h — the tkrepl wire contract (wire version 1) and the narrow
   interface through which the C fd_stem tkrepl tile applies the Zig-owned
   replay verdict.

     tkcase --(TkEvent, then TkCaseCapsuleMsg)--> tkrepl --(TkReplAuditMsg)--> tkaudt

   The replay side-channel (doc/knowledge/unified-flow-diagram.md): tkrepl is
   not in the event spine.  tkcase streams it the case capsule as it builds it:
   every event it attaches, exactly as forwarded (sig TK_LINK_SIG_EVENT), and,
   after the event that closes the case, one TkCaseCapsuleMsg (sig
   TK_LINK_SIG_CASE_CAPSULE) naming what the capsule holds.  tkrepl replays the
   capsule with external effects disabled (it has no model, adapter or
   execution path at all): it independently folds the events it received into
   its own observation, asks the Zig verifier whether that observation matches
   the summary, and reports the verdict to tkaudt as one RECORD_REPLAY_RESULT
   record (WireReplayResultPayload) and on its CNC slots 0 (replay_checked) and
   1 (replay_match), which tkdiag and the supervisor read.

   The verdict is Zig's (src/tickoni/tiles/replay/decision.zig) and reaches the
   stem as one function pointer, under the rules of tk_agent_hooks.h: plain
   fixed-size data in and out, no allocator, no I/O, no blocking, no retained
   pointers, pure.  The stem never decides a divergence itself.

   One C definition, included at the end of audit_schema.h, so Zig sees it
   through the same translate-c step (audit_mod.TkRepl*, audit_mod.TkCaseCapsuleMsg);
   nothing mirrors it by hand.  The capsule hash both tiles fold is in
   tk_capsule_hash.h (C only). */
#ifndef __TKREPL_FRAG_H__
#define __TKREPL_FRAG_H__

#define TK_REPL_WIRE_VERSION        1
#define TK_LINK_SIG_CASE_CAPSULE    0x4350UL   /* "CP": tkcase -> tkrepl, the capsule summary */
#define TK_LINK_SIG_REPLAY_AUDIT    0x5241UL   /* "RA": tkrepl -> tkaudt */

/* tkcase -> tkrepl carries whole TkEvents and the summary: the spine MTU.
   tkrepl -> tkaudt carries one TkReplAuditMsg per run. */
enum { TK_REPL_CAPSULE_LINK_MTU = TK_EVENT_LINK_MTU };
enum { TK_REPL_AUDIT_LINK_MTU = 128 };

/* tkcase -> tkrepl, after the event that closes the case.  What tkcase
   recorded in its capsule.  64 bytes. */
typedef struct {
    uint16_t  version;                 /* 0  - TK_REPL_WIRE_VERSION */
    uint8_t   _pad0[6];                /* 2  */
    uint64_t  case_id;                 /* 8  - nonzero */
    uint64_t  event_count;             /* 16 - events in the capsule */
    uint64_t  first_source_offset;     /* 24 - the capsule's first event's */
    uint64_t  last_source_offset;      /* 32 - the capsule's last event's */
    uint64_t  capsule_hash;            /* 40 - tk_capsule_hash.h over every event, in order */
    _Alignas(16) uint8_t trace_id[TK_TRACE_ID_SZ]; /* 48 - the closing event's */
} TkCaseCapsuleMsg;                    /* 64 */

/* tkrepl -> tkaudt: the replay verdict.  The audit record header is built by
   tkaudt from the message.  payload.capsule_id is the summary's capsule hash:
   the capsule's content address.  80 bytes. */
typedef struct {
    uint16_t  version;                 /* 0  - TK_REPL_WIRE_VERSION */
    uint8_t   record_type;             /* 2  - RECORD_REPLAY_RESULT */
    uint8_t   _pad0[5];                /* 3  */
    uint64_t  case_id;                 /* 8  - becomes header.case_id; the summary's */
    uint64_t  source_offset;           /* 16 - the summary's last_source_offset; becomes header.source_offset */
    uint8_t   _pad1[8];                /* 24 */
    _Alignas(16) uint8_t trace_id[TK_TRACE_ID_SZ]; /* 32 - the summary's; becomes header.trace_id */
    WireReplayResultPayload payload;   /* 48 */
    uint8_t   _pad2[8];                /* 72 */
} TkReplAuditMsg;                      /* 80 */

/* ─── verify ───

   The field a divergence names (TkReplVerifyDirective.first_field).  Bounded,
   append-only. */
enum {
    TK_REPL_FIELD_NONE                = 0,
    TK_REPL_FIELD_CAPSULE_VERSION     = 1,   /* the summary's wire version is not one tkrepl reads: hard */
    TK_REPL_FIELD_EVENT_CASE_ID       = 2,   /* an event is attached to a different case than the first */
    TK_REPL_FIELD_CASE_ID             = 3,   /* the summary names another (or no) case */
    TK_REPL_FIELD_EVENT_COUNT         = 4,
    TK_REPL_FIELD_FIRST_SOURCE_OFFSET = 5,
    TK_REPL_FIELD_LAST_SOURCE_OFFSET  = 6,
    TK_REPL_FIELD_CAPSULE_HASH        = 7
};

/* What tkcase recorded (the summary) against what tkrepl received.  The
   observation is tkrepl's fold of the events, in arrival order:
   observed_case_id is the first event's case id, and a case-id mismatch is an
   event whose case id differs from it (first_case_id_mismatch_seq is that
   event's 1-based position in the capsule, 0 when none).  128 bytes. */
typedef struct {
    TkCaseCapsuleMsg summary;                  /* 0   */
    uint64_t  observed_count;                  /* 64  */
    uint64_t  observed_case_id;                /* 72  */
    uint64_t  observed_first_source_offset;    /* 80  */
    uint64_t  observed_last_source_offset;     /* 88  */
    uint64_t  observed_hash;                   /* 96  */
    uint64_t  case_id_mismatches;              /* 104 */
    uint64_t  first_case_id_mismatch_seq;      /* 112 */
    uint8_t   _pad[8];                         /* 120 */
} TkReplVerifyQuery;                           /* 128 */

/* The verdict: how many fields diverge, the capsule position at which the
   first was seen (1-based; the summary is position observed_count+1; 0 when
   none diverges) and which field it was. */
typedef struct {
    uint64_t  divergences;             /* 0  */
    uint64_t  first_divergent_seq;     /* 8  */
    uint8_t   first_field;             /* 16 - TK_REPL_FIELD_* */
    uint8_t   _pad[7];                 /* 17 */
} TkReplVerifyDirective;               /* 24 */

typedef TkReplVerifyDirective (*TkReplVerifyFn)( TkReplVerifyQuery const * );

typedef struct {
    TkReplVerifyFn  verify;
} TkReplHooks;

_Static_assert( sizeof(TkCaseCapsuleMsg)==64UL,              "TkCaseCapsuleMsg wire size drift" );
_Static_assert( offsetof(TkCaseCapsuleMsg, trace_id)==48UL,  "TkCaseCapsuleMsg.trace_id ABI drift" );
_Static_assert( sizeof(TkCaseCapsuleMsg)<=(unsigned long)TK_REPL_CAPSULE_LINK_MTU, "TkCaseCapsuleMsg must fit its link" );
_Static_assert( sizeof(TkEvent)<=(unsigned long)TK_REPL_CAPSULE_LINK_MTU,          "TkEvent must fit the capsule link" );
_Static_assert( sizeof(TkReplAuditMsg)==80UL,                "TkReplAuditMsg wire size drift" );
_Static_assert( offsetof(TkReplAuditMsg, trace_id)==32UL,    "TkReplAuditMsg.trace_id ABI drift" );
_Static_assert( offsetof(TkReplAuditMsg, payload)==48UL,     "TkReplAuditMsg.payload ABI drift" );
_Static_assert( sizeof(TkReplAuditMsg)<=(unsigned long)TK_REPL_AUDIT_LINK_MTU, "TkReplAuditMsg must fit its link" );
_Static_assert( sizeof(TkReplVerifyQuery)==128UL,            "TkReplVerifyQuery ABI drift" );
_Static_assert( offsetof(TkReplVerifyQuery, observed_count)==64UL, "TkReplVerifyQuery ABI drift" );
_Static_assert( sizeof(TkReplVerifyDirective)==24UL,         "TkReplVerifyDirective ABI drift" );

#endif /* __TKREPL_FRAG_H__ */
