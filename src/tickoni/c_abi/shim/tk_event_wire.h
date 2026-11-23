/* tk_event_wire.h — the canonical spine event envelope, TkEvent.

   Every event enters the runtime as one TkEvent fragment on tkings's input
   link and travels the spine unchanged in shape:

     producer -> tkings -> tknorm -> tkdedu -> tkcase -> tkpoly -> tkaudt
                                                tkcase -> tkdisp

   One C definition, included at the end of audit_schema.h, so Zig sees it
   through the same translate-c step as audit_mod.TkEvent*; nothing mirrors it
   by hand.

   Who stamps what (plans/v2.NN-tkings-test-build-cleanup.md, revision 2):

     producer  version, kind, source, flags, trace_id, idempotency_key, body
               (tkapi for user requests, tkrepl for replay; the integration
               test harness stands in for tkapi).  The producer owns trace_id:
               one inbound request keeps one nonzero trace_id until its reply.
     tkings    validates framing (size, version, kind, source, flags,
               trace_id != 0), drops what fails, and stamps source_offset: a
               per-source counter, deterministic in arrival order.  It resets
               every field a later tile owns, so a producer cannot pre-decide
               anything.
     tknorm    validates the kind's fields and stamps event_hash.
     tkdedu    stamps duplicate.
     tkcase    will stamp case_id (0 until the tkcase plan).
     tkpoly    stamps decision and decided_by (tknorm stamps them for a
               malformed event).
     every     spine tile increments pipeline_hops.

   An event carries no prompt bytes: an agent request names its prompt by
   reference (TkAgentRequestMsg.prompt_ref, tk_agent_wire.h). */
#ifndef __TK_EVENT_WIRE_H__
#define __TK_EVENT_WIRE_H__

#define TK_EVENT_WIRE_VERSION  1

/* Event kinds with a consumer today. */
enum {
    TK_EVENT_KIND_PAYMENT       = 1,
    TK_EVENT_KIND_AGENT_REQUEST = 2
};

/* Producers.  The integration test harness stands in for tkapi, so there is no
   test value.  source_offset counts per source, so TK_EVENT_SOURCE_CNT bounds
   tkings's counter table. */
enum {
    TK_EVENT_SOURCE_TKAPI  = 1,
    TK_EVENT_SOURCE_TKREPL = 2,
    TK_EVENT_SOURCE_CNT    = 3
};

/* flags: the replay bit, which only tkrepl may set. */
#define TK_EVENT_FLAG_REPLAY       ((uint8_t)0x01)
#define TK_EVENT_FLAGS_KNOWN       TK_EVENT_FLAG_REPLAY

/* MTU of every spine link: one TkEvent per fragment. */
enum { TK_EVENT_LINK_MTU = 512 };

/* A payment event's fields (the former RawPayment, less what moved into the
   envelope).  `malformed` is the producer's own framing verdict, which tknorm
   honors as before. */
typedef struct {
    int64_t   amount_cents;            /* 0  */
    uint32_t  account_id;              /* 8  */
    uint8_t   currency[3];             /* 12 */
    uint8_t   malformed;               /* 15 */
} TkEventPayment;                      /* 16 */

typedef struct {
    uint16_t  version;                 /* 0  - TK_EVENT_WIRE_VERSION */
    uint8_t   kind;                    /* 2  - TK_EVENT_KIND_* */
    uint8_t   source;                  /* 3  - TK_EVENT_SOURCE_* */
    uint8_t   flags;                   /* 4  - TK_EVENT_FLAG_* */
    uint8_t   pipeline_hops;           /* 5  */
    uint8_t   duplicate;               /* 6  - tkdedu */
    uint8_t   decision;                /* 7  - PolicyOutcome; tknorm or tkpoly */
    uint64_t  trace_id;                /* 8  - producer; nonzero */
    uint64_t  idempotency_key;         /* 16 - producer */
    uint64_t  source_offset;           /* 24 - tkings */
    uint64_t  event_hash;              /* 32 - tknorm */
    uint64_t  case_id;                 /* 40 - tkcase; 0 until assigned */
    uint8_t   decided_by[6];           /* 48 - tile id that finalized `decision` */
    uint8_t   _pad[2];                 /* 54 */
    union {
        TkEventPayment     payment;
        TkAgentRequestMsg  agent_request;
    } body;                            /* 56 */
} TkEvent;                             /* 360 */

#define TK_EVENT_SIZE sizeof(TkEvent)

_Static_assert( sizeof(TkEventPayment)==16UL,            "TkEventPayment wire size drift" );
_Static_assert( offsetof(TkEvent, trace_id)==8UL,        "TkEvent.trace_id ABI drift" );
_Static_assert( offsetof(TkEvent, source_offset)==24UL,  "TkEvent.source_offset ABI drift" );
_Static_assert( offsetof(TkEvent, decided_by)==48UL,     "TkEvent.decided_by ABI drift" );
_Static_assert( offsetof(TkEvent, body)==56UL,           "TkEvent.body ABI drift" );
_Static_assert( sizeof(TkEvent)==360UL,                  "TkEvent wire size drift" );
_Static_assert( sizeof(TkEvent)<=(unsigned long)TK_EVENT_LINK_MTU, "TkEvent must fit a spine link" );

#endif /* __TK_EVENT_WIRE_H__ */
