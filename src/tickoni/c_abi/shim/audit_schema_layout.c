/* audit_schema_layout.c — C helpers for Zig parity checks.
   audit_schema.h is the single source of truth for the Header layout. */

#include "audit_schema.h"

size_t audit_header_sizeof(void) { return sizeof(AuditHeader); }
size_t audit_header_alignof(void) { return _Alignof(AuditHeader); }
