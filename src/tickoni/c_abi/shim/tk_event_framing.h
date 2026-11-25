/* tk_event_framing.h — the envelope checks the ingress tiles apply to a
   whole-fragment TkEvent (tk_event_wire.h).

   tkgate checks what the terminal tile sends it; tkings checks what tkgate and
   tkrepl send it.  Both use these definitions, so an event tkgate forwards is
   one tkings frames, and the two cannot drift apart.  Each tile adds only its
   own rule on top: tkgate takes user requests only and fills in a missing
   trace id, and tkings requires the trace id.

   Pure functions of the event.  Include after audit_schema.h. */
#ifndef __TK_EVENT_FRAMING_H__
#define __TK_EVENT_FRAMING_H__

/* A trace id is absent when all of its bytes are zero. */
static inline int
tk_event_trace_id_is_zero( uint8_t const id[ TK_TRACE_ID_SZ ] ) {
    uint8_t any = 0;
    for( size_t i=0; i<TK_TRACE_ID_SZ; i++ ) any |= id[i];
    return !any;
}

/* A known wire version, kind, source and flags, and the replay bit only from
   tkrepl. */
static inline int
tk_event_envelope_ok( TkEvent const * ev ) {
    if( ev->version!=TK_EVENT_WIRE_VERSION )                                       return 0;
    if( ev->kind!=TK_EVENT_KIND_PAYMENT && ev->kind!=TK_EVENT_KIND_AGENT_REQUEST ) return 0;
    if( ev->source!=TK_EVENT_SOURCE_TKGATE && ev->source!=TK_EVENT_SOURCE_TKREPL )  return 0;
    if( ev->flags & (uint8_t)~TK_EVENT_FLAGS_KNOWN )                               return 0;
    if( (ev->flags & TK_EVENT_FLAG_REPLAY) && ev->source!=TK_EVENT_SOURCE_TKREPL ) return 0;
    return 1;
}

#endif /* __TK_EVENT_FRAMING_H__ */
