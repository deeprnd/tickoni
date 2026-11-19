/* tk_agent_hooks.h — the narrow interface through which the C fd_stem tkagnt
   tile applies Zig-owned agent decisions.

   Approved boundary (tkagnt fd_stem migration plan, "Owner approvals"): the C
   stem does bounded transport and correlation only.  Which model tier serves a
   request, and what a returned model result means, are decided in Zig
   (src/tickoni/tiles/agent/decision.zig) and reach the stem as two function
   pointers.  This is the only C->Zig call path.

   One request, one model dispatch, one result: there is no cascade or
   follow-up dispatch (owner decision).  The topology defines which tiers
   exist; a request names the tier it needs.

   Rules the stem and the Zig side both keep:
     * Plain fixed-size data in, plain fixed-size data out.  No allocator, no
       I/O, no blocking, no publishing, no retained pointers: `content` is valid
       only for the duration of the call.
     * The stem validates every returned directive (tier ordinal in range and
       configured, action known) and fails closed on anything else.  A hook can
       ask for work; only the stem publishes it.
     * Hooks are pure: the same query yields the same directive, which is what
       keeps replay deterministic.

   One C definition, shared with Zig through audit_schema.h's translate-c step
   (audit_mod.TkAgent*); nothing mirrors it by hand.  Tier ordinals are
   TkAgntModelTier (src/tickoni/runtime/model_tier.zig); bit i of a
   `configured_mask` is set when the tier with ordinal i has a configured
   tkmodl instance. */
#ifndef __TK_AGENT_HOOKS_H__
#define __TK_AGENT_HOOKS_H__

#include <stddef.h>
#include <stdint.h>

#define TK_AGENT_TIER_NONE  255   /* no tier requested / none recommended */

/* Number of model tiers: the size of a configured_mask domain and of the
   agent's tier-indexed tables.  Zig asserts this equals
   runtime/model_tier.zig's TkAgntModelTier.count. */
enum { TK_AGENT_TIER_COUNT = 11 };

enum {
    TK_AGENT_REQ_CHAT      = 1,
    TK_AGENT_REQ_EMBEDDING = 2
};

/* ─── route_request ─── */

enum {
    TK_AGENT_ROUTE_DISPATCH         = 0,  /* send to `tier` */
    TK_AGENT_ROUTE_DENY_ABSENT_TIER = 1,  /* the tier the request names is not configured */
    TK_AGENT_ROUTE_DENY_INVALID     = 2   /* malformed or contradictory request */
};

typedef struct {
    uint16_t  configured_mask;    /* 0  */
    uint8_t   request_type;       /* 2  - TK_AGENT_REQ_* */
    uint8_t   requested_tier;     /* 3  - tier ordinal; TK_AGENT_TIER_NONE is allowed only for embedding */
    uint8_t   _pad[4];            /* 4  */
} TkAgentRouteQuery;              /* 8 */

typedef struct {
    uint8_t   verdict;            /* 0  - TK_AGENT_ROUTE_* */
    uint8_t   tier;               /* 1  - tier ordinal to dispatch to, or the absent tier on a denial */
    uint8_t   _pad[6];            /* 2  */
} TkAgentRouteDirective;          /* 8 */

/* ─── interpret_result ─── */

enum {
    TK_AGENT_ACT_FINAL = 0,       /* the run is complete with this result */
    TK_AGENT_ACT_FAIL  = 1        /* terminal failure; `why` says which */
};

enum {
    TK_AGENT_WHY_NONE              = 0,
    TK_AGENT_WHY_MODEL_DENIED      = 1,  /* tkmodl denied the call */
    TK_AGENT_WHY_INVALID_CONTENT   = 2,  /* result content is not the expected shape */
    TK_AGENT_WHY_INVALID_TIER      = 3,  /* a tier named by the model or the result source is unknown */
    TK_AGENT_WHY_CONTENT_TOO_LARGE = 4   /* result content exceeds the interpreter's bound */
};

enum {
    TK_AGENT_CONF_NONE   = 0,   /* not a classifier result */
    TK_AGENT_CONF_LOW    = 1,
    TK_AGENT_CONF_MEDIUM = 2,
    TK_AGENT_CONF_HIGH   = 3
};

typedef struct {
    uint8_t const * content;          /* 0  - complete verified result bytes; call-scoped */
    uint32_t        content_len;      /* 8  */
    uint8_t         request_type;     /* 12 - TK_AGENT_REQ_* */
    uint8_t         source_tier;      /* 13 - tier ordinal of the tkmodl instance that answered */
    uint8_t         model_decision;   /* 14 - ModelDecision tag from the result record */
    uint8_t         _pad;             /* 15 */
} TkAgentInterpretQuery;              /* 16 */

typedef struct {
    uint8_t   action;             /* 0  - TK_AGENT_ACT_* */
    uint8_t   why;                /* 1  - TK_AGENT_WHY_*; meaningful for FAIL */
    uint8_t   confidence;         /* 2  - TK_AGENT_CONF_* */
    uint8_t   recommended_tier;   /* 3  - tier ordinal or TK_AGENT_TIER_NONE */
    uint8_t   _pad[4];            /* 4  */
} TkAgentInterpretDirective;      /* 8 */

typedef TkAgentRouteDirective     (*TkAgentRouteFn)    ( TkAgentRouteQuery const * );
typedef TkAgentInterpretDirective (*TkAgentInterpretFn)( TkAgentInterpretQuery const * );

typedef struct {
    TkAgentRouteFn      route;
    TkAgentInterpretFn  interpret;
} TkAgentHooks;

_Static_assert( sizeof(TkAgentRouteQuery)==8UL,         "TkAgentRouteQuery ABI drift" );
_Static_assert( sizeof(TkAgentRouteDirective)==8UL,     "TkAgentRouteDirective ABI drift" );
_Static_assert( offsetof(TkAgentInterpretQuery, content_len)==8UL, "TkAgentInterpretQuery ABI drift" );
_Static_assert( sizeof(TkAgentInterpretQuery)==16UL,    "TkAgentInterpretQuery ABI drift" );
_Static_assert( sizeof(TkAgentInterpretDirective)==8UL, "TkAgentInterpretDirective ABI drift" );

#endif /* __TK_AGENT_HOOKS_H__ */
