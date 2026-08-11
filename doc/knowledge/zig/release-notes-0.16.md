# 0.16.0 Release Notes

Zig is a general-purpose programming language and toolchain for
maintaining **robust**, **optimal**, and **reusable** software.

Zig development is funded via [Zig Software Foundation](/zsf/), a
501(c)(3) non-profit organization. Please consider a recurring donation
so that we can offer more billable hours to our core team members. This
is the most straightforward way to accelerate the project along the
{#link\|Roadmap#} to 1.0. If you need **donation receipts** or are
looking to migrate away from GitHub Sponsors, we recommend [donating via
Every.org](https://www.every.org/zig-software-foundation-inc).

This release features **8 months of work**: changes from **244 different
contributors**, spread among **1183 commits**.

Perhaps most notably, this release debuts {#link\|I/O as an Interface#},
but don\'t sleep on the {#link\|Language Changes#} or enhancements to
the {#link\|Compiler#}, {#link\|Build System#}, {#link\|Linker#},
{#link\|Fuzzer#}, and {#link\|Toolchain#} which are also included in
this release.

Zig supports a wide range of architectures and operating systems. The
{#link\|Support Table#} and {#link\|Additional Platforms#} sections
cover the targets that Zig can build programs for, while the
[zig-bootstrap
README](https://codeberg.org/ziglang/zig-bootstrap#supported-targets)
covers the targets that the Zig compiler itself can be easily
cross-compiled to run on.

Notable changes:

-   `aarch64-freebsd`, `aarch64-netbsd`, `loongarch64-linux`,
    `powerpc64le-linux`, `s390x-linux`, `x86_64-freebsd`,
    `x86_64-netbsd`, and `x86_64-openbsd` are now tested natively in
    Zig\'s CI, ensuring high-quality support going forward. Thanks to
    [OSUOSL](https://osuosl.org/) for providing AArch64 and Power ISA
    hardware, and
    [IBM](https://community.ibm.com/community/user/groupz?CommunityKey=8c2c15eb-f059-4e7c-8cb6-5fb713a7806c)
    for providing z/Architecture hardware.
-   Cross-compilation support for `aarch64-maccatalyst` and
    `x86_64-maccatalyst` has been added. This was \'free\' in a sense,
    since the vendored `libSystem.tbd` that Zig ships already provides
    the symbols for these targets anyway.
-   Initial `loongarch32-linux` support has been added. Note that libc
    is not yet supported for this target, and LLVM still considers the
    ABI unstable, but programs using only syscalls via `std.os.linux`
    can be built.
-   Basic support has been added for the Alpha, KVX, MicroBlaze,
    OpenRISC, PA-RISC, and SuperH architectures. For now, these targets
    require using either Zig\'s C backend with GCC or an external
    LLVM/Clang fork.
-   Support for Oracle\'s Solaris and IBM\'s AIX and z/OS has been
    removed. In general, the Zig project cannot support proprietary
    operating systems that make it unreasonably difficult to obtain
    system headers and thus audit contributions. Note that this does not
    affect illumos; being an open source fork from OpenSolaris, it
    remains supported.
-   {#link\|Stack tracing support has been significantly improved across
    the board\|Expanded target support for segfault
    handling/unwinding#}; almost all major targets now provide stack
    traces on crashes.
-   Various {#link\|Standard Library#} bugs that mainly affected
    weakly-ordered architectures and targets with unusual page sizes
    have been fixed. Among others, this is known to have significantly
    improved reliability on AArch64 (especially w/o LSE), LoongArch, and
    Power ISA.
-   Various {#link\|Standard Library#} and {#link\|Compiler#} bugs
    preventing Zig from working on big-endian hosts have been fixed.
-   Big-endian ARM targets have been fixed to emit BE8 object files when
    targeting ARMv6+, rather than the legacy BE32 format.

{#header_open\|Tier System#}

Zig\'s level of support for various targets is broadly categorized into
four tiers with Tier 1 being the highest. The goal is for Tier 1 targets
to have zero disabled tests - this will become a requirement for
post-1.0.0 Zig releases.

{#header_open\|Tier 1#}

-   All non-experimental {#link\|language\|Language Changes#} features
    are known to work correctly.
-   The {#link\|Compiler#} can generate machine code for these targets
    without relying on {#link\|LLVM\|LLVM 21#}.

{#header_close#} {#header_open\|Tier 2#}

-   The {#link\|Standard Library#} cross-platform abstractions account
    for these targets.
-   These targets have debug info capabilities and therefore produce
    stack traces on failed assertions and crashes.
-   Libc is available for these targets when cross-compiling.
-   Continuous Integration machines run the module tests for these
    targets on every push.

{#header_close#} {#header_open\|Tier 3#}

-   The {#link\|Compiler#} can generate machine code for these targets
    via {#link\|LLVM\|LLVM 21#}.
-   The {#link\|Linker#} can produce object files, libraries, and
    executables for these targets.
-   These targets are not considered experimental by {#link\|LLVM\|LLVM
    21#}.

{#header_close#} {#header_open\|Tier 4#}

-   The {#link\|Compiler#} can generate assembly source code for these
    targets via {#link\|LLVM\|LLVM 21#}.

{#header_close#} {#header_close#} {#header_open\|Support Table#}

In the following table, ✅ indicates full support, ❌ indicates no
support, and ⚠️ indicates that there is partial support, e.g. only for
some sub-targets, or with some notable known issues. ❔ indicates that
the status is largely unknown, typically because the target is rarely
exercised. Hover over other icons for details.

+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| T     | Tier  | Lang. | Std.  | Code  | L     | Debug | libc  | CI    |
| arget |       | Feat. | Lib.  | Gen.  | inker | Info  |       |       |
+=======+=======+=======+=======+=======+=======+=======+=======+=======+
| `x86  | [1]   | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ✅    |
| _64-l | (http |       |       | itle= |       |       |       |       |
| inux` | s://g |       |       | "Mach |       |       |       |       |
|       | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       | [⚡]{ |       |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 3079) |       |       | ted"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| ---   |       |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `a    | [2    | ✅    | ✅    | [🖥️]{ | ✅    | ✅    | ✅    | ✅    |
| arch6 | ](htt |       |       | title |       |       |       |       |
| 4-fre | ps:// |       |       | ="Mac |       |       |       |       |
| ebsd` | githu |       |       | hine  |       |       |       |       |
|       | b.com |       |       | Code" |       |       |       |       |
|       | /zigl |       |       | }[🛠️]{ |      |       |       |       |
|       | ang/z |       |       | title |       |       |       |       |
|       | ig/is |       |       | ="Sel |       |       |       |       |
|       | sues/ |       |       | f-Hos |       |       |       |       |
|       | 3939) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `aarc | [2    | ✅    | ✅    | [🖥️]{ | ✅    | ✅    | ✅    | ✅    |
| h64(_ | ](htt |       |       | title |       |       |       |       |
| be)-l | ps:// |       |       | ="Mac |       |       |       |       |
| inux` | githu |       |       | hine  |       |       |       |       |
|       | b.com |       |       | Code" |       |       |       |       |
|       | /zigl |       |       | }[🛠️]{ |      |       |       |       |
|       | ang/z |       |       | title |       |       |       |       |
|       | ig/is |       |       | ="Sel |       |       |       |       |
|       | sues/ |       |       | f-Hos |       |       |       |       |
|       | 2443) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `     | [2]   | ✅    | ✅    | [🖥️]{ | ✅    | ✅    | ✅    | ⚠️    |
| aarch | (http |       |       | title |       |       |       |       |
| 64-ma | s://g |       |       | ="Mac |       |       |       |       |
| ccata | ithub |       |       | hine  |       |       |       |       |
| lyst` | .com/ |       |       | Code" |       |       |       |       |
|       | zigla |       |       | }[🛠️]{ |      |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 5932) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `aarc | [2]   | ✅    | ✅    | [🖥️]{ | ✅    | ✅    | ✅    | ✅    |
| h64-m | (http |       |       | title |       |       |       |       |
| acos` | s://g |       |       | ="Mac |       |       |       |       |
|       | ithub |       |       | hine  |       |       |       |       |
|       | .com/ |       |       | Code" |       |       |       |       |
|       | zigla |       |       | }[🛠️]{ |      |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 3078) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `     | [2]   | ✅    | ✅    | [🖥️]{ | ✅    | ✅    | ✅    | ✅    |
| aarch | (http |       |       | title |       |       |       |       |
| 64(_b | s://g |       |       | ="Mac |       |       |       |       |
| e)-ne | ithub |       |       | hine  |       |       |       |       |
| tbsd` | .com/ |       |       | Code" |       |       |       |       |
|       | zigla |       |       | }[🛠️]{ |      |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 3084) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `a    | [2]   | ✅    | ✅    | [🖥️]{ | ✅    | ✅    | ✅    | ⚠️    |
| arch6 | (http |       |       | title |       |       |       |       |
| 4-ope | s://g |       |       | ="Mac |       |       |       |       |
| nbsd` | ithub |       |       | hine  |       |       |       |       |
|       | .com/ |       |       | Code" |       |       |       |       |
|       | zigla |       |       | }[🛠️]{ |      |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 3085) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `a    | [2]   | ✅    | ✅    | [🖥️]{ | ✅    | ✅    | ✅    | ⚠️    |
| arch6 | (http |       |       | title |       |       |       |       |
| 4-win | s://g |       |       | ="Mac |       |       |       |       |
| dows` | ithub |       |       | hine  |       |       |       |       |
|       | .com/ |       |       | Code" |       |       |       |       |
|       | zigla |       |       | }[🛠️]{ |      |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/1 |       |       | f-Hos |       |       |       |       |
|       | 6665) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `ar   | [2]   | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ⚠️    |
| m-fre | (http |       |       | itle= |       |       |       |       |
| ebsd` | s://g |       |       | "Mach |       |       |       |       |
|       | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3675) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `arm( | [2    | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ✅    |
| eb)-l | ](htt |       |       | itle= |       |       |       |       |
| inux` | ps:// |       |       | "Mach |       |       |       |       |
|       | githu |       |       | ine C |       |       |       |       |
|       | b.com |       |       | ode"} |       |       |       |       |
|       | /zigl |       |       |       |       |       |       |       |
|       | ang/z |       |       |       |       |       |       |       |
|       | ig/is |       |       |       |       |       |       |       |
|       | sues/ |       |       |       |       |       |       |       |
|       | 3174) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `     | [2]   | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ⚠️    |
| arm(e | (http |       |       | itle= |       |       |       |       |
| b)-ne | s://g |       |       | "Mach |       |       |       |       |
| tbsd` | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3763) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `ar   | [2]   | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ⚠️    |
| m-ope | (http |       |       | itle= |       |       |       |       |
| nbsd` | s://g |       |       | "Mach |       |       |       |       |
|       | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3773) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `hexa | [2]   | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ✅    |
| gon-l | (http |       |       | itle= |       |       |       |       |
| inux` | s://g |       |       | "Mach |       |       |       |       |
|       | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 1652) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `loo  | [2]   | ✅    | ✅    | [🖥️]{ | ✅    | ✅    | ✅    | ✅    |
| ngarc | (http |       |       | title |       |       |       |       |
| h64-l | s://g |       |       | ="Mac |       |       |       |       |
| inux` | ithub |       |       | hine  |       |       |       |       |
|       | .com/ |       |       | Code" |       |       |       |       |
|       | zigla |       |       | }[🛠️]{ |      |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 1646) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `     | [2    | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ✅    |
| mips( | ](htt |       |       | itle= |       |       |       |       |
| el)-l | ps:// |       |       | "Mach |       |       |       |       |
| inux` | githu |       |       | ine C |       |       |       |       |
|       | b.com |       |       | ode"} |       |       |       |       |
|       | /zigl |       |       |       |       |       |       |       |
|       | ang/z |       |       |       |       |       |       |       |
|       | ig/is |       |       |       |       |       |       |       |
|       | sues/ |       |       |       |       |       |       |       |
|       | 3345) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `m    | [2]   | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ⚠️    |
| ips(e | (http |       |       | itle= |       |       |       |       |
| l)-ne | s://g |       |       | "Mach |       |       |       |       |
| tbsd` | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3764) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `mi   | [2]   | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ✅    |
| ps64( | (http |       |       | itle= |       |       |       |       |
| el)-l | s://g |       |       | "Mach |       |       |       |       |
| inux` | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 1647) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `mips | [2]   | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ⚠️    |
| 64(el | (http |       |       | itle= |       |       |       |       |
| )-ope | s://g |       |       | "Mach |       |       |       |       |
| nbsd` | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3774) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `powe | [2]   | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ⚠️    |
| rpc-l | (http |       |       | itle= |       |       |       |       |
| inux` | s://g |       |       | "Mach |       |       |       |       |
|       | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 1649) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `     | [2]   | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ⚠️    |
| power | (http |       |       | itle= |       |       |       |       |
| pc-ne | s://g |       |       | "Mach |       |       |       |       |
| tbsd` | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3766) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `p    | [2]   | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ⚠️    |
| owerp | (http |       |       | itle= |       |       |       |       |
| c-ope | s://g |       |       | "Mach |       |       |       |       |
| nbsd` | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3775) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `po   | [2]   | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ⚠️    |
| werpc | (http |       |       | itle= |       |       |       |       |
| 64(le | s://g |       |       | "Mach |       |       |       |       |
| )-fre | ithub |       |       | ine C |       |       |       |       |
| ebsd` | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3678) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `     | [2]   | ✅    | ✅    | [🖥️]{t | ⚠️   | ✅    | ✅    | ⚠️    |
| power | (http |       |       | itle= |       |       |       |       |
| pc64( | s://g |       |       | "Mach |       |       |       |       |
| le)-l | ithub |       |       | ine C |       |       |       |       |
| inux` | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 1651) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `pow  | [2]   | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ⚠️    |
| erpc6 | (http |       |       | itle= |       |       |       |       |
| 4-ope | s://g |       |       | "Mach |       |       |       |       |
| nbsd` | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3776) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `risc | [2]   | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ✅    |
| v32-l | (http |       |       | itle= |       |       |       |       |
| inux` | s://g |       |       | "Mach |       |       |       |       |
|       | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 1648) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `r    | [2]   | ✅    | ✅    | [🖥️]{ | ✅    | ✅    | ✅    | ⚠️    |
| iscv6 | (http |       |       | title |       |       |       |       |
| 4-fre | s://g |       |       | ="Mac |       |       |       |       |
| ebsd` | ithub |       |       | hine  |       |       |       |       |
|       | .com/ |       |       | Code" |       |       |       |       |
|       | zigla |       |       | }[🛠️]{ |      |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 3676) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `risc | [2    | ✅    | ✅    | [🖥️]{ | ✅    | ✅    | ✅    | ✅    |
| v64-l | ](htt |       |       | title |       |       |       |       |
| inux` | ps:// |       |       | ="Mac |       |       |       |       |
|       | githu |       |       | hine  |       |       |       |       |
|       | b.com |       |       | Code" |       |       |       |       |
|       | /zigl |       |       | }[🛠️]{ |      |       |       |       |
|       | ang/z |       |       | title |       |       |       |       |
|       | ig/is |       |       | ="Sel |       |       |       |       |
|       | sues/ |       |       | f-Hos |       |       |       |       |
|       | 4456) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `r    | [2]   | ✅    | ✅    | [🖥️]{ | ✅    | ✅    | ✅    | ⚠️    |
| iscv6 | (http |       |       | title |       |       |       |       |
| 4-ope | s://g |       |       | ="Mac |       |       |       |       |
| nbsd` | ithub |       |       | hine  |       |       |       |       |
|       | .com/ |       |       | Code" |       |       |       |       |
|       | zigla |       |       | }[🛠️]{ |      |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 3777) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `s3   | [2]   | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ✅    |
| 90x-l | (http |       |       | itle= |       |       |       |       |
| inux` | s://g |       |       | "Mach |       |       |       |       |
|       | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 1402) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `t    | [2]   | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ✅    |
| humb( | (http |       |       | itle= |       |       |       |       |
| eb)-l | s://g |       |       | "Mach |       |       |       |       |
| inux` | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3672) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `thum | [2]   | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ⚠️    |
| b-win | (http |       |       | itle= |       |       |       |       |
| dows` | s://g |       |       | "Mach |       |       |       |       |
|       | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 4017) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `wa   | [2]   | ✅    | ✅    | [🖥️]{ | ✅    | ⚠️    | ✅    | ✅    |
| sm32- | (http |       |       | title |       |       |       |       |
| wasi` | s://g |       |       | ="Mac |       |       |       |       |
|       | ithub |       |       | hine  |       |       |       |       |
|       | .com/ |       |       | Code" |       |       |       |       |
|       | zigla |       |       | }[🛠️]{ |      |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 3091) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `     | [2    | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ✅    |
| x86-l | ](htt |       |       | itle= |       |       |       |       |
| inux` | ps:// |       |       | "Mach |       |       |       |       |
|       | githu |       |       | ine C |       |       |       |       |
|       | b.com |       |       | ode"} |       |       |       |       |
|       | /zigl |       |       |       |       |       |       |       |
|       | ang/z |       |       |       |       |       |       |       |
|       | ig/is |       |       |       |       |       |       |       |
|       | sues/ |       |       |       |       |       |       |       |
|       | 1929) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `x    | [2]   | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ⚠️    |
| 86-ne | (http |       |       | itle= |       |       |       |       |
| tbsd` | s://g |       |       | "Mach |       |       |       |       |
|       | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3772) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `x8   | [2]   | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ⚠️    |
| 6-ope | (http |       |       | itle= |       |       |       |       |
| nbsd` | s://g |       |       | "Mach |       |       |       |       |
|       | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3778) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `x8   | [     | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ⚠️    |
| 6-win | 2](ht |       |       | itle= |       |       |       |       |
| dows` | tps:/ |       |       | "Mach |       |       |       |       |
|       | /gith |       |       | ine C |       |       |       |       |
|       | ub.co |       |       | ode"} |       |       |       |       |
|       | m/zig |       |       |       |       |       |       |       |
|       | lang/ |       |       |       |       |       |       |       |
|       | zig/i |       |       |       |       |       |       |       |
|       | ssues |       |       |       |       |       |       |       |
|       | /537) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `     | [2    | ✅    | ✅    | [🖥️]{ | ✅    | ✅    | ✅    | ✅    |
| x86_6 | ](htt |       |       | title |       |       |       |       |
| 4-fre | ps:// |       |       | ="Mac |       |       |       |       |
| ebsd` | githu |       |       | hine  |       |       |       |       |
|       | b.com |       |       | Code" |       |       |       |       |
|       | /zigl |       |       | }[🛠️]{ |      |       |       |       |
|       | ang/z |       |       | title |       |       |       |       |
|       | ig/is |       |       | ="Sel |       |       |       |       |
|       | sues/ |       |       | f-Hos |       |       |       |       |
|       | 1759) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `x86_ | [2]   | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ⚠️    |
| 64-ma | (http |       |       | itle= |       |       |       |       |
| ccata | s://g |       |       | "Mach |       |       |       |       |
| lyst` | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       | [⚡]{ |       |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 5933) |       |       | ted"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `x86  | [2    | ✅    | ✅    | [🖥️]{t | ✅   | ✅    | ✅    | ⚠️    |
| _64-m | ](htt |       |       | itle= |       |       |       |       |
| acos` | ps:// |       |       | "Mach |       |       |       |       |
|       | githu |       |       | ine C |       |       |       |       |
|       | b.com |       |       | ode"} |       |       |       |       |
|       | /zigl |       |       | [⚡]{ |       |       |       |       |
|       | ang/z |       |       | title |       |       |       |       |
|       | ig/is |       |       | ="Sel |       |       |       |       |
|       | sues/ |       |       | f-Hos |       |       |       |       |
|       | 4897) |       |       | ted"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `x86_ | [2]   | ✅    | ✅    | [🖥️]{ | ✅    | ✅    | ✅    | ✅    |
| 64-ne | (http |       |       | title |       |       |       |       |
| tbsd` | s://g |       |       | ="Mac |       |       |       |       |
|       | ithub |       |       | hine  |       |       |       |       |
|       | .com/ |       |       | Code" |       |       |       |       |
|       | zigla |       |       | }[🛠️]{ |      |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 3082) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `     | [2    | ✅    | ✅    | [🖥️]{ | ✅    | ✅    | ✅    | ✅    |
| x86_6 | ](htt |       |       | title |       |       |       |       |
| 4-ope | ps:// |       |       | ="Mac |       |       |       |       |
| nbsd` | githu |       |       | hine  |       |       |       |       |
|       | b.com |       |       | Code" |       |       |       |       |
|       | /zigl |       |       | }[🛠️]{ |      |       |       |       |
|       | ang/z |       |       | title |       |       |       |       |
|       | ig/is |       |       | ="Sel |       |       |       |       |
|       | sues/ |       |       | f-Hos |       |       |       |       |
|       | 2016) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `     | [2]   | ✅    | ✅    | [🖥️]{ | ✅    | ✅    | ✅    | ✅    |
| x86_6 | (http |       |       | title |       |       |       |       |
| 4-win | s://g |       |       | ="Mac |       |       |       |       |
| dows` | ithub |       |       | hine  |       |       |       |       |
|       | .com/ |       |       | Code" |       |       |       |       |
|       | zigla |       |       | }[🛠️]{ |      |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 3080) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| ---   |       |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `aarc | [3]   | ✅    | ⚠️    | [🖥️]{ | ✅    | ✅    | ❌️    | ❌️    |
| h64-h | (http |       |       | title |       |       |       |       |
| aiku` | s://g |       |       | ="Mac |       |       |       |       |
|       | ithub |       |       | hine  |       |       |       |       |
|       | .com/ |       |       | Code" |       |       |       |       |
|       | zigla |       |       | }[🛠️]{ |      |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 3755) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `aa   | [3]   | ✅    | ✅    | [🖥️]{ | ✅    | ✅    | ❌️    | ❌️    |
| rch64 | (http |       |       | title |       |       |       |       |
| -ios` | s://g |       |       | ="Mac |       |       |       |       |
|       | ithub |       |       | hine  |       |       |       |       |
|       | .com/ |       |       | Code" |       |       |       |       |
|       | zigla |       |       | }[🛠️]{ |      |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 3782) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `aa   | [3]   | ✅    | ⚠️    | [🖥️]{ | ✅    | ✅    | ❌️    | ❌️    |
| rch64 | (http |       |       | title |       |       |       |       |
| -sere | s://g |       |       | ="Mac |       |       |       |       |
| nity` | ithub |       |       | hine  |       |       |       |       |
|       | .com/ |       |       | Code" |       |       |       |       |
|       | zigla |       |       | }[🛠️]{ |      |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 3686) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `aar  | [3]   | ✅    | ✅    | [🖥️]{ | ✅    | ✅    | ❌️    | ❌️    |
| ch64- | (http |       |       | title |       |       |       |       |
| tvos` | s://g |       |       | ="Mac |       |       |       |       |
|       | ithub |       |       | hine  |       |       |       |       |
|       | .com/ |       |       | Code" |       |       |       |       |
|       | zigla |       |       | }[🛠️]{ |      |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 3784) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `aa   | [3]   | ✅    | ✅    | [🖥️]{ | ✅    | ✅    | ❌️    | ❌️    |
| rch64 | (http |       |       | title |       |       |       |       |
| -visi | s://g |       |       | ="Mac |       |       |       |       |
| onos` | ithub |       |       | hine  |       |       |       |       |
|       | .com/ |       |       | Code" |       |       |       |       |
|       | zigla |       |       | }[🛠️]{ |      |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 3786) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `a    | [3]   | ✅    | ✅    | [🖥️]{ | ✅    | ✅    | ❌️    | ❌️    |
| arch6 | (http |       |       | title |       |       |       |       |
| 4-wat | s://g |       |       | ="Mac |       |       |       |       |
| chos` | ithub |       |       | hine  |       |       |       |       |
|       | .com/ |       |       | Code" |       |       |       |       |
|       | zigla |       |       | }[🛠️]{ |      |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 3788) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `     | [3]   | ✅    | ⚠️    | [🖥️]{t | ✅   | ✅    | ❌️    | ❌️    |
| arm-h | (http |       |       | itle= |       |       |       |       |
| aiku` | s://g |       |       | "Mach |       |       |       |       |
|       | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3756) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `loo  | [3]   | ❔    | ⚠️    | [🖥️]{t | ✅   | ✅    | ❌️    | ❌️    |
| ngarc | (http |       |       | itle= |       |       |       |       |
| h32-l | s://g |       |       | "Mach |       |       |       |       |
| inux` | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3696) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `mip  | [3]   | ✅    | ✅    | [🖥️]{t | ✅   | ❌️    | ❌️    | ❌️    |
| s64(e | (http |       |       | itle= |       |       |       |       |
| l)-ne | s://g |       |       | "Mach |       |       |       |       |
| tbsd` | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3765) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `risc | [3]   | ✅    | ⚠️    | [🖥️]{ | ✅    | ✅    | ❌️    | ❌️    |
| v64-h | (http |       |       | title |       |       |       |       |
| aiku` | s://g |       |       | ="Mac |       |       |       |       |
|       | ithub |       |       | hine  |       |       |       |       |
|       | .com/ |       |       | Code" |       |       |       |       |
|       | zigla |       |       | }[🛠️]{ |      |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 3759) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `ri   | [3]   | ✅    | ⚠️    | [🖥️]{ | ✅    | ✅    | ❌️    | ❌️    |
| scv64 | (http |       |       | title |       |       |       |       |
| -sere | s://g |       |       | ="Mac |       |       |       |       |
| nity` | ithub |       |       | hine  |       |       |       |       |
|       | .com/ |       |       | Code" |       |       |       |       |
|       | zigla |       |       | }[🛠️]{ |      |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 3687) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `wa   | [3]   | ❔    | ❌️    | [🖥️]{ | ✅    | ⚠️    | ❌️    | ❌️    |
| sm64- | (http |       |       | title |       |       |       |       |
| wasi` | s://g |       |       | ="Mac |       |       |       |       |
|       | ithub |       |       | hine  |       |       |       |       |
|       | .com/ |       |       | Code" |       |       |       |       |
|       | zigla |       |       | }[🛠️]{ |      |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 3092) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `     | [3]   | ✅    | ⚠️    | [🖥️]{t | ✅   | ✅    | ❌️    | ❌️    |
| x86-h | (http |       |       | itle= |       |       |       |       |
| aiku` | s://g |       |       | "Mach |       |       |       |       |
|       | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3761) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `x8   | [3]   | ✅    | ⚠️    | [🖥️]{t | ✅   | ✅    | ❌️    | ❌️    |
| 6-ill | (http |       |       | itle= |       |       |       |       |
| umos` | s://g |       |       | "Mach |       |       |       |       |
|       | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3689) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `x8   | [3    | ✅    | ✅    | [🖥️]{ | ✅    | ✅    | ❌️    | ❌️    |
| 6_64- | ](htt |       |       | title |       |       |       |       |
| drago | ps:// |       |       | ="Mac |       |       |       |       |
| nfly` | githu |       |       | hine  |       |       |       |       |
|       | b.com |       |       | Code" |       |       |       |       |
|       | /zigl |       |       | }[🛠️]{ |      |       |       |       |
|       | ang/z |       |       | title |       |       |       |       |
|       | ig/is |       |       | ="Sel |       |       |       |       |
|       | sues/ |       |       | f-Hos |       |       |       |       |
|       | 7149) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `x86  | [3    | ✅    | ⚠️    | [🖥️]{t | ✅   | ✅    | ❌️    | ❌️    |
| _64-h | ](htt |       |       | itle= |       |       |       |       |
| aiku` | ps:// |       |       | "Mach |       |       |       |       |
|       | githu |       |       | ine C |       |       |       |       |
|       | b.com |       |       | ode"} |       |       |       |       |
|       | /zigl |       |       | [⚡]{ |       |       |       |       |
|       | ang/z |       |       | title |       |       |       |       |
|       | ig/is |       |       | ="Sel |       |       |       |       |
|       | sues/ |       |       | f-Hos |       |       |       |       |
|       | 7691) |       |       | ted"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `     | [3    | ✅    | ⚠️    | [🖥️]{ | ✅    | ✅    | ❌️    | ❌️    |
| x86_6 | ](htt |       |       | title |       |       |       |       |
| 4-ill | ps:// |       |       | ="Mac |       |       |       |       |
| umos` | githu |       |       | hine  |       |       |       |       |
|       | b.com |       |       | Code" |       |       |       |       |
|       | /zigl |       |       | }[🛠️]{ |      |       |       |       |
|       | ang/z |       |       | title |       |       |       |       |
|       | ig/is |       |       | ="Sel |       |       |       |       |
|       | sues/ |       |       | f-Hos |       |       |       |       |
|       | 7152) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `x    | [3]   | ✅    | ⚠️    | [🖥️]{t | ✅   | ✅    | ❌️    | ❌️    |
| 86_64 | (http |       |       | itle= |       |       |       |       |
| -sere | s://g |       |       | "Mach |       |       |       |       |
| nity` | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       | [⚡]{ |       |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 3688) |       |       | ted"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| ---   |       |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `al   | [4]   | ❔    | ⚠️    | [📄]{ | ❌️    | ❌️    | ❌️    | ❌️    |
| pha-l | (http |       |       | title |       |       |       |       |
| inux` | s://g |       |       | ="C C |       |       |       |       |
|       | ithub |       |       | ode"} |       |       |       |       |
|       | .com/ |       |       |       |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 5671) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `alp  | [4]   | ❔    | ✅    | [📄]{ | ❌️    | ❌️    | ❌️    | ❌️    |
| ha-ne | (http |       |       | title |       |       |       |       |
| tbsd` | s://g |       |       | ="C C |       |       |       |       |
|       | ithub |       |       | ode"} |       |       |       |       |
|       | .com/ |       |       |       |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 5673) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `alph | [4]   | ❔    | ✅    | [📄]{ | ❌️    | ❌️    | ❌️    | ❌️    |
| a-ope | (http |       |       | title |       |       |       |       |
| nbsd` | s://g |       |       | ="C C |       |       |       |       |
|       | ithub |       |       | ode"} |       |       |       |       |
|       | .com/ |       |       |       |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 5676) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `arc( | [4]   | ❔    | ⚠️    | [📄   | ❌️    | ✅    | ✅    | ❌️    |
| eb)-l | (http |       |       | ]{ti  |       |       |       |       |
| inux` | s://g |       |       | tle=" |       |       |       |       |
|       | ithub |       |       | Assem |       |       |       |       |
|       | .com/ |       |       | bly C |       |       |       |       |
|       | zigla |       |       | ode"} |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3086) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `c    | [4]   | ❔    | ⚠️    | [📄   | ❌️    | ✅    | ✅    | ❌️    |
| sky-l | (http |       |       | ]{ti  |       |       |       |       |
| inux` | s://g |       |       | tle=" |       |       |       |       |
|       | ithub |       |       | Assem |       |       |       |       |
|       | .com/ |       |       | bly C |       |       |       |       |
|       | zigla |       |       | ode"} |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3087) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `h    | [4]   | ❔    | ⚠️    | [📄]{ | ❌️    | ❌️    | ❌️    | ❌️    |
| ppa-l | (http |       |       | title |       |       |       |       |
| inux` | s://g |       |       | ="C C |       |       |       |       |
|       | ithub |       |       | ode"} |       |       |       |       |
|       | .com/ |       |       |       |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 5672) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `hp   | [4]   | ❔    | ✅    | [📄]{ | ❌️    | ❌️    | ❌️    | ❌️    |
| pa-ne | (http |       |       | title |       |       |       |       |
| tbsd` | s://g |       |       | ="C C |       |       |       |       |
|       | ithub |       |       | ode"} |       |       |       |       |
|       | .com/ |       |       |       |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 5674) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `hpp  | [4]   | ❔    | ✅    | [📄]{ | ❌️    | ❌️    | ❌️    | ❌️    |
| a-ope | (http |       |       | title |       |       |       |       |
| nbsd` | s://g |       |       | ="C C |       |       |       |       |
|       | ithub |       |       | ode"} |       |       |       |       |
|       | .com/ |       |       |       |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 5677) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `hpp  | [4]   | ❔    | ❌️    | [📄]{ | ❌️    | ❌️    | ❌️    | ❌️    |
| a64-l | (http |       |       | title |       |       |       |       |
| inux` | s://g |       |       | ="C C |       |       |       |       |
|       | ithub |       |       | ode"} |       |       |       |       |
|       | .com/ |       |       |       |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 6063) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `m    | [4]   | ❔    | ⚠️    | [🖥️]{t | ❌️   | ✅    | ❌️    | ❌️    |
| 68k-h | (http |       |       | itle= |       |       |       |       |
| aiku` | s://g |       |       | "Mach |       |       |       |       |
|       | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3757) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `m    | [4]   | ❔    | ✅    | [🖥️]{t | ❌️   | ✅    | ✅    | ❌️    |
| 68k-l | (http |       |       | itle= |       |       |       |       |
| inux` | s://g |       |       | "Mach |       |       |       |       |
|       | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3089) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `m6   | [4]   | ❔    | ✅    | [🖥️]{t | ❌️   | ✅    | ✅    | ❌️    |
| 8k-ne | (http |       |       | itle= |       |       |       |       |
| tbsd` | s://g |       |       | "Mach |       |       |       |       |
|       | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3090) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `m88  | [4]   | ❔    | ❌️    | [📄]{ | ❌️    | ❌️    | ❌️    | ❌️    |
| k-ope | (http |       |       | title |       |       |       |       |
| nbsd` | s://g |       |       | ="C C |       |       |       |       |
|       | ithub |       |       | ode"} |       |       |       |       |
|       | .com/ |       |       |       |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 6065) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `m    | [4]   | ❔    | ⚠️    | [📄]{ | ❌️    | ❌️    | ❌️    | ❌️    |
| icrob | (http |       |       | title |       |       |       |       |
| laze( | s://g |       |       | ="C C |       |       |       |       |
| el)-l | ithub |       |       | ode"} |       |       |       |       |
| inux` | .com/ |       |       |       |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 5670) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `o    | [4]   | ❔    | ✅    | [📄]{ | ❌️    | ✅    | ❌️    | ❌️    |
| r1k-l | (http |       |       | title |       |       |       |       |
| inux` | s://g |       |       | ="C C |       |       |       |       |
|       | ithub |       |       | ode"} |       |       |       |       |
|       | .com/ |       |       |       |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 6064) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `sh(  | [4]   | ❔    | ⚠️    | [📄]{ | ❌️    | ❌️    | ❌️    | ❌️    |
| eb)-l | (http |       |       | title |       |       |       |       |
| inux` | s://g |       |       | ="C C |       |       |       |       |
|       | ithub |       |       | ode"} |       |       |       |       |
|       | .com/ |       |       |       |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 5669) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `sh(e | [4]   | ❔    | ✅    | [📄]{ | ❌️    | ❌️    | ❌️    | ❌️    |
| b)-ne | (http |       |       | title |       |       |       |       |
| tbsd` | s://g |       |       | ="C C |       |       |       |       |
|       | ithub |       |       | ode"} |       |       |       |       |
|       | .com/ |       |       |       |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 5675) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `s    | [4]   | ❔    | ✅    | [📄]{ | ❌️    | ❌️    | ❌️    | ❌️    |
| h-ope | (http |       |       | title |       |       |       |       |
| nbsd` | s://g |       |       | ="C C |       |       |       |       |
|       | ithub |       |       | ode"} |       |       |       |       |
|       | .com/ |       |       |       |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 5678) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `sp   | [4]   | ❔    | ⚠️    | [🖥️]{t | ❌️   | ✅    | ✅    | ❌️    |
| arc-l | (http |       |       | itle= |       |       |       |       |
| inux` | s://g |       |       | "Mach |       |       |       |       |
|       | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3081) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `spa  | [4]   | ❔    | ✅    | [🖥️]{t | ❌️   | ❌️    | ✅    | ❌️    |
| rc-ne | (http |       |       | itle= |       |       |       |       |
| tbsd` | s://g |       |       | "Mach |       |       |       |       |
|       | ithub |       |       | ine C |       |       |       |       |
|       | .com/ |       |       | ode"} |       |       |       |       |
|       | zigla |       |       |       |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3770) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `spar | [4]   | ❔    | ⚠️    | [🖥️]{ | ⚠️    | ❌️    | ❌️    | ❌️    |
| c64-h | (http |       |       | title |       |       |       |       |
| aiku` | s://g |       |       | ="Mac |       |       |       |       |
|       | ithub |       |       | hine  |       |       |       |       |
|       | .com/ |       |       | Code" |       |       |       |       |
|       | zigla |       |       | }[🛠️]{ |      |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 3760) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `spar | [4    | ❔    | ✅    | [🖥️]{ | ⚠️    | ✅    | ✅    | ❌️    |
| c64-l | ](htt |       |       | title |       |       |       |       |
| inux` | ps:// |       |       | ="Mac |       |       |       |       |
|       | githu |       |       | hine  |       |       |       |       |
|       | b.com |       |       | Code" |       |       |       |       |
|       | /zigl |       |       | }[🛠️]{ |      |       |       |       |
|       | ang/z |       |       | title |       |       |       |       |
|       | ig/is |       |       | ="Sel |       |       |       |       |
|       | sues/ |       |       | f-Hos |       |       |       |       |
|       | 4931) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `     | [4]   | ❔    | ✅    | [🖥️]{ | ⚠️    | ❌️    | ✅    | ❌️    |
| sparc | (http |       |       | title |       |       |       |       |
| 64-ne | s://g |       |       | ="Mac |       |       |       |       |
| tbsd` | ithub |       |       | hine  |       |       |       |       |
|       | .com/ |       |       | Code" |       |       |       |       |
|       | zigla |       |       | }[🛠️]{ |      |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 3771) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `s    | [4]   | ❔    | ✅    | [🖥️]{ | ⚠️    | ❌️    | ✅    | ❌️    |
| parc6 | (http |       |       | title |       |       |       |       |
| 4-ope | s://g |       |       | ="Mac |       |       |       |       |
| nbsd` | ithub |       |       | hine  |       |       |       |       |
|       | .com/ |       |       | Code" |       |       |       |       |
|       | zigla |       |       | }[🛠️]{ |      |       |       |       |
|       | ng/zi |       |       | title |       |       |       |       |
|       | g/iss |       |       | ="Sel |       |       |       |       |
|       | ues/2 |       |       | f-Hos |       |       |       |       |
|       | 3779) |       |       | ted I |       |       |       |       |
|       |       |       |       | n Dev |       |       |       |       |
|       |       |       |       | elopm |       |       |       |       |
|       |       |       |       | ent"} |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| `xt   | [4]   | ❔    | ❌️    | [📄   | ❌️    | ❌️    | ❌️    | ❌️    |
| ensa( | (http |       |       | ]{ti  |       |       |       |       |
| eb)-l | s://g |       |       | tle=" |       |       |       |       |
| inux` | ithub |       |       | Assem |       |       |       |       |
|       | .com/ |       |       | bly C |       |       |       |       |
|       | zigla |       |       | ode"} |       |       |       |       |
|       | ng/zi |       |       |       |       |       |       |       |
|       | g/iss |       |       |       |       |       |       |       |
|       | ues/2 |       |       |       |       |       |       |       |
|       | 3081) |       |       |       |       |       |       |       |
+-------+-------+-------+-------+-------+-------+-------+-------+-------+

{#header_close#} {#header_open\|OS Version Requirements#}

The Zig standard library has minimum version requirements for some
supported operating systems, which in turn affect the Zig compiler
itself.

  Operating System   Minimum Version
  ------------------ -----------------
  DragonFly BSD      6.0
  FreeBSD            14.0
  Linux              5.10
  NetBSD             10.1
  OpenBSD            7.8
  macOS              13.0
  Windows            10

{#header_close#} {#header_open\|Additional Platforms#}

Zig also has varying levels of support for these targets, for which the
tier system does not quite apply:

-   `aarch64-driverkit`
-   `aarch64[_be]-freestanding`
-   `aarch64-fuchsia`
-   `aarch64-hurd`
-   `aarch64-uefi`
-   `alpha-freestanding`
-   `amdgcn-amdhsa`
-   `amdgcn-amdpal`
-   `amdgcn-mesa3d`
-   `arc[eb]-freestanding`
-   `arm[eb]-freestanding`
-   `arm-3ds`
-   `arm-fuchsia`
-   `arm-uefi`
-   `arm-vita`
-   `avr-freestanding`
-   `bpf(eb,el)-freestanding`
-   `csky-freestanding`
-   `hexagon-freestanding`
-   `hppa[64]-freestanding`
-   `kalimba-freestanding`
-   `kvx-freestanding`
-   `lanai-freestanding`
-   `loongarch(32,64)-freestanding`
-   `loongarch(32,64)-uefi`
-   `m68k-freestanding`
-   `microblaze[el]-freestanding`
-   `mips[64][el]-freestanding`
-   `mipsel-psp`
-   `msp430-freestanding`
-   `nvptx[64]-cuda`
-   `nvptx[64]-nvcl`
-   `or1k-freestanding`
-   `powerpc[64][le]-freestanding`
-   `powerpc64-ps3`
-   `propeller-freestanding`
-   `riscv(32,64)[be]-freestanding`
-   `riscv(32,64)-uefi`
-   `riscv64-fuchsia`
-   `s390x-freestanding`
-   `sh[eb]-freestanding`
-   `sparc[64]-freestanding`
-   `spirv(32,64)-opencl`
-   `spirv(32,64)-opengl`
-   `spirv(32,64)-vulkan`
-   `thumb[eb]-freestanding`
-   `thumb-fuchsia`
-   `ve-freestanding`
-   `wasm(32,64)-emscripten`
-   `wasm(32,64)-freestanding`
-   `x86[_16,_64]-freestanding`
-   `x86[_64]-hurd`
-   `x86[_64]-uefi`
-   `x86_64-driverkit`
-   `x86_64-fuchsia`
-   `x86_64-plan9`
-   `x86_64-ps4`
-   `x86_64-ps5`
-   `xcore-freestanding`
-   `xtensa[eb]-freestanding`

{#header_close#} {#header_close#} {#header_open\|Language Changes#}
{#header_open\|switch#} ![Carmen the
Allocgator](https://ziglang.org/img/Carmen_4.svg){style="height: 18em; float: right"}

{#syntax#}packed struct{#endsyntax#} and {#syntax#}packed
union{#endsyntax#} may now be used as switch prong items. They are
compared solely based on their backing integer, just like in equality
comparisons:

    {#syntax#}
    const U = packed union(u2) {
        a: i2,
        b: u2,
    };

    const u: U = .{ .a = -1 };
    switch (u) {
        .{ .b = 3 } => {},
        else => unreachable,
    }
        {#endsyntax#}

Other newly implemented features:

-   decl literals and everything else requiring a result type (e.g.
    {#syntax#}@enumFromInt{#endsyntax#}) may now be used as switch prong
    items
-   union tag captures are now allowed for all prongs, not just
    {#syntax#}inline{#endsyntax#} ones
-   switch prongs may contain errors which are not in the error set
    being switched on, if these prongs contain {#syntax#}=\> comptime
    unreachable{#endsyntax#}
-   switch prong captures may no longer all be discarded

Bug fixes:

-   lots of issues with switching on one-possible-value types are now
    fixed
-   the rules around unreachable {#syntax#}else{#endsyntax#} prongs when
    switching on errors now apply to *any* switch on an error, not just
    to {#syntax#}switch_block_err_union{#endsyntax#}, and are applied
    properly based on the AST
-   switching on {#syntax#}void{#endsyntax#} no longer requires an
    {#syntax#}else{#endsyntax#} prong unconditionally
-   lazy values are properly resolved before any comparisons with prong
    items
-   evaluation order between all kinds of switch statements is now the
    same, with or without label

{#header_close#} {#header_open\|Equality Comparisons on Packed Unions#}

This used to already be possible by wrapping the {#syntax#}packed
union{#endsyntax#} into a {#syntax#}packed struct{#endsyntax#}. Now
it\'s also possible without having to do that.

{#header_close#} {#header_open\|@cImport Moving to Build System#}

In the future, {#link\|C Translation#} will be handled via the
{#link\|Build System#} rather than the {#syntax#}@cImport{#endsyntax#}
language builtin, which is now deprecated.

Upgrade guide:

{#syntax_block\|zig\|c.zig#} pub const c = \@cImport({
\@cInclude(\"stdio.h\"); \@cInclude(\"math.h\"); \@cInclude(\"time.h\");
\@cInclude(\"stdlib.h\"); \@cInclude(\"epoxy/gl.h\");
\@cInclude(\"GLFW/glfw3.h\"); }); {#end_syntax_block#}

    {#syntax#}
    const c = @import("c.zig").c;
        {#endsyntax#}

⬇️ {#syntax_block\|c\|c.h#} #include #include #include #include #include
#include {#end_syntax_block#} {#syntax_block\|zig\|build.zig#} const
translate_c = b.addTranslateC(.{ .root_source_file =
b.path(\"src/c.h\"), .target = target, .optimize = optimize, });
translate_c.linkSystemLibrary(\"glfw\", .{});
translate_c.linkSystemLibrary(\"epoxy\", .{}); const exe =
b.addExecutable(.{ .name = \"tetris\", .root_module = b.createModule(.{
.root_source_file = b.path(\"src/main.zig\"), .optimize = optimize,
.target = target, .imports = &.{ .{ .name = \"c\", .module =
translate_c.createModule(), }, }, }), }); {#end_syntax_block#}

    {#syntax#}
    const c = @import("c");
        {#endsyntax#}

By doing this, the translated C code will be identical to how it was
before with {#syntax#}@cImport{#endsyntax#}.

Alternately, you can add [the official translate-c
package](https://codeberg.org/ziglang/translate-c) as an explicit
dependency and gain access to more [translation customization
options](https://codeberg.org/ziglang/translate-c/src/commit/41c10fa66ac81343c33f2b8c746f181b41eaaa27/build/Translator.zig#L40).

{#header_close#} {#header_open\|@Type Replaced with Individual
Type-Creating Builtin Functions#}

Zig 0.16.0 implements long-accepted proposal
[#10710](https://github.com/ziglang/zig/issues/10710) to remove the
{#syntax#}@Type{#endsyntax#} builtin from the language and replace it
with individual builtins like {#syntax#}@Int{#endsyntax#} and
{#syntax#}@Struct{#endsyntax#}. While {#syntax#}@Type{#endsyntax#} is a
simple parallel to {#syntax#}@typeInfo{#endsyntax#}, in practice, it was
clunky to use for common tasks, leading users to reach for helpers like
{#syntax#}std.meta.Int{#endsyntax#}. Ignoring
{#syntax#}@Vector{#endsyntax#}, which already existed,
{#syntax#}@Type{#endsyntax#} has been replaced with 8 new builtin
functions:

    {#syntax#}
    @EnumLiteral() type

    @Int(comptime signedness: std.builtin.Signedness, comptime bits: u16) type

    @Tuple(comptime field_types: []const type) type

    @Pointer(
        comptime size: std.builtin.Type.Pointer.Size,
        comptime attrs: std.builtin.Type.Pointer.Attributes,
        comptime Element: type,
        comptime sentinel: ?Element,
    ) type

    @Fn(
        comptime param_types: []const type,
        comptime param_attrs: *const [param_types.len]std.builtin.Type.Fn.Param.Attributes,
        comptime ReturnType: type,
        comptime attrs: std.builtin.Type.Fn.Attributes,
    ) type

    @Struct(
        comptime layout: std.builtin.Type.ContainerLayout,
        comptime BackingInt: ?type,
        comptime field_names: []const []const u8,
        comptime field_types: *const [field_names.len]type,
        comptime field_attrs: *const [field_names.len]std.builtin.Type.StructField.Attributes,
    ) type

    @Union(
        comptime layout: std.builtin.Type.ContainerLayout,
        /// Either the integer tag type, or the integer backing type, depending on `layout`.
        comptime ArgType: ?type,
        comptime field_names: []const []const u8,
        comptime field_types: *const [field_names.len]type,
        comptime field_attrs: *const [field_names.len]std.builtin.Type.UnionField.Attributes,
    ) type

    @Enum(
        comptime TagInt: type,
        comptime mode: std.builtin.Type.Enum.Mode,
        comptime field_names: []const []const u8,
        comptime field_values: *const [field_names.len]TagInt,
    ) type
        {#endsyntax#}

#### Enum Literal

{#syntax#}@EnumLiteral(){#endsyntax#} returns the \"enum literal\" type,
which is the type of uncoerced enum literals like
{#syntax#}.foo{#endsyntax#}. While it is equivalent to
{#syntax#}@TypeOf(.something){#endsyntax#}, the new
{#syntax#}@EnumLiteral(){#endsyntax#} is preferred for consistency.

    {#syntax#}
    @Type(.enum_literal)
        {#endsyntax#}

⬇️

    {#syntax#}
    @EnumLiteral()
        {#endsyntax#}

#### Integer

{#syntax#}@Int{#endsyntax#} is perhaps the most useful new builtin for
simple metaprogramming. The usage is equivalent to the now-deprecated
{#syntax#}std.meta.Int{#endsyntax#} helper: given a signedness and bit
count, it returns an integer type with those properties. This new usage
results in significantly more concise and readable code.

    {#syntax#}
    @Type(.{ .int = .{ .signedness = .unsigned, .bits = 10 } })
        {#endsyntax#}

⬇️

    {#syntax#}
    @Int(.unsigned, 10)
        {#endsyntax#}

#### Tuple

{#syntax#}@Tuple{#endsyntax#} is equivalent to the now-deprecated
{#syntax#}std.meta.Tuple{#endsyntax#} helper. It accepts a slice of
types, and returns a tuple type whose fields have those types.

    {#syntax#}
    @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = &.{.{
            .name = "0",
            .type = u32,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(u32),
        }, .{
            .name = "1",
            .type = [2]f64,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf([2]f64),
        }},
        .decls = &.{},
        .is_tuple = true,
    } })
        {#endsyntax#}

⬇️

    {#syntax#}
    @Tuple(&.{ u32, [2]f64 })
        {#endsyntax#}

To simplify the language, it is no longer possible to reify tuple types
with {#syntax#}comptime{#endsyntax#} fields.

#### Pointer

{#syntax#}@Pointer{#endsyntax#} returns a pointer type, equivalent to
{#syntax#}@Type(.{ .pointer = \... }){#endsyntax#}. Notably, it uses the
new {#syntax#}std.builtin.Type.Pointer.Attributes{#endsyntax#} type,
which uses struct field default values to make the usage more concise
and more closely aligned with literal pointer type syntax.

    {#syntax#}
    @Type(.{ .pointer = .{
        .size = .one,
        .is_const = true,
        .is_volatile = false,
        .alignment = @alignOf(u32),
        .address_space = .generic,
        .child = u32,
        .is_allowzero = false,
        .sentinel_ptr = null,
    } })
        {#endsyntax#}

⬇️

    {#syntax#}
    @Pointer(.one, .{ .@"const" = true }, u32, null)
        {#endsyntax#}

    {#syntax#}
    @Type(.{ .pointer = .{
        .size = .many,
        .is_const = false,
        .is_volatile = false,
        .alignment = 1,
        .address_space = .generic,
        .child = u64,
        .is_allowzero = false,
        .sentinel_ptr = &@as(u64, 0),
    } })
        {#endsyntax#}

⬇️

    {#syntax#}
    @Pointer(.many, .{ .@"align" = 1 }, u64, 0)
        {#endsyntax#}

#### Function

{#syntax#}@Fn{#endsyntax#} returns a function type, equivalent to
{#syntax#}@Type(.{ .@\"fn\" = \... }){#endsyntax#}. Like for pointers,
new helper types have been introduced to make this builtin simpler to
use. Parameters are specified with two separate arguments: the first
specifies all parameter types, and the second specifies \"attributes\"
(which currently consist only of the {#syntax#}noalias{#endsyntax#}
flag).

    {#syntax#}
    @Type(.{ .@"fn" = .{
        .calling_convention = .c,
        .is_generic = false,
        .is_var_args = true,
        .return_type = u32,
        .params = &.{.{
            .is_generic = false,
            .is_noalias = false,
            .type = f64,
        }, .{
            .is_generic = false,
            .is_noalias = true,
            .type = *const anyopaque,
        }},
    } })
        {#endsyntax#}

⬇️

    {#syntax#}
    @Fn(
        &.{ f64, *const anyopaque },
        &.{ .{}, .{ .@"noalias" = true } },
        u32,
        .{ .@"callconv" = .c, .varargs = true },
    )
        {#endsyntax#}

This is one of several of the new builtins which accepts arguments in a
\"struct of arrays\" style. An advantage of this style is that it makes
it easy to specify a fixed value for all elements. For instance, to use
the \"default\" attributes {#syntax#}.{}{#endsyntax#} for all
parameters, use {#syntax#}&@splat(.{}){#endsyntax#}:

    {#syntax#}
    @Fn(param_types, &@splat(.{}), ReturnType, .{ .@"callconv" = .c })
        {#endsyntax#}

#### Struct

{#syntax#}@Struct{#endsyntax#} returns a {#syntax#}struct{#endsyntax#}
type, equivalent to {#syntax#}@Type(.{ .@\"struct\" = \...
}){#endsyntax#}. Like {#syntax#}@Fn{#endsyntax#}, it uses a \"struct of
arrays\" strategy to pass information about fields. Fields are passed as
three separate arrays---field names, field types, and field
attributes---where the latter includes alignment, the
{#syntax#}comptime{#endsyntax#} flag, and the field\'s default value (if
any).

    {#syntax#}
    @Type(.{ .@"struct" = .{
        .layout = .@"extern",
        .fields = &.{.{
            .name = "foo",
            .type = [2]f64,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = 1,
        }, .{
            .name = "bar",
            .type = u32,
            .default_value_ptr = &@as(u32, 123),
            .is_comptime = true,
            .alignment = @alignOf(u32),
        }},
        .decls = &.{},
        .is_tuple = false,
    } })
        {#endsyntax#}

⬇️

    {#syntax#}
    @Struct(
        .@"extern",
        null,
        &.{ "foo", "bar" },
        &.{ [2]f64, u32 },
        &.{
            .{ .@"align" = 1 },
            .{ .@"comptime" = true, .default_value_ptr = &@as(u32, 123) },
        },
    )
        {#endsyntax#}

Again, {#syntax#}&@splat(.{}){#endsyntax#} is useful for specifying
\"default\" field attributes. In some cases, it is even useful to use
{#syntax#}@splat{#endsyntax#} for the field types. For instance, to
create a struct with homogeneous field types of
{#syntax#}FieldType{#endsyntax#} where the field names match the names
of an enum type {#syntax#}MyEnum{#endsyntax#}:

    {#syntax#}
    const MyStruct = @Struct(.auto, null, std.meta.fieldNames(MyEnum), &@splat(FieldType), &@splat(.{}));
        {#endsyntax#}

#### Union

{#syntax#}@Union{#endsyntax#} returns a {#syntax#}union{#endsyntax#}
type, equivalent to {#syntax#}@Type(.{ .@\"union\" = \...
}){#endsyntax#}. It is quite similar to {#syntax#}@Struct{#endsyntax#}
in usage.

    {#syntax#}
    @Type(.{ .@"union" = .{
        .layout = .auto,
        .tag_type = MyEnum,
        .fields = &.{.{
            .name = "foo",
            .type = i64,
            .alignment = @alignOf(i64),
        }, .{
            .name = "bar",
            .type = f64,
            .alignment = @alignOf(f64),
        }},
        .decls = &.{},
    } })
        {#endsyntax#}

⬇️

    {#syntax#}
    @Union(
        .auto,
        MyEnum,
        &.{ "foo", "bar" },
        &.{ i64, f64 },
        &@splat(.{}),
    )
        {#endsyntax#}

#### Enum

{#syntax#}@Enum{#endsyntax#} returns an {#syntax#}enum{#endsyntax#}
type, equivalent to {#syntax#}@Type(.{ .@\"enum\" = \...
}){#endsyntax#}. It is somewhat similar to
{#syntax#}@Struct{#endsyntax#} in usage, but accepts an array of field
\*tag values\* rather than field \*types\*.

    {#syntax#}
    @Type(.{ .@"enum" = .{
        .tag_type = u32,
        .fields = &.{.{
            .name = "foo",
            .value = 0,
        }, .{
            .name = "bar",
            .value = 1,
        }},
        .decls = &.{},
        .is_exhaustive = true,
    } })
        {#endsyntax#}

⬇️

    {#syntax#}
    @Enum(
        u32,
        .exhaustive,
        &.{ "foo", "bar" },
        &.{ 0, 1 },
    )
        {#endsyntax#}

#### Float

There is no {#syntax#}@Float{#endsyntax#} builtin, because there are
only 5 runtime floating-point types, so this functionality is trivially
implemented in userland. The function
{#syntax#}std.meta.Float{#endsyntax#} can be used if creating float
types from a bit count is required.

#### Array

There is no {#syntax#}@Array{#endsyntax#} builtin, because this
functionality is trivial to implement with normal array syntax. A
general {#syntax#}Array{#endsyntax#} function would look like this:

    {#syntax#}
    fn Array(comptime len: usize, comptime Elem: type, comptime sentinel: ?Elem) type {
        return if (sentinel) |s| [len:s]Elem else [len]Elem;
    }
        {#endsyntax#}

In practice, this generality is not usually necessary, and use sites can
simply be replaced with one of {#syntax#}\[len\]Elem{#endsyntax#} or
{#syntax#}\[len:s\]Elem{#endsyntax#}.

#### Opaque

There is no {#syntax#}@Opaque{#endsyntax#} builtin. Instead, write
{#syntax#}opaque {}{#endsyntax#}.

#### Optional

There is no {#syntax#}@Optional{#endsyntax#} builtin. Instead, write
{#syntax#}?T{#endsyntax#}.

#### Error Union

There is no {#syntax#}@ErrorUnion{#endsyntax#} builtin. Instead, write
{#syntax#}E!T{#endsyntax#}.

#### Error Set

There is no {#syntax#}@ErrorSet{#endsyntax#} builtin. To simplify the
language, it is no longer possible to reify error sets. Instead, declare
your error sets explicitly using {#syntax#}error{ \... }{#endsyntax#}
syntax. {#header_close#} {#header_open\|Allow Small Integer Types to
Coerce to Floats#}

If all possible values of an integer type can fit in a floating point
type without rounding, the integer may coerce to the float without an
explicit conversion. This is determined by comparing the number of bits
of precision in the integer type and the significand in the floating
point type. Larger integer types will still require
{#syntax#}@floatFromInt{#endsyntax#}.

    {#syntax#}
    var foo_int: u24 = 123;
    var foo_float: f32 = @floatFromInt(foo_int);

    var bar_int: u25 = 123;
    var bar_float: f32 = @floatFromInt(bar_int);
        {#endsyntax#}

⬇️

    {#syntax#}
    var foo_int: u24 = 123;
    var foo_float: f32 = foo_int; // Safe coercion

    var bar_int: u25 = 123;
    var bar_float: f32 = @floatFromInt(bar_int); // Explicit conversion is still required
        {#endsyntax#}

This is part of a larger effort to improve ergonomics for making video
games in Zig.

{#header_close#} {#header_open\|Forbid Runtime Vector Indexes#}

Upgrade guide:

    {#syntax#}
    for (0..vector_len) |i| {
       _ = vector[i];
    }
        {#endsyntax#}

⬇️

    {#syntax#}
    // coerce the vector to an array
    const vector_type = @typeInfo(@TypeOf(vector)).vector;
    const array: [vector_type.len]vector_type.child = vector;
    for (&array) |elem| {
        _ = elem;
    }
        {#endsyntax#}

This was changed as part of {#link\|Reworked Byval Syntax Lowering#}.

{#header_close#} {#header_open\|Vectors and Arrays No Longer Support
In-Memory Coercion#}

If you were using {#syntax#}@ptrCast{#endsyntax#} to convert between
array memory and vector memory, use coercion instead.

If you were coercing from {#syntax#}anyerror\![4\]i32{#endsyntax#} to
{#syntax#}anyerror!@Vector(4, i32){#endsyntax#} or similar, you need to
unwrap the error first.

{#header_close#} {#header_open\|Forbid Trivial Local Address Returned
from Functions#}

One thing that Zig beginners struggle with - particularly those
unfamiliar with manual memory management - is returning pointers to
local variables from functions.

This is challenging to address, because it is legal to return an invalid
pointer:

    {#syntax#}
    fn foo() *i32 {
        return undefined;
    }
        {#endsyntax#}

This is a perfectly valid function - the illegal operation only occurs
if the returned pointer is dereferenced. Even then, it\'s legal to have
a function that unconditionally invokes illegal behavior:

    {#syntax#}
    fn bar() noreturn {
        unreachable; // equivalent to foo().*
    }
        {#endsyntax#}

Given this function, the expression {#syntax#}bar(){#endsyntax#} is
equivalent to the expression {#syntax#}unreachable{#endsyntax#}.

So how then, can we make it a compile error to return an invalid pointer
from a function? Syntactic pedantry. We forbid all expressions that
trivially (i.e. without type checking) lower to {#syntax#}return
undefined{#endsyntax#} with the justification that the expression should
instead be written canonically as {#syntax#}return
undefined{#endsyntax#}.

Thus the following compile error was born:

    {#syntax#}
    fn foo() *i32 {
        var x: i32 = 1234;
        return &x;
    }
        {#endsyntax#}

    test.zig:3:13: error: returning address of expired local variable 'x'
        return &x;
                ^
    test.zig:2:9: note: declared runtime-known here
        var x: i32 = 1234;
            ^

[More compile errors of this nature are
planned.](https://github.com/ziglang/zig/issues/25312)

{#header_close#} {#header_open\|Unary Float Builtins Forward Result
Type#}

Previously Zig would not forward a result type through the following
builtin functions,

    {#syntax#}
    @sqrt
    @sin
    @cos
    @tan
    @exp
    @exp2
    @log
    @log2
    @log10
    @floor
    @ceil
    @trunc
    @round
        {#endsyntax#}

This has now been changed. Where previous you couldn\'t write,

    {#syntax#}
    const x: f64 = @sqrt(@floatFromInt(N));
        {#endsyntax#}

since {#syntax#}@sqrt{#endsyntax#} would not forward the
{#syntax#}f64{#endsyntax#} result type to
{#syntax#}@floatFromInt{#endsyntax#}, now you can.

This is part of a larger effort to improve ergonomics for making video
games in Zig.

{#header_close#} {#header_open\|@floor, \@ceil, \@round, \@trunc
Conversion to Integers#}

{#syntax#}@floor{#endsyntax#}, {#syntax#}@ceil{#endsyntax#},
{#syntax#}@round{#endsyntax#}, and {#syntax#}@trunc{#endsyntax#} now can
be used to convert a floating-point value to an integer value:

{#code\|float-conversion.zig#}

{#syntax#}@intFromFloat{#endsyntax#} is now redundant with
{#syntax#}@trunc{#endsyntax#} and is therefore deprecated.

This is part of a larger effort to improve ergonomics for making video
games in Zig.

{#header_close#} {#header_open\|Forbid Unused Bits in Packed Unions#}

There was not plainly one possible way of mapping packed union
representation to bits, a desirable feature of other packed types. For
example, {#syntax#}enum (u5) { \... }{#endsyntax#} plainly represents 5
bits in an obvious manner and is allowed in packed contexts, but
{#syntax#}?u8{#endsyntax#} has two reasonable ways of mapping to 9 bits
and is therefore not allowed in packed contexts.

This ambiguity is resolved by requiring all fields of a packed union to
have the same {#syntax#}@bitSizeOf{#endsyntax#} as a backing integer
type.

Upgrade guide:

    {#syntax#}
    const U = packed union {
        x: u8,
        y: u16,
    };
        {#endsyntax#}

⬇️

    {#syntax#}
    const U = packed union(u16) {
        x: packed struct(u16) {
            data: u8,
            padding: u8 = 0,
        },
        y: u16,
    };
        {#endsyntax#}

{#header_close#} {#header_open\|Forbid Pointers in Packed Structs and
Unions#}

Fields of {#syntax#}packed struct{#endsyntax#} and {#syntax#}packed
union{#endsyntax#} types are no longer permitted to be pointers,
implementing proposal
[#24657](https://github.com/ziglang/zig/issues/24657).

The primary reason for this change is that constant values containing
non-byte-aligned pointers cannot be represented in the vast majority of
binary formats. Additionally, there are some targets on which pointers
cannot be represented merely as their address bits, but have additional
metadata bits too---in this case it does not make sense to pack pointers
into an integer, as {#syntax#}packed{#endsyntax#} types purport to do.

If you were relying on pointers in {#syntax#}packed{#endsyntax#} types,
you can instead use a {#syntax#}usize{#endsyntax#} field and convert to
and from a pointer using {#syntax#}@ptrFromInt{#endsyntax#} and
{#syntax#}@intFromPtr{#endsyntax#}.

{#header_close#} {#header_open\|Allow Explicit Backing Integers on
Packed Unions#}

Although previous versions of Zig allowed {#syntax#}packed
struct{#endsyntax#} types to specify their backing integer type with the
syntax {#syntax#}packed struct(T){#endsyntax#}, this was not previously
permitted for {#syntax#}packed union{#endsyntax#} types. In Zig 0.16.0,
this has now been allowed.

{#code\|packed_union_explicit_backing_int.zig#}

Note that due to {#link\|Forbid Enum and Packed Types with Implicit
Backing Types in Extern Contexts#}, specifying a backing type like this
is sometimes required.

{#header_close#} {#header_open\|Forbid Enum and Packed Types with
Implicit Backing Types in Extern Contexts#}

{#syntax#}enum{#endsyntax#} types with inferred integer tag types, and
{#syntax#}packed struct{#endsyntax#} and {#syntax#}packed
union{#endsyntax#} types with inferred integer backing types, are no
longer considered valid {#syntax#}extern{#endsyntax#} types. This
implements proposal
[#24714](https://github.com/ziglang/zig/issues/24714).

This breaking change was made to avoid the ABI of a type being
determined entirely implicitly based solely on its fields. In
particular, this matters because {#syntax#}u8{#endsyntax#} and
{#syntax#}i8{#endsyntax#} may have differing ABIs in some contexts, and
it is not clear which is being used if the choice is implicit.

If this has introduced a compile error in your code, resolve it by
adding an explicit tag type or backing type. (See {#link\|Allow Explicit
Backing Integers on Packed Unions#} for a related language change in Zig
0.16.0.)

{#code\|extern_implicit_backing_type.zig#} ⬇️
{#code\|extern_explicit_backing_type.zig#} {#header_close#}
{#header_open\|Lazy Field Analysis#} ![Ziggy the
Ziguana](https://ziglang.org/img/Ziggy_11.svg){style="height: 9em; float: right"}

A problem we noticed since introducing {#link\|I/O as an Interface#} is
that if a type is used as a namespace, its fields will be analyzed
anyway. For instance, using {#syntax#}std.Io.Writer{#endsyntax#} in any
way pulls in the vtable of {#syntax#}std.Io{#endsyntax#}. Some cases of
this could even result in unnecessary codegen, which can bloat binaries.

Now, {#syntax#}struct{#endsyntax#} (reminder that files are structs),
{#syntax#}union{#endsyntax#}, {#syntax#}enum{#endsyntax#}, and
{#syntax#}opaque{#endsyntax#} are only resolved when its size or the
type of one of its fields is required. This means that not only can you
use types as namespaces without referencing them, but you can even use
non-dereferenced pointers {#syntax#}\*T{#endsyntax#} without needing
{#syntax#}T{#endsyntax#} to be resolved.

This was changed as part of {#link\|Reworked Type Resolution#}.

{#header_close#} {#header_open\|Pointers to Comptime-Only Types Are No
Longer Comptime-Only#}

For instance, though {#syntax#}comptime_int{#endsyntax#} is a
comptime-only type, {#syntax#}\*comptime_int{#endsyntax#} is not, and
neither is {#syntax#}\[\]comptime_int{#endsyntax#}. This may seem
confusing at first---the easiest way to understand it is to consider
function pointers. The type {#syntax#}\*const fn () void{#endsyntax#} is
a runtime type. However, you are not allowed to *dereference* it at
runtime, because the element type (the function body type {#syntax#}fn
() void{#endsyntax#}) is comptime-only. So these pointers can *exist* at
runtime, but may only be *dereferenced* at compile-time. This makes them
more-or-less useless at runtime---but there\'s actually an exception to
that! Suppose you have a {#syntax#}\[\]const
std.builtin.Type.StructField{#endsyntax#}, and you want to pass the
{#syntax#}name{#endsyntax#} of each field to runtime code somehow.
Previously, you would have done this by constructing a separate
{#syntax#}\[\]const \[\]const u8{#endsyntax#}. However, now, you can
pass the {#syntax#}\[\]const std.builtin.Type.StructField{#endsyntax#}
directly to a runtime function. Naturally, this function cannot load a
{#syntax#}StructField{#endsyntax#} from this slice at runtime. However,
what it *can* do is load the {#syntax#}name{#endsyntax#} field, because
*it* has a runtime type!

This was changed as part of {#link\|Reworked Type Resolution#}.

{#header_close#} {#header_open\|Explicitly-Aligned Pointer Types Now
Distinct from Naturally-Aligned Pointer Types#}

Previously, {#syntax#}\*u8{#endsyntax#} and {#syntax#}\*align(1)
u8{#endsyntax#} were considered by Zig to be literally the same type;
they would compare equal, and {#syntax#}\*u8{#endsyntax#} was considered
the canonical spelling (it\'s what the compiler would print). Now, those
two types are no longer considered equivalent.

**Crucially, the two types can still be used interchangeably.** They
coerce to one another, even through pointers (what the compiler calls
\"in-memory coercions\"), and in almost every case there is no need to
care which one you have. You could think of this difference as being
like the difference between {#syntax#}u32{#endsyntax#} and
{#syntax#}c_uint{#endsyntax#}: technically they are different types, but
(assuming your target has 32-bit {#syntax#}int{#endsyntax#}) they act
identically for all intents and purposes, and it doesn\'t technically
matter which one you pick.

This was changed as part of {#link\|Reworked Type Resolution#}.

{#header_close#} {#header_open\|Simplified Dependency Loop Rules#}

There are new cases which are now dependency loops when they previously
were not.

However, it\'s now more obvious *why* a dependency loop exists due to
simplified type checking rules and enhanced compile errors. This also
reduces the difficulty of formally specifying the Zig language.

This was changed as part of {#link\|Reworked Type Resolution#}.

{#header_close#} {#header_open\|Zero-bit Tuple Fields No Longer
Implicitly comptime#}

Back in 0.14.0, a rule was unintentionally introduced that tuple fields
with zero-bit types are implicitly promoted to
{#syntax#}comptime{#endsyntax#} fields:

    {#syntax#}
    comptime {
        const S = struct { void };
        @compileLog(@typeInfo(S).@"struct".fields[0].is_comptime); // @as(bool, true)
    }
        {#endsyntax#}

Zig 0.16.0 reverts this change: the above tuple field is no longer
considered a {#syntax#}comptime{#endsyntax#} field. However, this does
\*not\* prevent the field value from always being comptime-known:

    {#syntax#}
    test "zero-bit tuple field is comptime-known" {
        const S = struct { u32, void };
        var runtime_known: S = undefined;
        runtime_known = .{ 123, {} };
        // Even though the tuple is runtime-known, the zero-bit field is comptime-known:
        comptime assert(runtime_known[1] == {});
    }
    const assert = @import("std").debug.assert;
        {#endsyntax#}

In other words, this change is almost entirely non-breaking. The only
case where it could affect old code is if you were directly relying on
{#syntax#}std.builtin.StructField.is_comptime{#endsyntax#} from
{#syntax#}@typeInfo{#endsyntax#}, or on the equivalence of tuples with
and without explicitly declared {#syntax#}comptime{#endsyntax#} fields:

    {#syntax#}
    //! These tests both passed in Zig 0.15.x, but fail in Zig 0.16.x.
    test "zero-bit tuple field is comptime" {
        const S = struct { void };
        try expect(@typeInfo(S).@"struct".fields[0].is_comptime);
    }
    test "comptime annotation on zero-bit field is irrelevant to type equivalence" {
        const A = struct { void };
        const B = struct { comptime void = {} };
        try expect(A == B);
    }
    const expect = @import("std").testing.expect;
        {#endsyntax#}

{#header_close#} {#header_close#} {#header_open\|Standard Library#}

Added:

-   Io.Dir.renamePreserve: rename operation without replacing the
    destination file
-   Io.net.Socket.createPair

Removed:

-   SegmentedList
-   meta.declList
-   Io.GenericWriter
-   Io.AnyWriter
-   Io.null_writer
-   Io.CountingReader
-   Thread.Mutex.Recursive

Error set changes:

-   {#syntax#}error.RenameAcrossMountPoints{#endsyntax#} ➡️
    {#syntax#}error.CrossDevice{#endsyntax#}
-   {#syntax#}error.NotSameFileSystem{#endsyntax#} ➡️
    {#syntax#}error.CrossDevice{#endsyntax#}
-   {#syntax#}error.SharingViolation{#endsyntax#} ➡️
    {#syntax#}error.FileBusy{#endsyntax#}
-   {#syntax#}error.EnvironmentVariableNotFound{#endsyntax#} ➡️
    {#syntax#}error.EnvironmentVariableMissing{#endsyntax#}
-   {#syntax#}std.Io.Dir.rename{#endsyntax#} returns
    {#syntax#}error.DirNotEmpty{#endsyntax#} rather than
    {#syntax#}error.PathAlreadyExists{#endsyntax#}

Uncategorized changes:

-   fmt: Formatter ➡️ Alt
-   fmt: format ➡️ std.Io.Writer.print
-   fmt: FormatOptions ➡️ Options
-   fmt: bufPrintZ ➡️ bufPrintSentinel
-   compress: lzma, lzma2, and xz updated to Io.Reader / Io.Writer
-   DynLib: removed Windows support. Now users must use
    {#syntax#}LoadLibraryExW{#endsyntax#} and
    {#syntax#}GetProcAddress{#endsyntax#} directly, which is probably
    what they were already doing anyway.
-   math.sign: return smallest integer type that fits possible values
-   Trigger automatic fetching of root certificates on Windows
-   tar.extract: sanitize path traversal
-   BitSet, EnumSet: replace initEmpty, initFull with decl literals

{#header_open\|I/O as an Interface#} ![Zero the
Ziguana](https://ziglang.org/img/Zero_14.svg){style="height: 14em; float: right"}

Starting with Zig 0.16.0, all input and output functionality requires
being passed an {#syntax#}Io{#endsyntax#} instance. Generally, anything
that potentially **blocks control flow** or **introduces
nondeterminism** is grounds for being owned by the I/O interface.

Along with the *interface*, this release comes with the following
*implementations*:

-   {#syntax#}Io.Threaded{#endsyntax#} - based on threads. With this
    implementation, I/O operations are straightforward. For example,
    {#link\|File System#} operations directly call read, write, open,
    close, etc. When updating code from Zig 0.15.x, using this
    implementation provides the equivalent behavior. **This
    implementation is feature-complete and well-tested**, including
    {#link\|Cancelation#}. This is the implementation currently chosen
    by {#link\|\"Juicy Main\"#}.
    -   {#syntax#}-fno-single-threaded{#endsyntax#} - supports
        task-level concurrency and cancelation.
    -   {#syntax#}-fsingle-threaded{#endsyntax#} - does not support
        task-level concurrency or cancelation.
-   {#syntax#}Io.Evented{#endsyntax#} - **work-in-progress,
    experimental**, serving to inform the evolution of the interface.
    This implementation is based on userspace stack switching with work
    stealing, also known as M:N threading, \"green threads\", or
    stackful coroutines.
    -   {#syntax#}Io.Uring{#endsyntax#} - although it was not the focus
        of this release cycle, there is already a proof-of-concept
        implementation based on Linux\'s excellent io_uring API. This
        backend has really nice properties but it\'s not finished yet.
        It\'s lacking {#link\|Networking#}, error handling, test
        coverage, and minimal task stack allocations.
    -   {#syntax#}Io.Kqueue{#endsyntax#} - proof-of-concept only, enough
        to fix [a common bug in other async
        runtimes](https://github.com/mitchellh/libxev/issues/125).
    -   {#syntax#}Io.Dispatch{#endsyntax#} - based on Grand Central
        Dispatch (macOS).
-   {#syntax#}Io.failing{#endsyntax#} - simulates a system supporting no
    operations.

Overview:

-   {#link\|Future#} - task-level abstraction based on functions. Allows
    introducing operational independence (**asynchrony**) among any set
    of function calls.
-   {#link\|Group#} - efficiently manages many independent tasks.
    Supports awaiting and {#link\|canceling\|Cancelation#} all tasks in
    the group together.
-   {#syntax#}Queue(T){#endsyntax#} - many producer, many consumer,
    thread-safe, runtime configurable buffer size. When buffer is empty,
    consumers suspend and are resumed by producers. When buffer is full,
    producers suspend and are resumed by consumers.
-   {#syntax#}Select{#endsyntax#} - executes tasks together, providing a
    mechanism to wait until one or more tasks complete. Similar to
    {#link\|Batch#} but operates at the higher level task abstraction
    layer rather than lower level {#syntax#}Operation{#endsyntax#}
    abstraction layer.
-   {#link\|Batch#} - lower level abstraction based on introducing
    independence among any set of **operations**.
-   {#syntax#}Clock{#endsyntax#}, {#syntax#}Duration{#endsyntax#},
    {#syntax#}Timestamp{#endsyntax#}, {#syntax#}Timeout{#endsyntax#} -
    type safety for units of measurement

Demo of making an HTTP request to a domain:

{#code\|http-get.zig#}

Thanks to the fact that networking is now taking advantage of the new
{#syntax#}std.Io{#endsyntax#} interface, this code has the following
properties:

-   It asynchronously sends out DNS queries to each configured
    nameserver.
-   As each response comes in, it immediately, asynchronously tries to
    TCP connect to the returned IP address.
-   Upon the first successful TCP connection, all other in-flight
    connection attempts are {#link\|canceled\|Cancelation#}, including
    DNS queries.
-   The code also works when compiled with
    {#syntax#}-fsingle-threaded{#endsyntax#} even though the operations
    happen sequentially.
-   {#link\|On Windows, this all happens without ws2_32.dll
    dependency.\|Windows Networking Without ws2_32.dll#}

{#syntax#}init: std.process.Init{#endsyntax#} is thanks to
{#link\|\"Juicy Main\"#}.

When upgrading code, if you find yourself without access to an
{#syntax#}Io{#endsyntax#} instance, you can get one like this:

    {#syntax#}var threaded: Io.Threaded = .init_single_threaded;
    const io = threaded.io();{#endsyntax#}

This works as long as you don\'t need task-level concurrency, however,
it is a non-ideal workaround - like reaching for
{#syntax#}std.heap.page_allocator{#endsyntax#} when you need an
{#syntax#}Allocator{#endsyntax#} and do not have one. Instead, it is
better to accept an {#syntax#}Io{#endsyntax#} parameter if you need one
(or store one on a context struct for convenience). Point is that the
application\'s {#syntax#}main{#endsyntax#} function should generally be
responsible for constructing the {#syntax#}Io{#endsyntax#} instance used
throughout.

When testing, it is recommended to use
{#syntax#}std.testing.io{#endsyntax#} (much like
{#syntax#}std.testing.allocator{#endsyntax#}).

{#header_open\|Future#}

Futures are a task-level abstraction based on functions.

{#syntax#}io.async{#endsyntax#} creates a
{#syntax#}Future(T){#endsyntax#} where {#syntax#}T{#endsyntax#} is the
return type of the callee. {#syntax#}async{#endsyntax#} expresses
**asynchrony**: that the function call is independent from other logic.
Creating such a task is therefore infallible and portable across limited
{#syntax#}Io{#endsyntax#} implementations including those which lack a
concurrency mechanism. It is legal for {#syntax#}Io{#endsyntax#}
implementations to implement {#syntax#}async{#endsyntax#} calls simply
by directly calling the function before returning.

{#syntax#}io.concurrent{#endsyntax#} is the same as
{#syntax#}io.async{#endsyntax#} except communicates that the operation
*must* be done concurrently for correctness. This necessarily requires
memory allocation because that is the nature of doing things
simultaneously. This function can therefore fail with
{#syntax#}error.ConcurrencyUnavailable{#endsyntax#}.

In both cases, a {#syntax#}Future(T){#endsyntax#} is created. This
struct has two methods:

-   {#syntax#}await{#endsyntax#} - logically blocks control flow until
    the task completes, returning the return value of the function.
-   {#syntax#}cancel{#endsyntax#} - equivalent to
    {#syntax#}await{#endsyntax#} except also requests the
    {#syntax#}Io{#endsyntax#} implementation to interrupt the operation
    and return {#syntax#}error.Canceled{#endsyntax#}. Most I/O
    operations now have {#syntax#}error.Canceled{#endsyntax#} in their
    error sets.

Use this pattern to avoid resource leaks and handle
{#link\|Cancelation#} gracefully:

    {#syntax#}var foo_future = io.async(foo, .{args});
    defer if (foo_future.cancel(io)) |resource| resource.deinit() else |_| {}

    var bar_future = io.async(bar, .{args});
    defer if (bar_future.cancel(io)) |resource| resource.deinit() else |_| {}

    const foo_result = try foo_future.await(io);
    const bar_result = try bar_future.await(io);{#endsyntax#}

If the {#syntax#}foo{#endsyntax#} or {#syntax#}bar{#endsyntax#} function
does not return a resource that must be freed, then the
{#syntax#}if{#endsyntax#} can be simplified to {#syntax#}\_ =
foo.cancel(io) catch {}{#endsyntax#}, and if the function returns
{#syntax#}void{#endsyntax#}, then the discard can also be removed. The
{#syntax#}cancel{#endsyntax#} is necessary however because it releases
the async task resource when errors (including
{#syntax#}error.Canceled{#endsyntax#}) are returned.

{#header_close#} {#header_open\|Group#}

Groups are appropriate when many tasks share the same lifetime. They
offer a O(1) overhead for spawning N tasks.

{#code\|group.zig#} {#header_close#} {#header_open\|Cancelation#}

Lo! Lest one learn a lone release lesson, let proclaim: \"cancelation\"
should seriously only be spelt thusly (single \"l\"). Let not evil,
godless liars lead afoul.

In the same vein as breaking out of a for loop early, once you start
doing multiple tasks concurrently, you start running into situations
where one task having completed, for example by failing, means that you
would like to interrupt other ongoing tasks since their results and/or
side-effects are already known not to matter - or perhaps even require
being reversed.

{#link\|Future#}, {#link\|Group#}, and {#link\|Batch#} APIs all support
requesting cancelation. When cancelation is requested, the request may
or may not be acknowledged. Acknowledged cancelation requests cause I/O
operations to return {#syntax#}error.Canceled{#endsyntax#}. Even
{#syntax#}Io.Threaded{#endsyntax#} supports cancelation by sending a
signal to a thread, causing blocking syscalls to return
{#syntax#}EINTR{#endsyntax#}, and responding to that error code by
checking for a cancelation request before retrying the syscall.

Only the logic that made the cancelation request can soundly ignore an
{#syntax#}error.Canceled{#endsyntax#}. Otherwise, there are three ways
to handle {#syntax#}error.Canceled{#endsyntax#}. In order of most
common:

1.  Propagate it.
2.  After receiving it, {#syntax#}io.recancel(){#endsyntax#} and then
    don\'t propagate it. This rearms the cancelation request, so that
    the next check will have a chance to detect and acknowledge the
    request.
3.  Make it unreachable with
    {#syntax#}io.swapCancelProtection(){#endsyntax#}.

In general, cancelation is equivalent to awaiting, aside from the
request to cancel. This means you can still receive the return value
from the task - which may in fact have completed successfully despite
the request. In this case, the side effects, such as resource
allocation, should be accounted for. Here is an example of opening a
file and then immediately canceling the task. Note that we must account
for the possibility that the file succeeds in being opened.

{#code\|cancel.zig#}

Typically, since both {#syntax#}await{#endsyntax#} and
{#syntax#}cancel{#endsyntax#} are idempotent, the most useful pattern is
to {#syntax#}defer{#endsyntax#} a cancelation after creating a task.
This ensures the resources, including the concurrent tasks, are
deallocated before returning from the function.

Generally, Zig programmers don\'t need to explicitly add code to support
cancelation, because {#syntax#}error.Canceled{#endsyntax#} is baked into
the error sets of all the cancelable I/O operations. However, one can
add additional cancelation points by calling
{#syntax#}io.checkCancel{#endsyntax#}. It is rarely necessary to call
this function. The primary use case is in long-running CPU-bound tasks
which may need to respond to cancelation before completing.

{#header_close#} {#header_open\|Batch#}

You can think of {#syntax#}Batch{#endsyntax#} as a low level concurrency
mechanism which provides concurrency at an
{#syntax#}Operation{#endsyntax#} layer, which is efficient and portable,
but more difficult to abstract around, particularly if you need to run
some logic in between operations.

Eventually most of the {#link\|File System#} and {#link\|Networking#}
functionality are expected to migrate to become based on
{#syntax#}Operation{#endsyntax#}, making them eligible to be used with
{#syntax#}Batch{#endsyntax#}, and eligible to be used with
{#syntax#}operateTimeout{#endsyntax#}, which provides a general way to
add a timeout to *any* I/O operation.

Currently the list is:

-   {#syntax#}FileReadStreaming{#endsyntax#}
-   {#syntax#}FileWriteStreaming{#endsyntax#}
-   {#syntax#}DeviceIoControl{#endsyntax#}
-   {#syntax#}NetReceive{#endsyntax#}

Meanwhile {#link\|Future#} is the equivalent but at a *function*
abstraction layer, which is flexible and ergonomic, but it allocates
task memory and {#syntax#}error.ConcurrencyUnavailable{#endsyntax#}
(when using {#syntax#}concurrent{#endsyntax#}), or unwanted blocking
operations (when using {#syntax#}async{#endsyntax#}), can occur in more
circumstances than the lower level Batch APIs.

So, generally, if you\'re trying to write optimal, reusable software,
{#syntax#}Batch{#endsyntax#} is the way to go if you simply need to do
several operations at once, otherwise, you can always use the
{#link\|Future#} APIs if that would essentially require you to reinvent
futures. Or you can start with {#link\|Future#} APIs and then optimize
by reworking some stuff to use {#syntax#}Batch{#endsyntax#} later if
reducing task overhead is desirable.

{#header_close#} {#header_open\|Sync Primitives#}

Sync APIs must be migrated to use the new {#syntax#}std.Io{#endsyntax#}
APIs so that the code being synchronized can integrate correctly with
the application\'s chosen I/O implementation. This will ensure, for
example, when using {#syntax#}std.Io.Threaded{#endsyntax#}, a contended
mutex lock will block the thread, while when using
{#syntax#}std.Io.Evented{#endsyntax#}, it will switch stacks.

These APIs also integrate properly with {#link\|Cancelation#}.

-   {#syntax#}std.Thread.ResetEvent{#endsyntax#} ➡️
    {#syntax#}std.Io.Event{#endsyntax#}
-   {#syntax#}std.Thread.WaitGroup{#endsyntax#} ➡️
    {#syntax#}std.Io.Group{#endsyntax#}
-   {#syntax#}std.Thread.Futex{#endsyntax#} ➡️
    {#syntax#}std.Io.Futex{#endsyntax#}
-   {#syntax#}std.Thread.Mutex{#endsyntax#} ➡️
    {#syntax#}std.Io.Mutex{#endsyntax#}
-   {#syntax#}std.Thread.Condition{#endsyntax#} ➡️
    {#syntax#}std.Io.Condition{#endsyntax#}
-   {#syntax#}std.Thread.Semaphore{#endsyntax#} ➡️
    {#syntax#}std.Io.Semaphore{#endsyntax#}
-   {#syntax#}std.Thread.RwLock{#endsyntax#} ➡️
    {#syntax#}std.Io.RwLock{#endsyntax#}
-   {#syntax#}std.once{#endsyntax#} removed; avoid global variables, or
    hand-roll the logic yourself

Notably, lock-free sync primitives do not require
{#syntax#}std.Io{#endsyntax#} integration.

{#header_close#} {#header_open\|Entropy#}

Upgrade guide:

{#syntax#}std.crypto.random.bytes{#endsyntax#}

    {#syntax#}
    var buffer: [123]u8 = undefined;
    std.crypto.random.bytes(&buffer);
        {#endsyntax#}

⬇️

    {#syntax#}
    var buffer: [123]u8 = undefined;
    io.random(&buffer);
        {#endsyntax#}

{#syntax#}std.crypto.random{#endsyntax#} (std.Random interface)

    {#syntax#}
    const rng = std.crypto.random;
        {#endsyntax#}

⬇️

    {#syntax#}
    const rng_impl: std.Random.IoSource = .{ .io = io };
    const rng = rng_impl.interface();
        {#endsyntax#}

{#syntax#}posix.getrandom{#endsyntax#}

    {#syntax#}
    var buffer: [64]u8 = undefined;
    posix.getrandom(&buffer);
        {#endsyntax#}

⬇️

    {#syntax#}
    var buffer: [64]u8 = undefined;
    io.random(&buffer);
        {#endsyntax#}

{#syntax#}std.Options.crypto_always_getrandom{#endsyntax#} and
{#syntax#}std.Options.crypto_fork_safety{#endsyntax#}

Rather than these being std wide options, they are two different
{#syntax#}std.Io{#endsyntax#} APIs:

    {#syntax#}
    /// Obtains entropy.
    ///
    /// The implementation *may* store RNG state in process memory and use it to
    /// fill `buffer`.
    ///
    /// The degree to which the entropy is cryptographically secure is determined
    /// by the `Io` implementation.
    ///
    /// Threadsafe.
    ///
    /// See also `randomSecure`.
    pub fn random(io: Io, buffer: []u8) void {
        return io.vtable.random(io.userdata, buffer);
    }

    pub const RandomSecureError = error{EntropyUnavailable} || Cancelable;

    /// Obtains cryptographically secure entropy from outside the process.
    ///
    /// Always makes a syscall, or otherwise avoids dependency on process memory,
    /// in order to obtain fresh randomness. Does not rely on stored RNG state.
    ///
    /// Does not have any fallback mechanisms; returns `error.EntropyUnavailable`
    /// if any problems occur.
    ///
    /// Threadsafe.
    ///
    /// See also `random`.
    pub fn randomSecure(io: Io, buffer: []u8) RandomSecureError!void {
        return io.vtable.randomSecure(io.userdata, buffer);
    }
        {#endsyntax#}

So if you want to keep CSPRNG state out of your process memory, call
{#syntax#}Io.randomSecure{#endsyntax#} rather than
{#syntax#}Io.random{#endsyntax#}.

{#header_close#} {#header_open\|Time#}

This release adds the ability to get clock resolution, which may fail.
This allows {#syntax#}error.Unexpected{#endsyntax#} and
{#syntax#}error.ClockUnsupported{#endsyntax#} to be removed from timeout
and clock reading error sets because they can be treated as having a
resolution of infinite, which is detectable by the user by separately
(beforehand) calling {#syntax#}Clock.resolution{#endsyntax#}.

Upgrade guide:

-   {#syntax#}std.time.Instant{#endsyntax#} ➡️
    {#syntax#}std.Io.Timestamp{#endsyntax#}
-   {#syntax#}std.time.Timer{#endsyntax#} ➡️
    {#syntax#}std.Io.Timestamp{#endsyntax#}
-   {#syntax#}std.time.timestamp{#endsyntax#} ➡️
    {#syntax#}std.Io.Timestamp.now{#endsyntax#}

{#header_close#} {#header_open\|File System#}

All {#syntax#}fs{#endsyntax#} APIs are migrated to
{#syntax#}Io{#endsyntax#}.

Although it\'s a lot of breaking changes, unlike
[\"writergate\"](https://ziglang.org/download/0.15.1/release-notes.html#Writergate),
this changeset is expected to be generally easy for Zig programmers to
manage, because it does not require much critical thinking. For example,
typical upgrade path will look something like this:

    {#syntax#}file.close();{#endsyntax#}

⬇️

    {#syntax#}file.close(io);{#endsyntax#}

Although your upgrade diff might be large, it will be quite simple to
understand what needs to be done.

Added:

-   {#syntax#}Io.Dir.hardLink{#endsyntax#}
-   {#syntax#}Io.Dir.Reader{#endsyntax#}
-   {#syntax#}Io.Dir.setFilePermissions{#endsyntax#}
-   {#syntax#}Io.Dir.setFileOwner{#endsyntax#}
-   {#syntax#}Io.File.NLink{#endsyntax#}

Removed with no replacement:

-   {#syntax#}fs.realpathZ{#endsyntax#}
-   {#syntax#}fs.realpathW{#endsyntax#}
-   {#syntax#}fs.realpathW2{#endsyntax#}
-   {#syntax#}fs.makeDirAbsoluteZ{#endsyntax#}
-   {#syntax#}fs.deleteDirAbsoluteZ{#endsyntax#}
-   {#syntax#}fs.openDirAbsoluteZ{#endsyntax#}
-   {#syntax#}fs.renameAbsoluteZ{#endsyntax#}
-   {#syntax#}fs.renameZ{#endsyntax#}
-   {#syntax#}fs.deleteTreeAbsolute{#endsyntax#}
-   {#syntax#}fs.symLinkAbsoluteW{#endsyntax#}
-   {#syntax#}fs.Dir.realpathZ{#endsyntax#}
-   {#syntax#}fs.Dir.realpathW{#endsyntax#}
-   {#syntax#}fs.Dir.realpathW2{#endsyntax#}
-   {#syntax#}fs.Dir.deleteFileZ{#endsyntax#}
-   {#syntax#}fs.Dir.deleteFileW{#endsyntax#}
-   {#syntax#}fs.Dir.deleteDirZ{#endsyntax#}
-   {#syntax#}fs.Dir.deleteDirW{#endsyntax#}
-   {#syntax#}fs.Dir.renameZ{#endsyntax#}
-   {#syntax#}fs.Dir.renameW{#endsyntax#}
-   {#syntax#}fs.Dir.symLinkWasi{#endsyntax#}
-   {#syntax#}fs.Dir.symLinkZ{#endsyntax#}
-   {#syntax#}fs.Dir.symLinkW{#endsyntax#}
-   {#syntax#}fs.Dir.readLinkWasi{#endsyntax#}
-   {#syntax#}fs.Dir.readLinkZ{#endsyntax#}
-   {#syntax#}fs.Dir.readLinkW{#endsyntax#}
-   {#syntax#}fs.Dir.adaptToNewApi{#endsyntax#}
-   {#syntax#}fs.Dir.adaptFromNewApi{#endsyntax#}
-   {#syntax#}fs.File.isCygwinPty{#endsyntax#}
-   {#syntax#}fs.File.adaptToNewApi{#endsyntax#}
-   {#syntax#}fs.File.adaptFromNewApi{#endsyntax#}

Changed:

-   {#syntax#}fs.copyFileAbsolute{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.copyFileAbsolute{#endsyntax#}
-   {#syntax#}fs.makeDirAbsolute{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.createDirAbsolute{#endsyntax#}
-   {#syntax#}fs.deleteDirAbsolute{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.deleteDirAbsolute{#endsyntax#}
-   {#syntax#}fs.openDirAbsolute{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.openDirAbsolute{#endsyntax#}
-   {#syntax#}fs.openFileAbsolute{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.openFileAbsolute{#endsyntax#}
-   {#syntax#}fs.accessAbsolute{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.accessAbsolute{#endsyntax#}
-   {#syntax#}fs.createFileAbsolute{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.createFileAbsolute{#endsyntax#}
-   {#syntax#}fs.deleteFileAbsolute{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.deleteFileAbsolute{#endsyntax#}
-   {#syntax#}fs.renameAbsolute{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.renameAbsolute{#endsyntax#}
-   {#syntax#}fs.readLinkAbsolute{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.readLinkAbsolute{#endsyntax#}
-   {#syntax#}fs.symLinkAbsolute{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.symLinkAbsolute{#endsyntax#}

```{=html}
<!-- -->
```
-   {#syntax#}fs.has_executable_bit{#endsyntax#} ➡️
    {#syntax#}std.Io.File.Permissions.has_executable_bit{#endsyntax#}
-   {#syntax#}fs.realpath{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.realPathFileAbsolute{#endsyntax#}
-   {#syntax#}fs.rename{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.rename{#endsyntax#}
-   {#syntax#}fs.cwd{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.cwd{#endsyntax#}
-   {#syntax#}fs.defaultWasiCwd{#endsyntax#} ➡️
    {#syntax#}std.os.defaultWasiCwd{#endsyntax#}
-   {#syntax#}fs.realpathAlloc{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.realPathFileAbsoluteAlloc{#endsyntax#}

```{=html}
<!-- -->
```
-   {#syntax#}fs.openSelfExe{#endsyntax#} ➡️
    {#syntax#}std.process.openExecutable{#endsyntax#}
-   {#syntax#}fs.selfExePathAlloc{#endsyntax#} ➡️
    {#syntax#}std.process.executablePathAlloc{#endsyntax#}
-   {#syntax#}fs.selfExePath{#endsyntax#} ➡️
    {#syntax#}std.process.executablePath{#endsyntax#}
-   {#syntax#}fs.selfExeDirPath{#endsyntax#} ➡️
    {#syntax#}std.process.executableDirPath{#endsyntax#}
-   {#syntax#}fs.selfExeDirPathAlloc{#endsyntax#} ➡️
    {#syntax#}std.process.executableDirPathAlloc{#endsyntax#}
-   {#syntax#}fs.Dir.setAsCwd{#endsyntax#} ➡️
    {#syntax#}std.process.setCurrentDir{#endsyntax#}

```{=html}
<!-- -->
```
-   {#syntax#}fs.Dir.realpath{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.realPathFile{#endsyntax#}
-   {#syntax#}fs.Dir.realpathAlloc{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.realPathFileAlloc{#endsyntax#}

```{=html}
<!-- -->
```
-   {#syntax#}fs.Dir{#endsyntax#} ➡️ {#syntax#}std.Io.Dir{#endsyntax#}
-   {#syntax#}fs.File{#endsyntax#} ➡️ {#syntax#}std.Io.File{#endsyntax#}

```{=html}
<!-- -->
```
-   {#syntax#}fs.Dir.makeDir{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.createDir{#endsyntax#}
-   {#syntax#}fs.Dir.makePath{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.createDirPath{#endsyntax#}
-   {#syntax#}fs.Dir.makeOpenDir{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.createDirPathOpen{#endsyntax#}

```{=html}
<!-- -->
```
-   {#syntax#}fs.Dir.rename{#endsyntax#}: now accepts two
    {#syntax#}Dir{#endsyntax#}parameters (plus
    {#syntax#}Io{#endsyntax#})
-   {#syntax#}fs.Dir.atomicSymLink{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.symLinkAtomic{#endsyntax#}
-   {#syntax#}fs.Dir.chmod{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.setPermissions{#endsyntax#}
-   {#syntax#}fs.Dir.chown{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.setOwner{#endsyntax#}

```{=html}
<!-- -->
```
-   {#syntax#}fs.File.Mode{#endsyntax#} ➡️
    {#syntax#}std.Io.File.Permissions{#endsyntax#}
-   {#syntax#}fs.File.PermissionsWindows{#endsyntax#} ➡️
    {#syntax#}std.Io.File.Permissions{#endsyntax#}
-   {#syntax#}fs.File.PermissionsUnix{#endsyntax#} ➡️
    {#syntax#}std.Io.File.Permissions{#endsyntax#}
-   {#syntax#}fs.File.default_mode{#endsyntax#} ➡️
    {#syntax#}std.Io.File.Permissions.default_file{#endsyntax#}
-   {#syntax#}fs.File.getOrEnableAnsiEscapeSupport{#endsyntax#} ➡️
    {#syntax#}std.Io.File.enableAnsiEscapeCodes{#endsyntax#}
-   {#syntax#}fs.File.setEndPos{#endsyntax#} ➡️
    {#syntax#}std.Io.File.setLength{#endsyntax#}
-   {#syntax#}fs.File.getEndPos{#endsyntax#} ➡️
    {#syntax#}std.Io.File.length{#endsyntax#}
-   {#syntax#}fs.File.seekTo{#endsyntax#},
    {#syntax#}std.fs.File.seekBy{#endsyntax#},
    {#syntax#}std.fs.File.seekFromEnd{#endsyntax#} ➡️
    {#syntax#}std.Io.File.Reader.seekTo{#endsyntax#},
    {#syntax#}std.Io.File.Reader.seekBy{#endsyntax#},
    {#syntax#}std.Io.File.Writer.seekTo{#endsyntax#}
-   {#syntax#}fs.File.getPos{#endsyntax#} ➡️
    {#syntax#}std.Io.File.Reader.logicalPos{#endsyntax#},
    {#syntax#}std.Io.Writer.logicalPos{#endsyntax#}
-   {#syntax#}fs.File.mode{#endsyntax#} ➡️
    {#syntax#}std.Io.File.stat().permissions.toMode{#endsyntax#}
-   {#syntax#}fs.File.chmod{#endsyntax#} ➡️
    {#syntax#}std.Io.File.setPermissions{#endsyntax#}
-   {#syntax#}fs.File.chown{#endsyntax#} ➡️
    {#syntax#}std.Io.File.setOwner{#endsyntax#}
-   {#syntax#}fs.File.updateTimes{#endsyntax#} ➡️
    {#syntax#}std.Io.File.setTimestamps{#endsyntax#},
    {#syntax#}std.Io.File.setTimestampsNow{#endsyntax#}
-   {#syntax#}fs.File.read{#endsyntax#} ➡️
    {#syntax#}std.Io.File.readStreaming{#endsyntax#}
-   {#syntax#}fs.File.readv{#endsyntax#} ➡️
    {#syntax#}std.Io.File.readStreaming{#endsyntax#}
-   {#syntax#}fs.File.pread{#endsyntax#} ➡️
    {#syntax#}std.Io.File.readPositional{#endsyntax#}
-   {#syntax#}fs.File.preadv{#endsyntax#} ➡️
    {#syntax#}std.Io.File.readPositional{#endsyntax#}
-   {#syntax#}fs.File.preadAll{#endsyntax#} ➡️
    {#syntax#}std.Io.File.readPositionalAll{#endsyntax#}
-   {#syntax#}fs.File.write{#endsyntax#} ➡️
    {#syntax#}std.Io.File.writeStreaming{#endsyntax#}
-   {#syntax#}fs.File.writev{#endsyntax#} ➡️
    {#syntax#}std.Io.File.writeStreaming{#endsyntax#}
-   {#syntax#}fs.File.pwrite{#endsyntax#} ➡️
    {#syntax#}std.Io.File.writePositional{#endsyntax#}
-   {#syntax#}fs.File.pwritev{#endsyntax#} ➡️
    {#syntax#}std.Io.File.writePositional{#endsyntax#}
-   {#syntax#}fs.File.writeAll{#endsyntax#} ➡️
    {#syntax#}std.Io.File.writeStreamingAll{#endsyntax#}
-   {#syntax#}fs.File.pwriteAll{#endsyntax#} ➡️
    {#syntax#}std.Io.File.writePositionalAll{#endsyntax#}
-   {#syntax#}fs.File.copyRange{#endsyntax#},
    {#syntax#}std.fs.File.copyRangeAll{#endsyntax#} ➡️
    {#syntax#}std.Io.File.writer{#endsyntax#}

Many functions now have an {#syntax#}Io{#endsyntax#} parameter.

Deprecated:

-   {#syntax#}fs.path{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.path{#endsyntax#}
-   {#syntax#}fs.max_path_bytes{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.max_path_bytes{#endsyntax#}
-   {#syntax#}fs.max_name_bytes{#endsyntax#} ➡️
    {#syntax#}std.Io.Dir.max_name_bytes{#endsyntax#}

{#header_close#} {#header_open\|Networking#}

All {#syntax#}net{#endsyntax#} APIs are migrated to
{#syntax#}Io{#endsyntax#}.

[Io.Evented does not yet implement
networking.](https://codeberg.org/ziglang/zig/issues/31723)

[Io.net currently lacks a way to do non-IP
networking.](https://codeberg.org/ziglang/zig/issues/30892)

{#header_close#} {#header_open\|Process#}

Spawning a child process:

    {#syntax#}var child = std.process.Child.init(argv, gpa);
        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        try child.spawn(io);{#endsyntax#}

⬇️

    {#syntax#}var child = try std.process.spawn(io, .{
            .argv = argv,
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .pipe,
        });{#endsyntax#}

Running a child process and capturing its output:

    {#syntax#}const result = std.process.Child.run(allocator, io, .{ {#endsyntax#}

⬇️

    {#syntax#}const result = std.process.run(allocator, io, .{ {#endsyntax#}

Replacing current process image:

    {#syntax#}const err = std.process.execv(arena, argv);{#endsyntax#}

⬇️

    {#syntax#}const err = std.process.replace(io, .{ .argv = argv });{#endsyntax#}

{#header_close#} {#header_open\|File.MemoryMap#}

The pointer contents are defined to only be synchronized after explicit
sync points, making it legal to have a fallback implementation based on
file operations while still supporting a handful of use cases for memory
mapping.

Furthermore, it makes it legal for evented I/O implementations to use
evented file I/O for the sync points rather than memory mapping.

Technically this is a breaking change because the positional file
reading and writing error sets are more constrained. Also on WASI, you
now get {#syntax#}error.IsDir{#endsyntax#} correctly instead of
{#syntax#}error.NotOpenForReading{#endsyntax#}.

{#header_close#} {#header_open\|posix and os.windows removals#}

Most {#syntax#}std.posix{#endsyntax#} and
{#syntax#}std.os.windows{#endsyntax#} functions existed at an awkward
**medium-level abstraction** and have thus been removed. Therefore, if
you were using any functions removed from those namespaces, you must now
choose a direction:

-   Go higher: use {#syntax#}std.Io{#endsyntax#}
-   Go lower: use {#syntax#}std.posix.system{#endsyntax#} directly

[More removals are
planned](https://codeberg.org/ziglang/zig/issues/31694).

{#header_close#} {#header_close#} {#header_open\|heap.ArenaAllocator
Becomes Thread-Safe and Lock-Free#}

Lock-free and thread-safe plays better with {#link\|std.Io
integration\|I/O as an Interface#} and libc integration. By avoiding
locks, we avoid needing {#link\|Sync Primitives#} and thereby avoid
needing an {#syntax#}Io{#endsyntax#} instance, and also allow the
{#syntax#}Allocator{#endsyntax#} to be used as the backing allocator for
an {#syntax#}Io{#endsyntax#} instance.

The new implementation offers comparable performance to the previous one
when only being accessed by a single thread and a slight speedup
compared to the previous implementation wrapped into a
ThreadSafeAllocator up to \~7 threads performing operations on it
concurrently.

[more details](https://codeberg.org/ziglang/zig/pulls/31320)

[same thing is planned for
heap.DebugAllocator](https://codeberg.org/ziglang/zig/issues/31186)

{#header_close#} {#header_open\|heap.ThreadSafe Allocator Removed#}

The only reasonable way to implement
{#syntax#}ThreadSafeAllocator{#endsyntax#}, which wraps an underlying
{#syntax#}Allocator{#endsyntax#}, is with a mutex, which necessarily
requires an Io instance and is generally inefficient. Meanwhile,
essentially every {#syntax#}Allocator{#endsyntax#} in which thread
safety is desired, can be adjusted to be lock free and avoid slow,
blocking mutexes altogether - or at least in some of the hot paths!
{#syntax#}ThreadSafeAllocator{#endsyntax#} is an anti-pattern. This is a
situation when tighter coupling is called for.

{#header_close#} {#header_open\|Add Deflate Compression, Simplify
Decompression#}

Adds deflate compression, implemented from scratch. A history window is
kept in the writer\'s buffer for matching and a chained hash table is
used to find matches. Tokens are accumulated until a threshold is
reached and then outputted as a block.

Additionally, two other deflate writers are provided:

-   {#syntax#}Raw{#endsyntax#} writes only in store blocks (the
    uncompressed bytes). It utilizes data vectors to efficiently send
    block headers and data.
-   {#syntax#}Huffman{#endsyntax#} only performs Huffman compression on
    data and no matching.

The above are also able to take advantage of writer semantics since they
do not need to keep a history.

Literal and distance code parameters in {#syntax#}token{#endsyntax#}
have also been reworked. Their parameters are now derived
mathematically, however the more expensive ones are still obtained
through a lookup table (except on ReleaseSmall).

Decompression bit reading has been greatly simplified, taking advantage
of the ability to peek on the underlying reader. Additionally, a few
bugs with limit handling have been fixed.

{#header_open\|Zlib Comparison#}

zlib achieves a 1.00% better compression ratio at the default
compression level and 0.77% better at the best compression level. It
seems that zlib selects slightly different matches, however the total
matched bytes is less. In the future, it would be nice to figure this
out and be on par with zlib.

Here is a benchmark of the performance versus zlib using the equivalent
parameters (i.e. levels).

With default compression level:

    Benchmark 1 (20 runs): sh -c ./zpipe<sample
      measurement          mean ± σ            min … max           outliers         delta
      wall_time           252ms ± 1.07ms     250ms …  255ms          1 ( 5%)        0%
      peak_rss           5.46MB ± 97.4KB    5.32MB … 5.64MB          0 ( 0%)        0%
      cpu_cycles         1.19G  ± 4.44M     1.19G  … 1.21G           2 (10%)        0%
      instructions       1.83G  ±  665      1.83G  … 1.83G           3 (15%)        0%
      cache_references    117M  ±  904K      116M  …  120M           1 ( 5%)        0%
      cache_misses       1.66M  ±  931K      942K  … 5.00M           1 ( 5%)        0%
      branch_misses      13.6M  ± 9.84K     13.6M  … 13.7M           1 ( 5%)        0%
    Benchmark 2 (22 runs): sh -c ./std-deflate<sample
      measurement          mean ± σ            min … max           outliers         delta
      wall_time           228ms ±  841us     226ms …  229ms          0 ( 0%)        ⚡-  9.7% ±  0.2%
      peak_rss           5.45MB ±  116KB    5.24MB … 5.61MB          0 ( 0%)          -  0.2% ±  1.2%
      cpu_cycles         1.07G  ± 1.33M     1.07G  … 1.08G           1 ( 5%)        ⚡-  9.8% ±  0.2%
      instructions       2.18G  ±  825      2.18G  … 2.18G           0 ( 0%)        💩+ 18.9% ±  0.0%
      cache_references   95.0M  ±  435K     94.1M  … 96.1M           1 ( 5%)        ⚡- 18.7% ±  0.4%
      cache_misses        874K  ±  326K      499K  … 1.94M           1 ( 5%)        ⚡- 47.3% ± 25.7%
      branch_misses      6.30M  ± 18.3K     6.24M  … 6.32M           2 ( 9%)        ⚡- 53.7% ±  0.1%

With best compression level:

    Benchmark 1 (7 runs): sh -c ./zpipe<sample
      measurement          mean ± σ            min … max           outliers         delta
      wall_time           803ms ± 5.75ms     798ms …  815ms          0 ( 0%)        0%
      peak_rss           5.48MB ±  120KB    5.24MB … 5.61MB          0 ( 0%)        0%
      cpu_cycles         3.85G  ± 30.5M     3.83G  … 3.92G           0 ( 0%)        0%
      instructions       5.32G  ± 1.11K     5.32G  … 5.32G           0 ( 0%)        0%
      cache_references    414M  ± 1.47M      412M  …  416M           0 ( 0%)        0%
      cache_misses       7.91M  ± 1.12M     6.15M  … 9.30M           0 ( 0%)        0%
      branch_misses      28.6M  ± 15.2K     28.6M  … 28.7M           0 ( 0%)        0%
    Benchmark 2 (7 runs): sh -c ./std-deflate<sample
      measurement          mean ± σ            min … max           outliers         delta
      wall_time           797ms ± 1.19ms     795ms …  798ms          0 ( 0%)          -  0.8% ±  0.6%
      peak_rss           5.50MB ± 82.3KB    5.35MB … 5.60MB          0 ( 0%)          +  0.3% ±  2.2%
      cpu_cycles         3.82G  ± 2.11M     3.82G  … 3.82G           0 ( 0%)          -  0.7% ±  0.7%
      instructions       8.19G  ±  508      8.19G  … 8.19G           0 ( 0%)        💩+ 54.1% ±  0.0%
      cache_references    345M  ± 1.02M      344M  …  346M           0 ( 0%)        ⚡- 16.8% ±  0.4%
      cache_misses       4.63M  ±  393K     4.20M  … 5.44M           0 ( 0%)        ⚡- 41.5% ± 12.4%
      branch_misses      6.98M  ± 41.8K     6.93M  … 7.02M           0 ( 0%)        ⚡- 75.6% ±  0.1%

Benchmark for decompression vs before:

    Benchmark 1 (113 runs): sh -c ./std-inflate-old<sample.gz
      measurement          mean ± σ            min … max           outliers         delta
      wall_time          44.1ms ±  474us    43.3ms … 46.0ms         12 (11%)        0%
      peak_rss           5.48MB ±  112KB    5.23MB … 5.70MB          0 ( 0%)        0%
      cpu_cycles          194M  ±  487K      193M  …  197M           5 ( 4%)        0%
      instructions        459M  ±  524       459M  …  459M           7 ( 6%)        0%
      cache_references   1.90M  ± 46.2K     1.80M  … 2.18M           7 ( 6%)        0%
      cache_misses       38.1K  ± 3.95K     33.8K  … 65.1K           7 ( 6%)        0%
      branch_misses      3.16M  ± 3.87K     3.15M  … 3.18M           4 ( 4%)        0%
    Benchmark 2 (126 runs): sh -c ./std-inflate-new<sample.gz
      measurement          mean ± σ            min … max           outliers         delta
      wall_time          39.9ms ±  662us    38.2ms … 42.3ms          4 ( 3%)        ⚡-  9.5% ±  0.3%
      peak_rss           5.47MB ±  104KB    5.18MB … 5.65MB          0 ( 0%)          -  0.1% ±  0.5%
      cpu_cycles          173M  ±  241K      173M  …  175M           4 ( 3%)        ⚡- 10.6% ±  0.0%
      instructions        410M  ±  321       410M  …  410M           2 ( 2%)        ⚡- 10.7% ±  0.0%
      cache_references   1.84M  ± 38.7K     1.71M  … 2.09M           3 ( 2%)        ⚡-  2.9% ±  0.6%
      cache_misses       36.2K  ± 1.61K     33.1K  … 40.8K           1 ( 1%)        ⚡-  4.9% ±  2.0%
      branch_misses      2.58M  ± 3.36K     2.58M  … 2.59M           0 ( 0%)        ⚡- 18.3% ±  0.0%

\[[source](https://github.com/ziglang/zig/pull/25301#issue-3436311980)\]
{#header_close#} {#header_close#} {#header_open\|Expanded target support
for segfault handling/unwinding#}

On every target that sees real use with Zig (and probably even a few
that don\'t), we now have working stack traces on crashes and when using
DebugAllocator.

Additionally, inline callers are now resolved from debug info when
printing stack traces on Windows. If the debug info is
[ambiguous](https://github.com/llvm/llvm-project/issues/191787), all
candidate callers are printed. [Support for resolving inline traces from
DWARF is planned](https://github.com/ziglang/zig/issues/19407). Windows
was prioritized as PDB initially associates return addresses with the
outermost inline caller leading to a particularly poor debugging
experience if the other callers aren\'t resolved. Error return traces
now include inline callers on all platforms.

This is part of a larger effort to improve the use case of making video
games in Zig.

{#header_close#} {#header_open\|Removal of ucontext_t and related
types/functions#}

This type was useful for two things:

-   Doing non-local control flow with {#syntax#}ucontext.h{#endsyntax#}
    functions.
-   Inspecting machine state in a signal handler.

The first use case is not one we support; we no longer expose bindings
to those functions in the standard library. They\'re also deprecated in
POSIX and, as a result, not available in musl.

The second use case is valid, but is very poorly served by the standard
library. As evidenced by changes to
{#syntax#}std.debug.cpu_context.signal_context_t{#endsyntax#} in this
release, users will be better served rolling their own
{#syntax#}ucontext_t{#endsyntax#} and especially
{#syntax#}mcontext_t{#endsyntax#} types which fit their specific
situation. Further, these types tend to evolve frequently as
architectures evolve, and the standard library has not done a good job
keeping up, or even providing them for all supported targets.

{#header_close#} {#header_open\|Debug Information Reworked#} ![Zero the
Ziguana](https://ziglang.org/img/Zero_8.svg){style="height: 13em; float: right"}

Zig 0.16.0 reworks many standard library APIs related to debug
information, and in particular stack traces. The motivation behind the
changes was allowing fast stack tracing (without needing to [check every
stack frame for invalid memory
addresses](https://github.com/ziglang/zig/pull/24960)) without
introducing potential crashes in cases where frame pointers are
unavailable (such as a libc compiled with `-fomit-frame-pointer`).

This is a surprisingly complex problem. Solving it requires \"unwind
information\", which is encoded in different ways on different targets.
The Zig standard library already supported using unwind information, but
this support was buggy and incomplete, and often suffered from poor
performance. In Zig 0.16.0, the Zig standard library will always use
\"safe\" stack unwinding by default if it is available, and the
performance impact (compared with naive \"frame pointer\" unwinding) is
usually acceptable.

The interface for printing a
{#syntax#}std.builtin.StackTrace{#endsyntax#} is
{#syntax#}std.debug.writeStackTrace{#endsyntax#}:

    {#syntax#}
    /// Write a previously captured stack trace to `t`, annotated with source locations.
    pub fn writeStackTrace(st: *const StackTrace, t: Io.Terminal) Writer.Error!void { ... }
        {#endsyntax#}

For debugging purposes, there is also
{#syntax#}std.debug.dumpStackTrace{#endsyntax#}, which writes to stderr
rather than accepting a {#syntax#}std.Io.Terminal{#endsyntax#}.

To capture the current call stack into a
{#syntax#}std.builtin.StackTrace{#endsyntax#} value, use
{#syntax#}std.debug.captureCurrentStackTrace{#endsyntax#}, which also
accepts some options to control the stack trace collection behavior:

    {#syntax#}
    pub const StackUnwindOptions = struct {
        /// If not `null`, we will ignore all frames up until this return address. This is typically
        /// used to omit intermediate handling code (for instance, a panic handler and its machinery)
        /// from stack traces.
        first_address: ?usize = null,
        /// If not `null`, we will unwind from this `cpu_context.Native` instead of the current top of
        /// the stack. The main use case here is printing stack traces from signal handlers, where the
        /// kernel provides a `*const cpu_context.Native` of the state before the signal.
        context: ?CpuContextPtr = null,
        /// If `true`, stack unwinding strategies which may cause crashes are used as a last resort.
        /// If `false`, only known-safe mechanisms will be attempted.
        allow_unsafe_unwind: bool = false,
    };

    /// Capture and return the current stack trace. The returned `StackTrace` stores its addresses in
    /// the given buffer, so `addr_buf` must have a lifetime at least equal to the `StackTrace`.
    ///
    /// See `writeCurrentStackTrace` to immediately print the trace instead of capturing it.
    pub noinline fn captureCurrentStackTrace(options: StackUnwindOptions, addr_buf: []usize) StackTrace { ... }
    {#endsyntax#}

Lastly, to print the *current* stack trace, there are analogues to
{#syntax#}writeStackTrace{#endsyntax#} and
{#syntax#}dumpStackTrace{#endsyntax#}:

    {#syntax#}
    /// Write the current stack trace to `t`, annotated with source locations.
    ///
    /// See `captureCurrentStackTrace` to capture the trace addresses into a buffer instead of printing.
    pub noinline fn writeCurrentStackTrace(options: StackUnwindOptions, t: Io.Terminal) Writer.Error!void { ... }
    /// A thin wrapper around `writeCurrentStackTrace` which writes to stderr and ignores write errors.
    pub fn dumpCurrentStackTrace(options: StackUnwindOptions) void { ... }
    {#endsyntax#}

Most of these function already existed in previous versions of Zig
(albeit with different signatures), but there were also several more in
the past which have now been consolidated into the above functions.
Here\'s the API you want if using one of the removed functions:

-   {#syntax#}captureStackTrace{#endsyntax#} ➡️
    {#syntax#}captureCurrentStackTrace{#endsyntax#}
-   {#syntax#}dumpStackTraceFromBase{#endsyntax#} ➡️
    {#syntax#}dumpCurrentStackTrace{#endsyntax#}
-   {#syntax#}walkStackWindows{#endsyntax#} ➡️
    {#syntax#}captureCurrentStackTrace{#endsyntax#}
-   {#syntax#}writeStackTraceWindows{#endsyntax#} ➡️
    {#syntax#}writeCurrentStackTrace{#endsyntax#}

{#syntax#}std.debug.StackIterator{#endsyntax#} is now considered an
internal API and is no longer {#syntax#}pub{#endsyntax#}. If you were
previously using it, consider whether
{#syntax#}captureCurrentStackTrace{#endsyntax#} is suitable for your
needs. If for some reason it is not, take a look at the API exposed by
{#syntax#}std.debug.SelfInfo{#endsyntax#}, which is the standard
library\'s abstraction over the platform\'s debug information.

The {#syntax#}std.debug.SelfInfo{#endsyntax#} implementation can be
overridden by exposing
{#syntax#}@import(\"root\").debug.SelfInfo{#endsyntax#}. This allows
stack traces to be made functional on targets which the Zig Standard
Library does not support---even freestanding ones!

{#header_close#} {#header_open\|Inter-Process Progress Reporting for
Windows#}

{#syntax#}std.Progress{#endsyntax#} supports reporting information from
child processes on Windows now.

Maximum node length bumped from 40 to 120.

{#header_close#} {#header_open\|Windows Networking Without ws2_32.dll#}

All networking API on Windows now is implemented via direct AFD access.

This fixes a handful of bugs, makes {#link\|Cancelation#} and
{#link\|Batch#} work properly for networking operations, and avoids the
performance pitfalls that exist within ws2_32.dll\'s implementation of
networking, such as maintaining an entirely unnecessary hash table for
side data attached to socket handles that requires allocation and
synchronization, rather than simply passing socket mode and protocol to
the accept function.

{#header_close#} {#header_open\|Completed Migration to NtDll#}

On Windows, all standard library functionality is now implemented based
on calls to the lowest level stable syscall API. The remaining extern
functions in the standard library which make calls to Windows DLLs are:

    {#syntax#}
    extern "kernel32" fn CreateProcessW(
    extern "crypt32" fn CertOpenStore(
    extern "crypt32" fn CertCloseStore(
    extern "crypt32" fn CertEnumCertificatesInStore(
    extern "crypt32" fn CertFreeCertificateContext(
    extern "crypt32" fn CertAddEncodedCertificateToStore(
    extern "crypt32" fn CertOpenSystemStoreW(
    extern "crypt32" fn CertGetCertificateChain(
    extern "crypt32" fn CertFreeCertificateChain(
    extern "crypt32" fn CertVerifyCertificateChainPolicy(
        {#endsyntax#}

This avoids bugs, performance pitfalls, and missing functionality on
Windows, making Zig programs more robust, lean, and fast than other
programming languages that target this platform.

Notably the {#link\|Batch#} API and {#link\|Cancelation#} have full
Windows support with efficient implementations thanks to these efforts.

Users who wish to target older versions of Windows such as XP, or for
whatever reason would rather their applications use higher level DLLs
such as kernel32 are encouraged to collaborate on a third-party
{#link\|I/O implementation\|I/O as an Interface#} that eschews NtDll.

There are no plans to migrate away from using the above listed
functions.

{#header_close#} {#header_open\|\"Juicy Main\"#}

Starting in Zig 0.16.0, by adding a {#syntax#}process.Init{#endsyntax#}
parameter to {#syntax#}main{#endsyntax#}, one gains access to these
values:

    {#syntax#}/// A standard set of pre-initialized useful APIs for programs to take
    /// advantage of. This is the type of the first parameter of the main function.
    /// Applications wanting more flexibility can accept `Init.Minimal` instead.
    pub const Init = struct {
        /// `Init` is a superset of `Minimal`; the latter is included here.
        minimal: Minimal,
        /// Permanent storage for the entire process, cleaned automatically on
        /// exit. Threadsafe.
        arena: *std.heap.ArenaAllocator,
        /// A default-selected general purpose allocator for temporary heap
        /// allocations. Debug mode will set up leak checking if possible.
        /// Threadsafe.
        gpa: Allocator,
        /// An appropriate default Io implementation based on the target
        /// configuration. Debug mode will set up leak checking if possible.
        io: Io,
        /// Environment variables, initialized with `gpa`. Not threadsafe.
        environ_map: *Environ.Map,
        /// Named files that have been provided by the parent process. This is
        /// mainly useful on WASI, but can be used on other systems to mimic the
        /// behavior with respect to stdio.
        preopens: Preopens,

        /// Alternative to `Init` as the first parameter of the main function.
        pub const Minimal = struct {
            /// Environment variables.
            environ: Environ,
            /// Command line arguments.
            args: Args,
        };
    };{#endsyntax#}

Usage example:

{#code\|juice.zig#}

The first parameter of {#syntax#}pub fn main{#endsyntax#} may be one of
three things:

-   Missing. Empty main parameter list is still legal, however it now
    means you can\'t access CLI arguments or environment variables.
-   {#syntax#}process.Init.Minimal{#endsyntax#}. Only argv and environ
    available in raw form.
-   {#syntax#}process.Init{#endsyntax#}. Provides a bunch of
    pre-initialized goodies.

An additional enhancement is being considered to add CLI arg parsing as
a second parameter, however there are some competing ideas behind the
best way to do this.

{#header_close#} {#header_open\|Environment Variables and Process
Arguments Become Non-Global#}

The \"environment\" (a set of key-value string mappings inherited by
child processes) being global state, while a very common abstraction, is
problematic. In C, it is unsound to call environment-modifying functions
like {#syntax#}setenv{#endsyntax#} in a threaded context, because
{#syntax#}environ{#endsyntax#} can be (and often is) directly accessed
without any kind of lock. Additionally, the Zig standard library had [a
major footgun](https://github.com/ziglang/zig/issues/4524):
{#syntax#}std.os.environ{#endsyntax#} was meant to be equivalent to C\'s
{#syntax#}environ{#endsyntax#}, but it was impossible to populate it in
a library which does not link libc.

Now, **environment variables are available only in the application\'s
main function**. Therefore, functions which need access environment
variables should accept parameters for the needed values, or accept a
{#syntax#}\*const process.Environ.Map{#endsyntax#} parameter. An
instance of this environment variable map can be obtained conveniently
from {#link\|\"Juicy Main\"#}.

Accessing environment variables:

{#syntax_block\|zig\|example.zig#} const std = \@import(\"std\"); pub fn
main(init: std.process.Init) !void { for (init.environ_map.keys(),
init.environ_map.values()) \|key, value\| { std.log.info(\"env:
{s}={s}\", .{ key, value }); } } {#end_syntax_block#}

Accessing environment variables (minimal):

{#syntax_block\|zig\|example.zig#} const std = \@import(\"std\"); pub fn
main(init: std.process.Init.Minimal) !void { var arena_allocator:
std.heap.ArenaAllocator = .init(std.heap.page_allocator); defer
arena_allocator.deinit(); const arena = arena_allocator.allocator();
std.log.info(\"contains HOME: {any}\", .{init.environ.contains(arena,
\"HOME\")}); std.log.info(\"contains HOME (unempty): {any}\",
.{init.environ.containsUnempty(arena, \"HOME\")});
std.log.info(\"contains EDITOR: {any}\",
.{init.environ.containsConstant(\"EDITOR\")}); std.log.info(\"contains
EDITOR (unempty): {any}\",
.{init.environ.containsConstant(\"EDITOR\")}); std.log.info(\"HOME:
{?s}\", .{init.environ.getPosix(\"HOME\")}); std.log.info(\"EDITOR:
{s}\", .{try init.environ.getAlloc(arena, \"EDITOR\")}); const
environ_map = try init.environ.createMap(arena); for
(environ_map.keys(), environ_map.values()) \|key, value\| {
std.log.info(\"env: {s}={s}\", .{ key, value }); } }
{#end_syntax_block#}

Accessing CLI arguments ({#syntax#}iterate{#endsyntax#}):

{#syntax_block\|zig\|example.zig#} const std = \@import(\"std\"); pub fn
main(init: std.process.Init.Minimal) void { var args =
init.args.iterate(); while (args.next()) \|arg\| { std.log.info(\"arg:
{s}\", .{arg}); } } {#end_syntax_block#}

Accessing CLI arguments ({#syntax#}toSlice{#endsyntax#}):

{#syntax_block\|zig\|example.zig#} const std = \@import(\"std\"); pub fn
main(init: std.process.Init) !void { const args = try
init.minimal.args.toSlice(init.arena.allocator()); for (args) \|arg\| {
std.log.info(\"arg: {s}\", .{arg}); } } {#end_syntax_block#}
{#header_close#} {#header_open\|mem: introduce cut functions; rename
\"index of\" to \"find\"#}

1.  Introduce cut functions: {#syntax#}cut{#endsyntax#},
    {#syntax#}cutPrefix{#endsyntax#}, {#syntax#}cutSuffix{#endsyntax#},
    {#syntax#}cutScalar{#endsyntax#}, {#syntax#}cutLast{#endsyntax#},
    {#syntax#}cutLastScalar{#endsyntax#}
2.  Moving towards our function naming convention of having one word per
    concept and constructing function names out of concatenated
    concepts.

In {#syntax#}std.mem{#endsyntax#} the concepts are:

-   \"find\" - return index of substring
-   \"pos\" - starting index parameter
-   \"last\" - search from the end
-   \"linear\" - simple for loop rather than fancy algo
-   \"scalar\" - substring is a single element

{#header_close#} {#header_open\|Selectively Walking Directory Trees#}

{#syntax#}std.Io.Dir.walk{#endsyntax#} can be used to recursively walk a
directory tree, but it does not support skipping certain directories
along the way. To support that use case,
{#syntax#}std.Io.Dir.walkSelectively{#endsyntax#} has been added, which
requires opting-in to recursing into each directory entry encountered.
This design allows avoiding redundant open/close syscalls for
directories that are skipped.

Migration guide if you have a use case that benefits from selectively
walking:

    {#syntax#}
    var walker = try dir.walk(gpa);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        // ...
    }
        {#endsyntax#}

⬇️

    {#syntax#}
    var walker = try dir.walkSelectively(gpa);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        // some sort of filtering
        if (failsFilter(entry)) continue;
        if (entry.kind == .directory) {
            try walker.enter(io, entry);
        }
        // ...
    }
        {#endsyntax#}

Additionally, a {#syntax#}depth{#endsyntax#} function has been added to
{#syntax#}Walker.Entry{#endsyntax#}, and {#syntax#}leave{#endsyntax#}
functions have been added to both {#syntax#}Walker{#endsyntax#} and
{#syntax#}SelectiveWalker{#endsyntax#} to allow for bailing out of
iterating a particular directory part-way through.

{#header_close#} {#header_open\|fs.path Windows Paths#}

All functions in {#syntax#}std.fs.path{#endsyntax#} now handle Windows
paths more correctly and consistently, mostly with regards to UNC,
\"rooted\", and drive-relative path types. This involves behavior
changes in many functions, see
[#25993](https://github.com/ziglang/zig/pull/25993) for details.

API changes:

-   {#syntax#}windowsParsePath{#endsyntax#}/{#syntax#}diskDesignator{#endsyntax#}/{#syntax#}diskDesignatorWindows{#endsyntax#}
    ➡️ {#syntax#}parsePath{#endsyntax#},
    {#syntax#}parsePathWindows{#endsyntax#},
    {#syntax#}parsePathPosix{#endsyntax#}
-   Added {#syntax#}getWin32PathType{#endsyntax#}
-   {#syntax#}componentIterator{#endsyntax#}/{#syntax#}ComponentIterator.init{#endsyntax#}
    can no longer fail

{#header_close#} {#header_open\|fs.path.relative Became Pure#}

{#syntax#}relative{#endsyntax#}, {#syntax#}relativeWindows{#endsyntax#},
and {#syntax#}relativePosix{#endsyntax#} are now pure functions that
require passing the CWD path and (optionally) an environment map as
inputs instead of internally querying the OS for that information (the
environment map is needed to resolve certain path types on Windows).

Upgrade guide:

    {#syntax#}
    const relative = try std.fs.path.relative(gpa, from, to);
    defer gpa.free(relative);
        {#endsyntax#}

⬇️

    {#syntax#}
    const cwd_path = try std.process.currentPathAlloc(io, gpa);
    defer gpa.free(cwd_path);

    const relative = try std.fs.path.relative(gpa, cwd_path, environ_map, from, to);
    defer gpa.free(relative);
        {#endsyntax#}

{#header_close#} {#header_open\|File.Stat: Make Access Time Optional#}

Filesystems generally find this value problematic to keep updated since
it turns read-only file system accesses into file system mutations. Some
systems report stale values, and some systems explicitly refuse to
report this value. The latter case is now handled by
{#syntax#}null{#endsyntax#}.

ZFS has been observed to not report atime from statx.

Also take the opportunity to make setting timestamps API more flexible
and match the APIs widely available, which have
{#syntax#}UTIME_OMIT{#endsyntax#} and {#syntax#}UTIME_NOW{#endsyntax#}
constants that can be independently set for both fields.

This is needed to handle smoothly the case when atime is
{#syntax#}null{#endsyntax#}.

Upgrade guide:

    {#syntax#}
    try atomic_file.file_writer.file.setTimestamps(io, src_stat.atime, src_stat.mtime);
        {#endsyntax#}

⬇️

    {#syntax#}
    try atomic_file.file_writer.file.setTimestamps(io, .{
        .access_timestamp = .init(src_stat.atime),
        .modify_timestamp = .init(src_stat.mtime),
    });
        {#endsyntax#}

For accessing {#syntax#}Io.File.Stat.atime{#endsyntax#}:

    {#syntax#}
    stat.atime
        {#endsyntax#}

⬇️

    {#syntax#}
    stat.atime orelse return error.FileAccessTimeUnavailable
        {#endsyntax#}

{#header_close#} {#header_open\|\"Preopens\"#}

Upgrade guide:

    {#syntax#}
            const wasi_preopens: std.fs.wasi.Preopens = try .preopensAlloc(arena);
        {#endsyntax#}

⬇️

    {#syntax#}
            const preopens: std.process.Preopens = try .init(arena);
        {#endsyntax#}

Or simply get them from {#link\|\"Juicy Main\"#} via
{#syntax#}std.Process.Init.preopens{#endsyntax#}.

Data is {#syntax#}void{#endsyntax#} on non-WASI systems; you don\'t pay
for it if you don\'t use it. However, this API is future proof in case
other operating systems add equivalent functionality.

{#header_close#} {#header_open\|Atomic/Temporary Files#}

Main motivation for this change was to move the call to
{#syntax#}std.crypto.random{#endsyntax#} below the
{#syntax#}std.Io.VTable{#endsyntax#}. Specifically, the one in
{#syntax#}std.Io.File.Atomic.init{#endsyntax#}.

At the same time, I took the opportunity to integrate it with
{#syntax#}O_TMPFILE{#endsyntax#} on Linux. I\'d like to take the
opportunity to complain about this API. First of all, it\'s almost very
good. It gives the ability to create an ephemeral, unnamed file
descriptor, which one can operate on freely until ready to materialize
it onto the file system. If the process terminates before it gets around
to doing that, the OS garbage collects the file, rather than leaving
temporary, insecure trash around. Brilliant! Unfortunately, due to
multiple bugs and a debilitating design limitation, the API is nearly
useless.

First of all, {#syntax#}O_TMPFILE{#endsyntax#} is split across 2 bits on
some architectures, and missing from another. Wtf? That\'s not a real
problem though, moving on.

When using {#syntax#}O_TMPFILE{#endsyntax#}, how would you guess that
{#syntax#}openat(){#endsyntax#} indicates that the file system does not
support that operation? Perhaps with {#syntax#}ENOSYS{#endsyntax#}? Or
{#syntax#}OPNOTSUPP{#endsyntax#} perchance? The all-singing, all-dancing
{#syntax#}EINVAL{#endsyntax#}? Those would be two very reasonable
guesses, and an acceptable third, however, wrong!! It returns either
{#syntax#}EISDIR{#endsyntax#} or {#syntax#}ENOENT{#endsyntax#}. As a
reminder, this is {#syntax#}openat(){#endsyntax#} we\'re talking about,
so we very much need to know whether the path doesn\'t exist, or the
temp file mechanism doesn\'t work.

Next up we have a missing API. {#syntax#}linkat(){#endsyntax#} doesn\'t
support the {#syntax#}AT_REPLACE{#endsyntax#} flag even though there was
[a
patch](https://patchwork.kernel.org/project/linux-fsdevel/patch/c823982d5b46ea888dc1fdf26c067a7aa0f3585f.1490103963.git.osandov@fb.com/)
for it submitted nearly 10 years ago that was perfectly fine. Linus said
it was OK, and then it just never got merged. Without this flag,
{#syntax#}O_TMPFILE{#endsyntax#} cannot be used to atomically overwrite
an existing file. This means if you want to do that you have to create a
regular old non temp file with random numbers or something, and then use
{#syntax#}renameat(){#endsyntax#}.

So the only time that this {#syntax#}O_TMPFILE{#endsyntax#} trick
actually does any good is if you want hard link semantics, i.e. you want
{#syntax#}error.PathAlreadyExists{#endsyntax#} when the destination path
already exists. Think about it, if you deleted the file to make room,
then it wouldn\'t be atomic any more!

OK, rant over.

Anyway the upshot of this is, the moment any OS fixes their shitty APIs
with respect to temporary files, we can change
{#syntax#}std.Io.Threaded{#endsyntax#} accordingly, and all the Zig code
that uses {#syntax#}std.Io{#endsyntax#} can remain unchanged and gain
those benefits transparently.

Finally, this branch introduces
{#syntax#}std.Io.File.hardLink{#endsyntax#} API, which only works on
Linux, and is needed in order to materialize a
{#syntax#}O_TMPFILE{#endsyntax#} file descriptor without replacement
semantics.

Upgrade guide:

    {#syntax#}
    var buffer: [1024]u8 = undefined;
    var atomic_file = try dest_dir.atomicFile(io, dest_path, .{
        .permissions = actual_permissions,
        .write_buffer = &buffer,
    });
    defer atomic_file.deinit();

    // do something with atomic_file.file_writer;

    try atomic_file.flush();
    try atomic_file.renameIntoPlace();
        {#endsyntax#}

⬇️

    {#syntax#}
    var atomic_file = try dest_dir.createFileAtomic(io, dest_path, .{
        .permissions = actual_permissions,
        .make_path = true,
        .replace = true,
    });
    defer atomic_file.deinit(io);

    var buffer: [1024]u8 = undefined; // Used only when direct fd-to-fd is not available.
    var file_writer = atomic_file.file.writer(io, &buffer);

    // do something with file_writer

    try file_writer.flush();
    try atomic_file.replace(io); // or set .replace = false above and call link() instead
        {#endsyntax#}

{#header_close#} {#header_open\|Memory Locking and Protection API Moved
to process#}

mmap and mprotect flags now have type safety:

    {#syntax#}
    std.posix.PROT.READ | std.posix.PROT.WRITE,
        {#endsyntax#}

⬇️

    {#syntax#}
    .{ .READ = true, .WRITE = true },
        {#endsyntax#}

mlock, mlock2, mlockall:

    {#syntax#}
    try std.posix.mlock();
    try std.posix.mlock2(slice, std.posix.MLOCK_ONFAULT);
    try std.posix.mlockall(slice, std.posix.MCL_CURRENT|std.posix.MCL_FUTURE);
        {#endsyntax#}

⬇️

    {#syntax#}
    try std.process.lockMemory(slice, .{});
    try std.process.lockMemory(slice, .{.on_fault = true});
    try std.process.lockMemoryAll(.{ .current = true, .future = true });
        {#endsyntax#}

{#header_close#} {#header_open\|Current Directory API Renamed#}

In Zig standard library, {#syntax#}Dir{#endsyntax#} means an open
directory handle. {#syntax#}path{#endsyntax#} represents a file system
identifier string. This function is better named after \"current path\"
than \"current dir\". \"get\" and \"working\" are superfluous.

Upgrade guide:

    {#syntax#}
    std.process.getCwd(buffer)
    std.process.getCwdAlloc(allocator)
        {#endsyntax#}

⬇️

    {#syntax#}
    std.process.currentPath(io, buffer)
    std.process.currentPathAlloc(io, allocator)
        {#endsyntax#}

{#header_close#} {#header_open\|Migration to \"Unmanaged\" Containers#}

In the past, Zig standard library offered two variants of dynamically
growing data structures: one with the {#syntax#}Allocator{#endsyntax#}
instance as a field of the struct (\"managed\"), one where it must be
passed into every method that needs it (\"unmanaged\").

Over time, Zig programmers realized together that the variant without
the allocator field is more versatile and the other one should be
removed. With only one variant, we no longer need this vague word
\"managed\" to distinguish them. In this release, several APIs took
migratory steps:

-   Added {#syntax#}heap.MemoryPoolUnmanaged{#endsyntax#},
    {#syntax#}heap.MemoryPoolAlignedUnmanaged{#endsyntax#},
    {#syntax#}heap.MemoryPoolExtraUnmanaged{#endsyntax#}
    ([#23234](https://github.com/ziglang/zig/pull/23234))
-   {#link\|PriorityDequeue#} no longer has an
    {#syntax#}Allocator{#endsyntax#} field.
-   {#link\|PriorityQueue#} no longer has an
    {#syntax#}Allocator{#endsyntax#} field.
-   {#syntax#}ArrayHashMap{#endsyntax#},
    {#syntax#}AutoArrayHashMap{#endsyntax#},
    {#syntax#}StringArrayHashMap{#endsyntax#} removed.
-   {#syntax#}AutoArrayHashMapUnmanaged{#endsyntax#} ➡️
    {#syntax#}array_hash_map.Auto{#endsyntax#}
-   {#syntax#}StringArrayHashMapUnmanaged{#endsyntax#} ➡️
    {#syntax#}array_hash_map.String{#endsyntax#}
-   {#syntax#}ArrayHashMapUnmanaged{#endsyntax#} ➡️
    {#syntax#}array_hash_map.Custom{#endsyntax#}

{#header_close#} {#header_open\|PriorityDequeue#}

Changes follow {#syntax#}Deque{#endsyntax#} closely:

-   Methods containing {#syntax#}add{#endsyntax#} have been renamed to
    {#syntax#}push{#endsyntax#} and {#syntax#}remove{#endsyntax#} have
    been renamed to {#syntax#}pop{#endsyntax#}.
-   {#syntax#}popMinOrNull{#endsyntax#} and
    {#syntax#}popMaxOrNull{#endsyntax#} have been merged into the
    {#syntax#}popMin{#endsyntax#} and {#syntax#}popMax{#endsyntax#}
    respectively (without any loss in functionality).
-   Default field values are initialized using a
    {#syntax#}.empty{#endsyntax#} constant instead of the
    {#syntax#}init(){#endsyntax#} method.

Upgrade guide:

-   {#syntax#}init{#endsyntax#} ➡️ {#syntax#}.empty{#endsyntax#}
-   {#syntax#}add{#endsyntax#} ➡️ {#syntax#}push{#endsyntax#}
-   {#syntax#}addSlice{#endsyntax#} ➡️ {#syntax#}pushSlice{#endsyntax#}
-   {#syntax#}addUnchecked{#endsyntax#} ➡️
    {#syntax#}pushUnchecked{#endsyntax#}
-   {#syntax#}removeMinOrNull{#endsyntax#} ➡️
    {#syntax#}popMin{#endsyntax#}
-   {#syntax#}removeMin{#endsyntax#} ➡️ {#syntax#}popMin{#endsyntax#}
-   {#syntax#}removeMaxOrNull{#endsyntax#} ➡️
    {#syntax#}popMax{#endsyntax#}
-   {#syntax#}removeMax{#endsyntax#} ➡️ {#syntax#}popMax{#endsyntax#}
-   {#syntax#}removeIndex{#endsyntax#} ➡️
    {#syntax#}popIndex{#endsyntax#}

{#header_close#} {#header_open\|PriorityQueue#}

A priority queue with default field values can be initialized using
{#syntax#}.empty{#endsyntax#}.

For example, a priority queue can be used to initialize a min and max
heap with a compare function like:

{#syntax_block\|zig\|min_heap.zig#} fn lessThan(context: void, a: u32,
b: u32) Order { \_ = context; return std.math.order(a, b); } const
MinHeap = std.PriorityQueue(u32, void, lessThan); var queue: MinHeap =
.empty; {#end_syntax_block#} {#syntax_block\|zig\|max_heap.zig#} fn
greaterThan(context: void, a: u32, b: u32) Order { \_ = context; return
std.math.order(a, b).invert(); } const MaxHeap = std.PriorityQueue(u32,
void, greaterThan); var queue: MaxHeap = .empty; {#end_syntax_block#}

Upgrade guide:

-   {#syntax#}init{#endsyntax#} ➡️ {#syntax#}initContext{#endsyntax#}
-   {#syntax#}add{#endsyntax#} ➡️ {#syntax#}push{#endsyntax#}
-   {#syntax#}addUnchecked{#endsyntax#} ➡️
    {#syntax#}pushUnchecked{#endsyntax#}
-   {#syntax#}addSlice{#endsyntax#} ➡️ {#syntax#}pushSlice{#endsyntax#}
-   {#syntax#}remove{#endsyntax#} ➡️ {#syntax#}pop{#endsyntax#}
-   {#syntax#}removeOrNull{#endsyntax#} ➡️ {#syntax#}pop{#endsyntax#}
-   {#syntax#}removeIndex{#endsyntax#} ➡️
    {#syntax#}popIndex{#endsyntax#}

{#header_close#} {#header_open\|Thread.Pool Removed#}

The thread pool implementation previously at
{#syntax#}std.Thread.Pool{#endsyntax#} has been removed in Zig 0.16.0,
in favor of the multiprocessing primitives in the {#link\|new std.Io
interface\|I/O as an Interface#}.

Uses of {#syntax#}std.Thread.Pool.spawnWg{#endsyntax#} should likely be
replaced with calls to {#syntax#}std.Io.async{#endsyntax#} or
{#syntax#}std.Io.Group.async{#endsyntax#}, though note that this assumes
the task does not need to synchronize with the caller (in other words,
it assume the new task is \*asynchronous\* with the caller). For
instance, one migration might look like this:

    {#syntax#}
    /// Does a lot of work in `pool`, and returns after all this work is completed.
    fn doAllTheWork(pool: *std.Thread.Pool) void {
        var wg: std.Thread.WaitGroup = .{};
        pool.spawnWg(wg, doSomeWork, .{ pool, &wg, first_work_item });
        wg.wait();
    }
    /// Does some work, and potentially adds one or more new tasks to `pool`.
    fn doSomeWork(pool: *std.Thread.Pool, wg: *std.Thread.WaitGroup, foo: Foo) void {
        foo.doTheThing();
        for (foo.new_work_items) |new| {
            pool.spawnWg(wg, doSomeWork, .{ pool, wg, new });
        }
    }
        {#endsyntax#}

⬇️

    {#syntax#}
    /// Does a lot of work in a group, and returns after all this work is completed.
    fn doAllTheWork(io: std.Io) void {
        var g: std.Io.Group = .init;

        // While `doAllTheWork` cannot fail in this case, it may nonetheless be a good idea
        // to do this so that a bug is not introduced if `doAllTheWork` becomes fallible:
        errdefer g.cancel(io);

        g.async(io, doSomeWork, .{ io, &g, first_work_item });
        try g.await(io);
    }
    /// Does one unit of work, and potentially adds one or more new tasks to `pool`.
    fn doSomeWork(io: std.Io, g: *std.Io.Group, foo: Foo) void {
        foo.doTheThing();
        for (foo.new_work_items) |new| {
            g.async(io, doSomeWork, .{ io, g, new });
        }
    }
        {#endsyntax#}

Note that when switching from {#syntax#}std.Thread.Pool{#endsyntax#} to
{#syntax#}std.Io{#endsyntax#}, it is required for correctness that any
{#syntax#}Thread.Mutex{#endsyntax#},
{#syntax#}Thread.Condition{#endsyntax#},
{#syntax#}Thread.ResetEvent{#endsyntax#}, or other thread
synchronization primitive in the code, be converted to its equivalent
{#syntax#}Io{#endsyntax#} type, such as {#syntax#}Io.Mutex{#endsyntax#},
{#syntax#}Io.Condition{#endsyntax#}, or {#syntax#}Io.Event{#endsyntax#}.

For complex usages of {#syntax#}std.Thread.Pool{#endsyntax#} (where two
or more tasks must synchronize somehow), {#syntax#}async{#endsyntax#}
may not be appropriate: consult the documentation for
{#syntax#}std.Io.async{#endsyntax#} and
{#syntax#}std.Io.concurrent{#endsyntax#} for more information.

{#header_close#} {#header_open\|Remove builtin.subsystem#}

The subsystem detection was flaky and often incorrect and was not
actually needed by the compiler or standard library. The actual
subsystem won\'t be known until at link time, so it doesn\'t make sense
to try to determine it at compile time.

Removing {#syntax#}std.builtin.subsystem{#endsyntax#} is a breaking
change but it is unlikely many users were using it in the first place.
[If your code absolutely needs to know the subsystem there are ways to
determine it at
runtime](https://github.com/ziglang/zig/issues/25127#issuecomment-3249505063).

{#header_close#} {#header_open\|Move Target.SubSystem to zig.Subsystem
and update field names#}

{#syntax#}std.zig{#endsyntax#} is where options like
{#syntax#}SanitizeC{#endsyntax#} or {#syntax#}LtoMode{#endsyntax#}
reside, so it is an appropriate place.
{#syntax#}std.Target.SubSystem{#endsyntax#} remains as a deprecated
alias and the old field names remain as deprecated decls to avoid
breaking e.g. {#syntax#}exe.subsystem = .Windows{#endsyntax#} in
build.zig scripts.

{#header_close#} {#header_open\|Io: delete GenericReader, AnyReader,
FixedBufferStream#}

Migration guide:

-   std.io ➡️ std.Io
-   std.Io.GenericReader ➡️ std.Io.Reader
-   std.Io.AnyReader ➡️ std.Io.Reader
-   std.leb.readUleb128 ➡️ std.Io.Reader.takeLeb128
-   std.leb.readIleb128 ➡️ std.Io.Reader.takeLeb128

FixedBufferStream (reading)

    {#syntax#}
    var fbs = std.io.fixedBufferStream(data);
    const reader = fbs.reader();
        {#endsyntax#}

⬇️

    {#syntax#}
        var reader: std.Io.Reader = .fixed(data);
        {#endsyntax#}

FixedBufferStream (writing)

    {#syntax#}
    var fbs = std.io.fixedBufferStream(buffer);
    const writer = fbs.writer();
        {#endsyntax#}

⬇️

    {#syntax#}
        var writer: std.Io.Writer = .fixed(buffer);
        {#endsyntax#}

{#header_close#} {#header_open\|Replace {D} format specifier with
Io.Duration format method#}

The {#syntax#}{D}{#endsyntax#} duration format specifier has been
removed in order to enhance type safety in light of the new
{#syntax#}std.Io.Duration{#endsyntax#} type.

Migration guide:

    {#syntax#}
    writer.print("{D}", .{ns});
        {#endsyntax#}

⬇️

    {#syntax#}
    writer.print("{f}", .{std.Io.Duration{ .nanoseconds = ns }});
        {#endsyntax#}

{#header_close#} {#header_open\|fs.getAppDataDir Removed#}

This API was a bit too opinionated for the Zig standard library.
Applications should contain this logic instead. Users may consider third
party package [known-folders](https://github.com/ziglibs/known-folders)
as an alternative.

{#header_close#} {#header_open\|Io.Writer.Allocating Alignment Field#}
This API now has a new field:

    {#syntax#}
        alignment: std.mem.Alignment,
        {#endsyntax#}

This is a runtime-known alignment value. The Allocator API supports this
if you use the \"raw\" function variants. {#header_close#}
{#header_open\|fs.Dir.readFileAlloc#}

    {#syntax#}
        const contents = try std.fs.cwd().readFileAlloc(allocator, file_name, 1234);
        {#endsyntax#}

⬇️

    {#syntax#}
        const contents = try std.Io.Dir.cwd().readFileAlloc(io, file_name, allocator, .limited(1234));
        {#endsyntax#}

Note that the limit has a difference; if it\'s *reached* it also returns
the error. Also the error has been changed from
{#syntax#}FileTooBig{#endsyntax#} to
{#syntax#}StreamTooLong{#endsyntax#}.

{#header_close#} {#header_open\|fs.File.readToEndAlloc#}

    {#syntax#}
    const contents = try file.readToEndAlloc(allocator, 1234);
        {#endsyntax#}

⬇️

    {#syntax#}
    var file_reader = file.reader(io, &.{});
    const contents = try file_reader.interface.allocRemaining(allocator, .limited(1234));
        {#endsyntax#}

{#header_close#} {#header_open\|std.crypto: add AES-SIV and
AES-GCM-SIV#}

The Zig standard library was missing schemes that are resistant to nonce
reuse.

AES-SIV and AES-GCM-SIV are the standard solutions for this.

AES-GCM-SIV is particularly useful when Zig is targeting embedded
systems, while AES-SIV is especially valuable for key wrapping.

{#header_close#} {#header_open\|std.crypto: add Ascon-AEAD, Ascon-Hash,
Ascon-CHash#}

Ascon is the family of cryptographic constructions standardized by NIST
for lightweight cryptography.

The Zig standard library already included the Ascon permutation itself,
but higher-level constructions built on top of it were intentionally
postponed until NIST released the final specification.

That specification has now been published as [NIST SP
800-232](https://csrc.nist.gov/pubs/sp/800/232/final).

With this publication, we can now confidently include these
constructions in the standard library.

{#header_close#} {#header_close#} {#header_open\|Build System#}

Uncategorized changes:

-   std.Build.Step.ConfigHeader: handle leading whitespace for cmake

{#header_open\|Ability to Override Packages Locally#} ![Carmen the
Allocgator](https://ziglang.org/img/Carmen_9.svg){style="height: 12em; float: right"}

Introduces a new {#syntax#}zig build{#endsyntax#} flag:

    zig build --fork=[path]

This is a **project override** option. The path provided contains a
{#syntax#}build.zig.zon{#endsyntax#} file which contains
{#syntax#}name{#endsyntax#} and {#syntax#}fingerprint{#endsyntax#}
fields. Any time the dependency tree would resolve to a package with
matching {#syntax#}name{#endsyntax#} and
{#syntax#}fingerprint{#endsyntax#}, it resolves to the override instead,
across the entire tree, completely ignoring
{#syntax#}version{#endsyntax#}. This resolves before the package is
potentially fetched. So if you find yourself without Internet, forgot to
fetch, but you have a git repository lying around, you\'re one CLI flag
away from being unblocked.

This is an easy way to temporarily use one or more forks which are in
entirely separate directories. One can iterate on their entire
dependency tree until everything is working, while using comfortably the
development environment and source control of the dependency projects.

The fact that it is a CLI flag makes it appropriately ephemeral. The
moment you drop the flags, you\'re back to using your pristine, fetched
dependency tree.

If the project does not match, an error occurs, preventing confusion:

    $ zig build --fork=/home/andy/dev/mime
    error: fork /home/andy/dev/mime matched no mime packages
    $

If the project does match, you get a reminder that you are using a fork,
preventing confusion:

    $ zig build --fork=/home/andy/dev/dvui
    info: fork /home/andy/dev/dvui matched 1 (dvui) packages
    ...

This functionality is intended to enhance the workflow of dealing with
ecosystem breakage.

This feature depends on the new hash format; therefore legacy hash
format support is removed.

{#header_close#} {#header_open\|Fetch Packages Into Project-Local
Directory#}

Instead of being fetched into `$GLOBAL_ZIG_CACHE/p/$HASH`, package
dependencies are now fetched into a \"zig-pkg\" directory relative to
the build root (next to {#syntax#}build.zig{#endsyntax#}). Users are
generally encouraged to not commit these files to source control,
however it is understood that some will choose to do so for convenience.

After a package is fetched, the filters are applied
({#syntax#}paths{#endsyntax#} field in `build.zig.zon`) in order to
delete files not part of the hash, and then the package is recompressed
into a canonical `$GLOBAL_ZIG_CACHE/p/$HASH.tar.gz` in order to avoid
network next time the same package is needed.

The motivation for this change is to make it easier to tinker. Go ahead
and edit those files, see what happens. Swap out your package directory
with a git clone. Grep your dependencies all together. Configure your
IDE to auto-complete based on zig-pkgs directory. [Run baobab on your
dependency tree](https://codeberg.org/awebo-chat/awebo/issues/61).
Furthermore, by having the global cache have compressed files instead
makes it easier to share that cached data between computers.

{#syntax#}zig build{#endsyntax#} will now fail when encountering package
dependencies without {#syntax#}fingerprint{#endsyntax#} field or with
{#syntax#}name{#endsyntax#} as a string rather than enum literal.
Fingerprint is needed in order to determine that two packages with
different versions are intended to be different versions of the same
project. It will become an error to have the same fingerprint, same
version, different hash in your dependency tree because it means
somebody forgot to bump a version number, or somebody is trying to do a
hostile package fork and now you have to choose a side.

Zig no longer observes {#syntax#}ZIG_BTRFS_WORKAROUND{#endsyntax#}
environment variable. The bug has been fixed in upstream Linux a long
time ago by now ([#17095](https://github.com/ziglang/zig/issues/17095)).

{#header_close#} {#header_open\|Unit Test Timeouts#}

It is now possible to specify a timeout to apply to all individual Zig
unit tests (i.e. {#syntax#}test{#endsyntax#} blocks). Using the
`--test-timeout` flag to `zig build`, you can specify a timeout value,
after which the build system will forcibly terminate the current unit
test (by killing and restarting the test process) and move on to the
next.

For instance, running `zig build test --test-timeout 500ms` will run the
step named `test`, except if any individual Zig unit test fails to
finish within 500ms of real time, the test will be terminated and an
error emitted:

    $ zig build test --test-timeout 500ms
    test
    └─ run test 1 pass, 2 timeout (3 total)
    error: 'main.test.first slow test' timed out after 499.491ms
    error: 'main.test.second slow test' timed out after 499.609ms
    failed command: ./.zig-cache/o/6d2da140357b7fa42c69cd4b151c14ff/test --cache-dir=./.zig-cache --seed=0xb6711f5 --listen=-

    Build Summary: 1/3 steps succeeded (1 failed); 1/3 tests passed (2 timed out)
    test transitive failure
    └─ run test 1 pass, 2 timeout (3 total)

This is useful to detect slow tests or tests which are failing to
terminate. However, bear in mind that the timeouts are specified in real
time rather than CPU time, so on a system under heavy load, scheduler
stress could cause unexpected timeouts.

{#header_close#} {#header_open\|Added `--error-style` Flag#}

The new `--error-style` CLI flag of `zig build` allows customizing how
error messages from build steps are written to stderr. The default
style, `verbose`, will print the full context, including the relevant
step dependency tree showing why this step is being built, and failed
commands where applicable. Alternatively, the `minimal` style can be
specified to omit these pieces of information in favour of simply
printing the failed step name and its error message.

In addition, two more error styles are available, `verbose_clear` and
`minimal_clear`. These are similar to `verbose` and `minimal`
respectively, but when using `--watch`, they will clear the terminal
when a rebuild is triggered due to an input file changing. These modes
are particularly useful if you make use of {#link\|Incremental
Compilation#}.

If the `--error-style` flag is not specified, the build system will also
check for the environment variable `ZIG_BUILD_ERROR_STYLE`, and if
present, use that value. This allows globally specifying your preferred
mode by setting a persistent environment variable in your shell
configuration.

This flag replaces the `--prominent-compile-errors` flag, which has been
removed. If you were previously using `--prominent-compile-errors`, the
equivalent in Zig 0.16.x is `--error-style minimal`.

{#header_close#} {#header_open\|Added `--multiline-errors` Flag#}

The new `--multiline-errors` CLI flag of `zig build` controls how the
build system prints errors which span multiple lines. The available
options are `indent` (the new default), `newline`, and `none`:

    error: this is how the "indent" style looks when an error message
           spans multiple lines. every line other than the first is
           indented to align with the first line.

    error:
    this is how the "newline" style looks when an error message
    spans multiple lines. an extra newline is added before the
    start to align all of the lines at the first column.

    error: this is how the "none" style looks when an error message
    spans multiple lines. no special handling is applied, so
    the first line is not aligned with the remaining lines.

If the `--multiline-errors` flag is not specified, the build system will
also check for the environment variable `ZIG_BUILD_MULTILINE_ERRORS`,
and if present, use that value. This allows globally specifying your
preferred mode by setting a persistent environment variable in your
shell configuration.

{#header_close#} {#header_open\|Temporary Files API#}

The RemoveDir step is gone with no replacement. This step had no valid
purpose. Mutating source files? That should be done with
UpdateSourceFiles step. Deleting temporary directories? That required
creating the tmp directories in the configure phase which is broken.
Deleting cached artifacts? That\'s going to cause problems.

Similarly, {#syntax#}Build.makeTempPath{#endsyntax#} function is gone.
This was used to create a temporary path in the configure place which,
again, is the wrong place to do it.

Instead, the WriteFile step has been updated with more functionality:

**tmp mode**: In this mode, the directory will be placed inside \"tmp\"
rather than \"o\", and caching will be skipped. During the
{#syntax#}make{#endsyntax#} phase, the step will always do all the file
system operations, and on successful build completion, the dir will be
deleted along with all other tmp directories. The directory is therefore
eligible to be used for mutations by other steps.
{#syntax#}Build.addTempFiles{#endsyntax#} is introduced to initialize a
WriteFile step with this mode.

**mutate mode**: The operations will not be performed against a freshly
created directory, but instead act against a temporary directory.
{#syntax#}Build.addMutateFiles{#endsyntax#} is introduced to initialize
a WriteFile step with this mode.

{#syntax#}Build.tmpPath{#endsyntax#} is introduced, which is a shortcut
for {#syntax#}Build.addTempFiles{#endsyntax#} followed by
{#syntax#}WriteFile.getDirectory{#endsyntax#}.

Upgrade guide:

If you were calling {#syntax#}b.makeTempPath(){#endsyntax#} followed by
{#syntax#}addRemoveDirTree{#endsyntax#}, instead you can now call
{#syntax#}b.addTempFiles{#endsyntax#} and use the
{#syntax#}std.Build.Step.WriteFile{#endsyntax#} API. No need to do
anything else, the build runner will clean up the tmp files for you, and
it will understand that the tmp files cannot be cached.

{#header_close#} {#header_close#} {#header_open\|Compiler#}
{#header_open\|C Translation#}

Zig\'s implementation of translate-c is now based on
[arocc](https://github.com/Vexu/arocc/) and
[translate-c](https://codeberg.org/ziglang/translate-c) instead of
libclang. Goodbye and good riddance to 5,940 lines of our remaining C++
code in the compiler source tree, with 3,763 remaining.

The implementation is compiled lazily from source the first time
{#syntax#}@cImport{#endsyntax#} is encountered. {#link\|In the future,
Zig will drop the \@cImport language builtin\|@cImport Moving to Build
System#}, but for now it remains, backed by Aro instead of Clang.

This is progress towards [transitioning from a library dependency on
LLVM to a process dependency on
Clang](https://github.com/ziglang/zig/issues/16270).

This is technically a non-breaking change. While breakage is likely due
to one C compiler being swapped out for another, if it occurs it is a
bug rather than a feature. So, cross your fingers when you upgrade and
report a bug if something breaks.

{#header_close#} {#header_open\|LLVM Backend#}

-   **Experimental support for {#link\|Incremental Compilation#}**
-   3-7% decrease in LLVM bitcode size
-   Slightly faster compilation (\~3%) in some cases
-   Fixed debug information for unions with zero-bit payloads
-   Debug information now includes correct names for all types
-   Error set types are now lowered as enums so that error names are
    visible at runtime

Matthew also looked into changing the representation of tagged union and
error union types in debug information to use [variant
types](https://dwarfstd.org/doc/DWARF5.pdf#page=141), which would allow
debuggers to understand which field is \"active\" and only show that
one. Unfortunately, while GDB supports this feature, LLDB does not, and
fails to print the type\'s fields whatsoever when variant types are
used. (Bizarrely, LLDB *does* have partial support, but [it\'s only
enabled when the language is marked as
Rust](https://github.com/llvm/llvm-project/blob/0c0ae3786ef4ec04ba0dc9cdd565b68ec486498a/lldb/source/Plugins/SymbolFile/DWARF/DWARFASTParserClang.cpp#L3203-L3207)).
He may revisit this in the future if the situation improves downstream.

We have made some internal changes to try and work towards fully
parallelising this backend, so that there can be multiple threads
generating LLVM IR for different functions which then get glued together
by a \"linker\" thread. Expect more progress towards this in the future!

Compared to the {#link\|x86 Backend#}, the LLVM backend is passing
2004/2010 (100%) of the behavior tests.

{#header_close#} {#header_open\|Reworked Byval Syntax Lowering#}

When writing the self-hosted compiler, there was an early experiment to
attempt to slightly reduce the number of intermediate instructions
emitted in the pipeline, by lowering expressions with \"byval\"
semantics. The experiment was a failure, because it lead to the
following issues:

-   [Array access performance
    issues](https://github.com/ziglang/zig/issues/13938)
-   [Surprising aliasing despite explicit
    copy](https://github.com/ziglang/zig/issues/22906)
-   [Extremely poor code quality in degenerate
    cases](https://github.com/ziglang/zig/issues/25111)

The frontend now lowers expressions \"byref\" until the final load,
fixing all of those issues.

[more details](https://github.com/ziglang/zig/pull/25154)

{#header_close#} {#header_open\|Reworked Type Resolution#}

Zig 0.16.0 [significantly
reworks](https://codeberg.org/ziglang/zig/pulls/31403) how the Zig
compiler handles type resolution internally. The motivation behind this
change was to simplify the process of writing the Zig language
specification, and to resolve a huge number of compiler bugs, in
particular related to {#link\|Incremental Compilation#}.

The new type resolution semantics are, on the whole, *more* permissive
than the old behavior. This means that most code which previously worked
will continue to work, and some examples which previously did not work
(likely with a \"dependency loop\" error) *will* now work.

However, the new system is not *strictly* more permissive. There are
certain things which were previously accepted by the Zig compiler and
are now not, such as the following:

{#code\|struct_uses_own_alignment.zig#}

The rules of the new system are generally more intuitive---for instance,
while the above code snippet *could* theoretically work, it also seems
clear why it might *not*. In other words, the dependency loop errors do
not seem unreasonable or wholly unexpected, which they often did in
previous versions of Zig.

Unfortunately, it is difficult to give general advice if you are
experiencing dependency loop errors, because the appropriate solution is
highly contextual. However, Zig 0.16.0 also significantly improves error
reporting in dependency loop situations, which should hopefully make it
easier to understand where dependency loops actually come from:

{#code\|complex_dependency_loop.zig#}

If you are struggling to resolve a dependency loop, consider joining a
Zig [community](https://ziglang.org/community/) to get help from fellow
Zig users!

{#header_close#} {#header_open\|Incremental Compilation#} ![Carmen the
Allocgator](https://ziglang.org/img/Carmen_10.svg){style="height: 16em; float: right"}

Incremental compilation is a feature of the Zig compiler which allows it
to only compile code which has been modified since the previous build,
making small changes take milliseconds to build instead of seconds or
minutes. In Zig 0.16.0, support for this feature has improved
significantly.

Here are some of the main improvements in this release cycle:

-   Incremental updates have been made significantly faster by avoiding
    \"over-analysis\" (where the compiler rebuilds more code than it
    needs to) in the vast majority of cases. For instance, when using
    incremental compilation on the Zig compiler itself, changes which
    previously recompiled almost the entire compiler now complete in
    milliseconds. This is thanks to {#link\|Reworked Type Resolution#}
    making the compiler\'s internal dependency graph acyclic (except in
    the case of dependency loops).
-   Incremental compilation no longer triggers \"dependency loop\"
    compile errors which do not occur in non-incremental builds (and
    vice versa). This was the biggest inconsistency between incremental
    and non-incremental builds in previous releases, and was resolved as
    a part of {#link\|Reworked Type Resolution#}.
-   When using a self-hosted backend targeting ELF, the {#link\|New ELF
    Linker#} is now enabled by default, which is faster and has much
    more stable support for incremental compilation. This linker is not
    yet feature-complete---see {#link\|New ELF Linker#} for details.
-   General stability has greatly improved---crashes and miscompilations
    in incremental updates are far less common than in previous versions
    of Zig.
-   The {#link\|LLVM Backend#} now supports incremental compilation.
    **This does not speed up the \"LLVM Emit Object\" phase of
    compilation:** that step is entirely LLVM\'s responsibility and
    there is little we can do to speed it up. However, it does speed up
    the building of LLVM bitcode in the Zig compiler. This also means
    that in cases where your code emits compilation errors, you can get
    near-instant feedback even with the LLVM backend (since \"LLVM Emit
    Object\" is skipped when compile errors exist).

Incremental compilation {#link\|still has known bugs, including some
miscompilations\|This Release Contains Bugs#}, and therefore remains
disabled by default in 0.16.0. **Despite this, we still encourage
enabling it.** Users are frequently surprised by just how much time they
can save even just with near-instant compile error feedback, let alone
near-instant *compilation*!

Because incremental compilation is now usable with both the
{#link\|self-hosted ELF linker\|New ELF Linker#} and the {#link\|LLVM
Backend#}, opting in is usually as simple as running
`zig build -fincremental --watch`. This command will spawn a build
process which can detect when any source files change and automatically
perform an incremental update.

{#link\|Future release cycles\|Roadmap#} will continue to focus on
incremental compilation, with more bug fixes, improved testing
infrastructure, performance enhancements, and better {#link\|Linker#}
support.

{#header_close#} {#header_open\|x86 Backend#}

-   11 bugs fixed.
-   Generates better constant memcpy code
    ([#25353](https://github.com/ziglang/zig/pull/25353)).

Compared to the {#link\|LLVM Backend#}, this backend passes more
behavior tests, has significantly faster compilation speed, superior
debug information, and inferior machine code quality. It remains the
default when compiling in Debug mode.

{#header_close#} {#header_open\|aarch64 Backend#}

Still a work-in-progress. Progress was paused during this release cycle
due to the {#link\|I/O as an Interface#} churn. Currently crashes when
running the behavior tests. Progress is expected to pick up as the
{#link\|Standard Library#} churn subsides.

{#header_close#} {#header_open\|WebAssembly Backend#}

Compared to the {#link\|LLVM Backend#}, Zig\'s WebAssembly backend is
passing 1813/1970 (92%) of behavior tests.

{#header_close#} {#header_open\|Generating Import Libraries from .def
Files Without LLVM#}

Eliminates a dependency on LLVM with regards to the set of
{#link\|MinGW-w64#} .def files shipped with Zig. This implementation is
largely based on the LLVM implementation (specifically
[COFFModuleDefinition.cpp](https://github.com/llvm/llvm-project/blob/main/llvm/lib/Object/COFFModuleDefinition.cpp)
and
[COFFImportFile.cpp](https://github.com/llvm/llvm-project/blob/main/llvm/lib/Object/COFFImportFile.cpp)).

This is progress towards [transitioning from a library dependency on
LLVM to a process dependency on
Clang](https://github.com/ziglang/zig/issues/16270).

{#header_close#} {#header_open\|Improved Code Generation of For Loop
Safety Checks#}

Looping over slices generates \~30% less code.

{#header_close#} {#header_close#} {#header_open\|Linker#}
{#header_open\|New ELF Linker#}

The new linker can be used with {#syntax#}-fnew-linker{#endsyntax#} in
the CLI, or by setting {#syntax#}exe.use_new_linker = true{#endsyntax#}
in a build script. It is now the default when passing
{#syntax#}-fincremental{#endsyntax#} and targeting ELF.

Performance data point
\[[source](https://github.com/ziglang/zig/pull/25299#issuecomment-3321207092)\]:
building the Zig {#link\|Compiler#}, then making a single-line change to
a function, and then another:

-   Old linker: 14s, 194ms, 191ms
-   New linker: 14s, 65ms, 64ms (66% faster)
-   Skip linking altogether: 14s, 62ms, 62ms (68% faster)

The performance is fast enough that there is **no longer much benefit to
exposing a `-Dno-bin` build step**. You might as well keep codegen and
linking always enabled because the compilation speed difference is
negligible, and then you get an executable at the end.

However, this new linker is not feature complete versus the old one nor
versus LLD. For example, executables produced this way lack DWARF
information. Therefore, the old linker and LLD are both still available.
When the new linker is feature complete, the old linker will be deleted
and LLD will be removed as a dependency.

{#header_close#} {#header_close#} {#header_open\|Fuzzer#}
{#header_open\|Smith#} ![Carmen the
Allocgator](https://ziglang.org/img/Carmen_8.svg){style="height: 6em; float: right"}

The {#syntax#}\[\]const u8{#endsyntax#} parameter of fuzz tests has been
replaced with {#syntax#}\*std.testing.Smith{#endsyntax#}. This new
interface is used to generate values from the fuzzer. It contains the
following base methods:

-   {#syntax#}value{#endsyntax#} for generating any type.
-   {#syntax#}eos{#endsyntax#} for generating end-of-stream markers.
    Provides the additional guarantee that {#syntax#}true{#endsyntax#}
    will eventually by returned.
-   {#syntax#}bytes{#endsyntax#} for filling a byte array.
-   {#syntax#}slice{#endsyntax#} for filling part of a buffer and
    providing the length.

Values can be given a probability of being selected with
{#syntax#}\[\]const Smith.Weight{#endsyntax#}. This is useful to

-   make interesting values be chosen more often
-   reduce the chance for more work
-   constrain selectable values

In an empty slice of weights, every value has a weight of zero and will
not be selected. Weights can only be used with types fitting in 64-bits.
Each base methods has corresponding ones that accept weights.
Additionally, the following functions are provided:

-   {#syntax#}baselineWeights{#endsyntax#} which provides a set of
    weights containing every possible value of a type.
-   {#syntax#}boolWeighted{#endsyntax#} and
    {#syntax#}eosSimpleWeighted{#endsyntax#} for conveniently weighing
    {#syntax#}true{#endsyntax#} and {#syntax#}false{#endsyntax#}.
-   {#syntax#}valueRangeAtMost{#endsyntax#} and
    {#syntax#}valueRangeLessThan{#endsyntax#} for generating only a
    range of values.

Each method also has a counterpart which accepts a hash where values
with the same hash are more more likely to be mutated in respect to each
other. The regular methods already use hashes based off the callee\'s
return address, so it is usually redundant to directly call these
functions, but they can be useful in case of inlining.

Example upgrade:

    {#syntax#}
    fn fuzzTest(_: void, input: []const u8) !void {
        var sum: u64 = 0;
        for (input) |b| {
            sum += b;
        }
        try std.testing.expect(sum != 1234);
    }
        {#endsyntax#}

⬇️

    {#syntax#}
    fn fuzzTest(_: void, smith: *std.testing.Smith) !void {
        var sum: u64 = 0;
        while (!smith.eosWeightedSimple(7, 1)) {
            sum += smith.value(u8);
        }
        try std.testing.expect(sum != 1234);
    }
        {#endsyntax#}

{#header_close#} {#header_open\|Multiprocess Fuzzing#}

The fuzzer now is able to utilize multiple cores. This is controllable
with the {#syntax#}-j{#endsyntax#} build option. Limited fuzzing still
uses one core.

{#header_close#} {#header_open\|Fuzzing Infinite Mode#}

When provided multiple tests, the fuzzer now switches between them and
prioritizes the most effective and interesting ones. Over time already
explored tests will become barely run compared to tests yielding new
inputs.

{#header_close#} {#header_open\|Crash Dumps#}

Crashing inputs are now saved to a file indicated by the crash message.
It is recommended to use these files to reproduce the crash using
{#syntax#}std.testing.FuzzInputOptions.corpus{#endsyntax#} and
{#syntax#}@embedFile{#endsyntax#}.

{#header_close#} {#header_open\|Numerous bugs found and fixed with the
help of an AST smith#}

The new smith interface has already seen use in testing the toolchain
with the creation of an AST Smith which is used to generate random valid
ASTs.

When run against zig fmt (in addition to some earlier simpler random
source testing) 20 unique bugs were found and fixed, some of which had
been previously reported and many newly discovered.

It also found several inconsistencies between the specified PEG and the
parser: notably, a tuple could not contain types starting with
{#syntax#}extern{#endsyntax#} or {#syntax#}inline{#endsyntax#}; for
example, {#syntax#}const T = struct { u64, extern struct { a: u64 }, u32
}{#endsyntax#} would result in an error. A detailed list of PEG and
Parser changes can be found on [add an ast
smith](https://codeberg.org/ziglang/zig/pulls/31635).

{#header_close#} {#header_close#} {#header_open\|Bug Fixes#}

Full list of the 345 bug reports closed during this release cycle:

-   [Tracked on
    GitHub](https://github.com/ziglang/zig/issues?q=is%3Aclosed+is%3Aissue+label%3Abug+milestone%3A0.16.0)
-   [Tracked on
    Codeberg](https://codeberg.org/ziglang/zig/issues?q=&type=all&sort=relevance&state=closed&labels=741711&milestone=32343&project=0&assignee=0&poster=0)

Many bugs were both introduced and resolved within this release cycle.
Most bug fixes are omitted from these release notes for the sake of
brevity.

{#header_open\|This Release Contains Bugs#}

Zig has known
[bugs](https://codeberg.org/ziglang/zig/issues?q=&type=all&sort=relevance&labels=741711&state=open&milestone=0&project=0&assignee=0&poster=0),
[miscompilations](https://codeberg.org/ziglang/zig/issues?q=&type=all&sort=relevance&labels=746970&state=open&milestone=0&project=0&assignee=0&poster=0),
and
[regressions](https://codeberg.org/ziglang/zig/issues?q=&type=all&sort=relevance&labels=741714&state=open&milestone=0&project=0&assignee=0&poster=0).

Even with Zig 0.16.x, working on a non-trivial project using Zig may
require participating in the development process.

When Zig reaches 1.0.0, Tier 1 support will gain a bug policy as an
additional requirement.

{#header_close#} {#header_close#} {#header_open\|Toolchain#}
{#header_open\|LLVM 21#}

This release of Zig upgrades to [LLVM
21.1.0](https://releases.llvm.org/21.1.0/docs/ReleaseNotes.html). This
covers Clang ({#link\|zig cc#}), libc++, libc++abi, libunwind, and
libtsan as well.

{#header_open\|Loop Vectorization Disabled to Work Around Regression#}

The regression is serious for Zig because it causes the compiler itself
to be miscompiled in common configurations. Trying to work around this
by disabling certain CPU features is too brittle, so we have disabled
loop vectorization entirely until we upgrade to a version of LLVM where
this bug is fixed. This pessimises codegen in some cases, which, while
unfortunate, is preferable to miscompilations.

This has been
[reported](https://github.com/llvm/llvm-project/issues/186922) and
[fixed](https://github.com/llvm/llvm-project/pull/187023) upstream,
however at time of writing the fix has not been cherry-picked into
LLVM\'s 22.x release branch, therefore we expect this performance
regression to affect not only Zig 0.16.x but also 0.17.x, finally
resolved in 0.18.x.

{#header_close#} {#header_close#} {#header_open\|musl 1.2.5#}

Zig 0.16.0 distributes musl 1.2.5 plus backported security fixes.
Meanwhile, upstream has tagged 1.2.6. A future release of Zig will
update to musl 1.2.6.

When targeting musl statically, many functions are now provided by
{#link\|zig libc#} rather than source files copied from musl.
Specifically, 331 fewer musl C source files are now distributed with
Zig, with 1,206 remaining. Therefore, if you encounter bugs with musl
libc provided by Zig, please respect upstream by reporting them to
Zig\'s issue tracker rather than musl\'s.

Note that Zig 0.16.0 is not believed to be affected by
[CVE-2026-40200](https://www.openwall.com/lists/oss-security/2026/04/10/13)
due to musl\'s `qsort` and `qsort_r` no longer being used.

{#header_close#} {#header_open\|glibc 2.43#}

glibc version 2.43 is now available when cross-compiling.

{#header_close#} {#header_open\|Linux 6.19 Headers#}

This release includes Linux kernel headers for version 6.19.

{#header_close#} {#header_open\|macOS 26.4 Headers#}

This release includes macOS system headers for version 26.4.

{#header_close#} {#header_open\|MinGW-w64#}

Zig 0.16.0 continues to distribute MinGW-w64 commit
`38c8142f660b6ba11e7c408f2de1e9f8bfaf839e`.

However, many functions are now provided by {#link\|zig libc#} rather
than source files copied from MinGW-w64. Specifically, 99 fewer
MinGW-w64 C source files are now distributed with Zig, with 398
remaining. Therefore, if you encounter bugs with MinGW-w64 libc provided
by Zig, please respect upstream by reporting them to Zig\'s issue
tracker rather than MinGW-w64\'s.

{#header_close#} {#header_open\|FreeBSD 15.0 libc#}

FreeBSD libc version 15.0 is now available when cross-compiling.

{#header_close#} {#header_open\|WASI libc#}

Zig 0.16.0 updates to WASI libc commit
`c89896107d7b57aef69dcadede47409ee4f702ee`.

However, many functions are now provided by {#link\|zig libc#} rather
than source files copied from WASI libc.

In spite of this, the number of WASI libc C source files distributed
with Zig increased from 196 to 228 due to the newer WASI libc adding
pthread shims and the fact that most WASI libc source files are shared
with {#link\|musl\|musl 1.2.5#}.

{#header_close#} {#header_open\|zig libc#}

Zig\'s libc implementation gained many new functions, leading to the
corresponding C source files being deleted from {#link\|musl\|musl
1.2.5#} and {#link\|MinGW-w64#}. In this release, the number of C source
files distributed went from 2,270 to 1,873 (-17%).

Notably this includes many math functions, as well as `malloc` and
friends. Special thanks to Szabolcs Nagy for
[libc-test](https://wiki.musl-libc.org/libc-test.html).

{#header_close#} {#header_open\|zig cc#}

`zig cc` and `zig c++` are now based on Clang 21.1.8.

9 bugs were fixed:
[GitHub](https://github.com/ziglang/zig/issues/?q=is%3Aissue%20state%3Aclosed%20label%3A%22zig%20cc%22%20milestone%3A0.16.0)
[Codeberg](https://codeberg.org/ziglang/zig/issues?q=&type=all&sort=relevance&state=closed&labels=741711%2C747024&milestone=32343&project=0&assignee=0&poster=0&archived=false)

{#header_close#} {#header_open\|Support dynamically-linked OpenBSD libc
when cross-compiling#}

Zig now allows cross-compiling to OpenBSD 7.8+ by providing stub
libraries for dynamic libc, similar to how cross-compilation for glibc
is handled. Additionally, all libc headers and most system headers are
provided.
