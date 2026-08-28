typedef unsigned char uchar;
typedef unsigned short ushort;
typedef unsigned int uint;
typedef unsigned long ulong;

// ── Return-value truncation ────────────────────────────────────────────────

uchar ret_as_uchar(ulong x) {
    return x; // $ Alert
}

ushort ret_as_ushort(ulong x) {
    return x; // $ Alert
}

uint ret_as_uint(ulong x) {
    return x; // $ Alert
}

// ── Variable initialisation ────────────────────────────────────────────────

void init_vars(ulong big) {
    uchar  a = big;  // $ Alert
    ushort b = big;  // $ Alert
    uint   c = big;  // $ Alert

    // Explicit casts – no alert
    uchar  d = (uchar)big;   // NO Alert
    ushort e = (ushort)big;  // NO Alert
    uint   f = (uint)big;    // NO Alert

    // Widening – no alert
    ulong g = c;             // NO Alert
    ulong h = b;             // NO Alert
    ulong i = a;             // NO Alert
    (void)(d + e + f + g + h + i);
}

// ── Integer literal narrowing (GCC 8.3 compile-failure case) ──────────────
// int literals are widened to `int` by the C standard before assignment,
// which is an implicit truncation to `uchar`/`ushort`.

void literal_narrow(void) {
    uchar  x = 3;    // $ Alert
    ushort y = 300;  // $ Alert
    (void)(x + y);
}

// ── Function-call argument truncation ─────────────────────────────────────

void takes_ushort(ushort x);

void call_with_ulong(ulong big) {
    takes_ushort(big); // $ Alert
}

// ── Struct-member assignment ───────────────────────────────────────────────

struct narrow_fields {
    ushort x;
    uchar  y;
};

void assign_members(ulong big) {
    struct narrow_fields s;
    s.x = big;        // $ Alert
    s.y = big;        // $ Alert
    s.x = (ushort)big; // NO Alert
}
