# 0.16.0 Release Notes


[Download & Documentation](https://ziglang.org/download/#release-0.16.0)


Zig is a general-purpose programming language and toolchain for maintaining
robust, optimal, and reusable software.


Zig development is funded via [Zig Software Foundation](/zsf/),
a 501(c)(3) non-profit organization. Please consider a recurring donation
so that we can offer more billable hours to our core team members. This is
the most straightforward way to accelerate the project along the
[Roadmap](#Roadmap) to 1.0. If you need donation receipts or are
looking to migrate away from GitHub Sponsors, we recommend
[donating via Every.org](https://www.every.org/zig-software-foundation-inc).


This release features 8 months of work:
changes from 244 different contributors, spread among
1183 commits.


Perhaps most notably, this release debuts [I/O as an Interface](#I/O as an Interface),
but don't sleep on the [Language Changes](#Language Changes) or enhancements to
the [Compiler](#Compiler), [Build System](#Build System), [Linker](#Linker),
[Fuzzer](#Fuzzer), and [Toolchain](#Toolchain) which are also included in this release.


## Table of Contents


## Target Support


Zig supports a wide range of architectures and operating systems. The
[Support Table](#Support Table) and [Additional Platforms](#Additional Platforms) sections cover
the targets that Zig can build programs for, while the
[zig-bootstrap README](https://codeberg.org/ziglang/zig-bootstrap#supported-targets)
covers the targets that the Zig compiler itself can be easily
cross-compiled to run on.


Notable changes:


- `aarch64-freebsd`, `aarch64-netbsd`,
`loongarch64-linux`, `powerpc64le-linux`,
`s390x-linux`, `x86_64-freebsd`,
`x86_64-netbsd`, and `x86_64-openbsd` are now
tested natively in Zig's CI, ensuring high-quality support going
forward. Thanks to [OSUOSL](https://osuosl.org/) for
providing AArch64 and Power ISA hardware, and
[IBM](https://community.ibm.com/community/user/groupz?CommunityKey=8c2c15eb-f059-4e7c-8cb6-5fb713a7806c)
for providing z/Architecture hardware.


- Cross-compilation support for `aarch64-maccatalyst` and
`x86_64-maccatalyst` has been added. This was 'free' in a
sense, since the vendored `libSystem.tbd` that Zig ships
already provides the symbols for these targets anyway.


- Initial `loongarch32-linux` support has been added. Note that
libc is not yet supported for this target, and LLVM still considers the
ABI unstable, but programs using only syscalls via
`std.os.linux` can be built.


- Basic support has been added for the Alpha, KVX, MicroBlaze, OpenRISC,
PA-RISC, and SuperH architectures. For now, these targets require using
either Zig's C backend with GCC or an external LLVM/Clang fork.


- Support for Oracle's Solaris and IBM's AIX and z/OS has been removed. In
general, the Zig project cannot support proprietary operating systems
that make it unreasonably difficult to obtain system headers and thus
audit contributions. Note that this does not affect illumos; being an
open source fork from OpenSolaris, it remains supported.


- [Stack tracing support has been significantly improved across the board](#Expanded target support for segfault handling/unwinding);
almost all major targets now provide stack traces on crashes.


- Various [Standard Library](#Standard Library) bugs that mainly affected weakly-ordered
architectures and targets with unusual page sizes have been fixed. Among
others, this is known to have significantly improved reliability on
AArch64 (especially w/o LSE), LoongArch, and Power ISA.


- Various [Standard Library](#Standard Library) and [Compiler](#Compiler) bugs preventing Zig
from working on big-endian hosts have been fixed.


- Big-endian ARM targets have been fixed to emit BE8 object files when
targeting ARMv6+, rather than the legacy BE32 format.


## Tier System


Zig's level of support for various targets is broadly categorized into
four tiers with Tier 1 being the highest. The goal is for Tier 1 targets
to have zero disabled tests - this will become a requirement for
post-1.0.0 Zig releases.


## Tier 1


- All non-experimental [language](#Language Changes) features are known to work correctly.


- The [Compiler](#Compiler) can generate machine code for these targets without relying on [LLVM](#LLVM 21).


## Tier 2


- The [Standard Library](#Standard Library) cross-platform abstractions account for these targets.


- These targets have debug info capabilities and therefore produce stack traces on failed assertions and crashes.


- Libc is available for these targets when cross-compiling.


- Continuous Integration machines run the module tests for these targets on every push.


## Tier 3


- The [Compiler](#Compiler) can generate machine code for these targets via [LLVM](#LLVM 21).


- The [Linker](#Linker) can produce object files, libraries, and executables for these targets.


- These targets are not considered experimental by [LLVM](#LLVM 21).


## Tier 4


- The [Compiler](#Compiler) can generate assembly source code for these targets via [LLVM](#LLVM 21).


## Support Table


In the following table, ✅ indicates full support, ❌ indicates no
support, and ⚠️ indicates that there is partial support, e.g. only for some
sub-targets, or with some notable known issues. ❔ indicates that the
status is largely unknown, typically because the target is rarely
exercised. Hover over other icons for details.


| Target | Tier | Lang. Feat. | Std. Lib. | Code Gen. | Linker | Debug Info | libc | CI |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `x86_64-linux` | 1 | ✅ | ✅ | 🖥️⚡ | ✅ | ✅ | ✅ | ✅ |
| `aarch64-freebsd` | 2 | ✅ | ✅ | 🖥️🛠️ | ✅ | ✅ | ✅ | ✅ |
| `aarch64(_be)-linux` | 2 | ✅ | ✅ | 🖥️🛠️ | ✅ | ✅ | ✅ | ✅ |
| `aarch64-maccatalyst` | 2 | ✅ | ✅ | 🖥️🛠️ | ✅ | ✅ | ✅ | ⚠️ |
| `aarch64-macos` | 2 | ✅ | ✅ | 🖥️🛠️ | ✅ | ✅ | ✅ | ✅ |
| `aarch64(_be)-netbsd` | 2 | ✅ | ✅ | 🖥️🛠️ | ✅ | ✅ | ✅ | ✅ |
| `aarch64-openbsd` | 2 | ✅ | ✅ | 🖥️🛠️ | ✅ | ✅ | ✅ | ⚠️ |
| `aarch64-windows` | 2 | ✅ | ✅ | 🖥️🛠️ | ✅ | ✅ | ✅ | ⚠️ |
| `arm-freebsd` | 2 | ✅ | ✅ | 🖥️ | ✅ | ✅ | ✅ | ⚠️ |
| `arm(eb)-linux` | 2 | ✅ | ✅ | 🖥️ | ✅ | ✅ | ✅ | ✅ |
| `arm(eb)-netbsd` | 2 | ✅ | ✅ | 🖥️ | ✅ | ✅ | ✅ | ⚠️ |
| `arm-openbsd` | 2 | ✅ | ✅ | 🖥️ | ✅ | ✅ | ✅ | ⚠️ |
| `hexagon-linux` | 2 | ✅ | ✅ | 🖥️ | ✅ | ✅ | ✅ | ✅ |
| `loongarch64-linux` | 2 | ✅ | ✅ | 🖥️🛠️ | ✅ | ✅ | ✅ | ✅ |
| `mips(el)-linux` | 2 | ✅ | ✅ | 🖥️ | ✅ | ✅ | ✅ | ✅ |
| `mips(el)-netbsd` | 2 | ✅ | ✅ | 🖥️ | ✅ | ✅ | ✅ | ⚠️ |
| `mips64(el)-linux` | 2 | ✅ | ✅ | 🖥️ | ✅ | ✅ | ✅ | ✅ |
| `mips64(el)-openbsd` | 2 | ✅ | ✅ | 🖥️ | ✅ | ✅ | ✅ | ⚠️ |
| `powerpc-linux` | 2 | ✅ | ✅ | 🖥️ | ✅ | ✅ | ✅ | ⚠️ |
| `powerpc-netbsd` | 2 | ✅ | ✅ | 🖥️ | ✅ | ✅ | ✅ | ⚠️ |
| `powerpc-openbsd` | 2 | ✅ | ✅ | 🖥️ | ✅ | ✅ | ✅ | ⚠️ |
| `powerpc64(le)-freebsd` | 2 | ✅ | ✅ | 🖥️ | ✅ | ✅ | ✅ | ⚠️ |
| `powerpc64(le)-linux` | 2 | ✅ | ✅ | 🖥️ | ⚠️ | ✅ | ✅ | ⚠️ |
| `powerpc64-openbsd` | 2 | ✅ | ✅ | 🖥️ | ✅ | ✅ | ✅ | ⚠️ |
| `riscv32-linux` | 2 | ✅ | ✅ | 🖥️ | ✅ | ✅ | ✅ | ✅ |
| `riscv64-freebsd` | 2 | ✅ | ✅ | 🖥️🛠️ | ✅ | ✅ | ✅ | ⚠️ |
| `riscv64-linux` | 2 | ✅ | ✅ | 🖥️🛠️ | ✅ | ✅ | ✅ | ✅ |
| `riscv64-openbsd` | 2 | ✅ | ✅ | 🖥️🛠️ | ✅ | ✅ | ✅ | ⚠️ |
| `s390x-linux` | 2 | ✅ | ✅ | 🖥️ | ✅ | ✅ | ✅ | ✅ |
| `thumb(eb)-linux` | 2 | ✅ | ✅ | 🖥️ | ✅ | ✅ | ✅ | ✅ |
| `thumb-windows` | 2 | ✅ | ✅ | 🖥️ | ✅ | ✅ | ✅ | ⚠️ |
| `wasm32-wasi` | 2 | ✅ | ✅ | 🖥️🛠️ | ✅ | ⚠️ | ✅ | ✅ |
| `x86-linux` | 2 | ✅ | ✅ | 🖥️ | ✅ | ✅ | ✅ | ✅ |
| `x86-netbsd` | 2 | ✅ | ✅ | 🖥️ | ✅ | ✅ | ✅ | ⚠️ |
| `x86-openbsd` | 2 | ✅ | ✅ | 🖥️ | ✅ | ✅ | ✅ | ⚠️ |
| `x86-windows` | 2 | ✅ | ✅ | 🖥️ | ✅ | ✅ | ✅ | ⚠️ |
| `x86_64-freebsd` | 2 | ✅ | ✅ | 🖥️🛠️ | ✅ | ✅ | ✅ | ✅ |
| `x86_64-maccatalyst` | 2 | ✅ | ✅ | 🖥️⚡ | ✅ | ✅ | ✅ | ⚠️ |
| `x86_64-macos` | 2 | ✅ | ✅ | 🖥️⚡ | ✅ | ✅ | ✅ | ⚠️ |
| `x86_64-netbsd` | 2 | ✅ | ✅ | 🖥️🛠️ | ✅ | ✅ | ✅ | ✅ |
| `x86_64-openbsd` | 2 | ✅ | ✅ | 🖥️🛠️ | ✅ | ✅ | ✅ | ✅ |
| `x86_64-windows` | 2 | ✅ | ✅ | 🖥️🛠️ | ✅ | ✅ | ✅ | ✅ |
| `aarch64-haiku` | 3 | ✅ | ⚠️ | 🖥️🛠️ | ✅ | ✅ | ❌️ | ❌️ |
| `aarch64-ios` | 3 | ✅ | ✅ | 🖥️🛠️ | ✅ | ✅ | ❌️ | ❌️ |
| `aarch64-serenity` | 3 | ✅ | ⚠️ | 🖥️🛠️ | ✅ | ✅ | ❌️ | ❌️ |
| `aarch64-tvos` | 3 | ✅ | ✅ | 🖥️🛠️ | ✅ | ✅ | ❌️ | ❌️ |
| `aarch64-visionos` | 3 | ✅ | ✅ | 🖥️🛠️ | ✅ | ✅ | ❌️ | ❌️ |
| `aarch64-watchos` | 3 | ✅ | ✅ | 🖥️🛠️ | ✅ | ✅ | ❌️ | ❌️ |
| `arm-haiku` | 3 | ✅ | ⚠️ | 🖥️ | ✅ | ✅ | ❌️ | ❌️ |
| `loongarch32-linux` | 3 | ❔ | ⚠️ | 🖥️ | ✅ | ✅ | ❌️ | ❌️ |
| `mips64(el)-netbsd` | 3 | ✅ | ✅ | 🖥️ | ✅ | ❌️ | ❌️ | ❌️ |
| `riscv64-haiku` | 3 | ✅ | ⚠️ | 🖥️🛠️ | ✅ | ✅ | ❌️ | ❌️ |
| `riscv64-serenity` | 3 | ✅ | ⚠️ | 🖥️🛠️ | ✅ | ✅ | ❌️ | ❌️ |
| `wasm64-wasi` | 3 | ❔ | ❌️ | 🖥️🛠️ | ✅ | ⚠️ | ❌️ | ❌️ |
| `x86-haiku` | 3 | ✅ | ⚠️ | 🖥️ | ✅ | ✅ | ❌️ | ❌️ |
| `x86-illumos` | 3 | ✅ | ⚠️ | 🖥️ | ✅ | ✅ | ❌️ | ❌️ |
| `x86_64-dragonfly` | 3 | ✅ | ✅ | 🖥️🛠️ | ✅ | ✅ | ❌️ | ❌️ |
| `x86_64-haiku` | 3 | ✅ | ⚠️ | 🖥️⚡ | ✅ | ✅ | ❌️ | ❌️ |
| `x86_64-illumos` | 3 | ✅ | ⚠️ | 🖥️🛠️ | ✅ | ✅ | ❌️ | ❌️ |
| `x86_64-serenity` | 3 | ✅ | ⚠️ | 🖥️⚡ | ✅ | ✅ | ❌️ | ❌️ |
| `alpha-linux` | 4 | ❔ | ⚠️ | 📄 | ❌️ | ❌️ | ❌️ | ❌️ |
| `alpha-netbsd` | 4 | ❔ | ✅ | 📄 | ❌️ | ❌️ | ❌️ | ❌️ |
| `alpha-openbsd` | 4 | ❔ | ✅ | 📄 | ❌️ | ❌️ | ❌️ | ❌️ |
| `arc(eb)-linux` | 4 | ❔ | ⚠️ | 📄 | ❌️ | ✅ | ✅ | ❌️ |
| `csky-linux` | 4 | ❔ | ⚠️ | 📄 | ❌️ | ✅ | ✅ | ❌️ |
| `hppa-linux` | 4 | ❔ | ⚠️ | 📄 | ❌️ | ❌️ | ❌️ | ❌️ |
| `hppa-netbsd` | 4 | ❔ | ✅ | 📄 | ❌️ | ❌️ | ❌️ | ❌️ |
| `hppa-openbsd` | 4 | ❔ | ✅ | 📄 | ❌️ | ❌️ | ❌️ | ❌️ |
| `hppa64-linux` | 4 | ❔ | ❌️ | 📄 | ❌️ | ❌️ | ❌️ | ❌️ |
| `m68k-haiku` | 4 | ❔ | ⚠️ | 🖥️ | ❌️ | ✅ | ❌️ | ❌️ |
| `m68k-linux` | 4 | ❔ | ✅ | 🖥️ | ❌️ | ✅ | ✅ | ❌️ |
| `m68k-netbsd` | 4 | ❔ | ✅ | 🖥️ | ❌️ | ✅ | ✅ | ❌️ |
| `m88k-openbsd` | 4 | ❔ | ❌️ | 📄 | ❌️ | ❌️ | ❌️ | ❌️ |
| `microblaze(el)-linux` | 4 | ❔ | ⚠️ | 📄 | ❌️ | ❌️ | ❌️ | ❌️ |
| `or1k-linux` | 4 | ❔ | ✅ | 📄 | ❌️ | ✅ | ❌️ | ❌️ |
| `sh(eb)-linux` | 4 | ❔ | ⚠️ | 📄 | ❌️ | ❌️ | ❌️ | ❌️ |
| `sh(eb)-netbsd` | 4 | ❔ | ✅ | 📄 | ❌️ | ❌️ | ❌️ | ❌️ |
| `sh-openbsd` | 4 | ❔ | ✅ | 📄 | ❌️ | ❌️ | ❌️ | ❌️ |
| `sparc-linux` | 4 | ❔ | ⚠️ | 🖥️ | ❌️ | ✅ | ✅ | ❌️ |
| `sparc-netbsd` | 4 | ❔ | ✅ | 🖥️ | ❌️ | ❌️ | ✅ | ❌️ |
| `sparc64-haiku` | 4 | ❔ | ⚠️ | 🖥️🛠️ | ⚠️ | ❌️ | ❌️ | ❌️ |
| `sparc64-linux` | 4 | ❔ | ✅ | 🖥️🛠️ | ⚠️ | ✅ | ✅ | ❌️ |
| `sparc64-netbsd` | 4 | ❔ | ✅ | 🖥️🛠️ | ⚠️ | ❌️ | ✅ | ❌️ |
| `sparc64-openbsd` | 4 | ❔ | ✅ | 🖥️🛠️ | ⚠️ | ❌️ | ✅ | ❌️ |
| `xtensa(eb)-linux` | 4 | ❔ | ❌️ | 📄 | ❌️ | ❌️ | ❌️ | ❌️ |


## OS Version Requirements


The Zig standard library has minimum version requirements for some
supported operating systems, which in turn affect the Zig compiler itself.


| Operating System | Minimum Version |
| --- | --- |
| DragonFly BSD | 6.0 |
| FreeBSD | 14.0 |
| Linux | 5.10 |
| NetBSD | 10.1 |
| OpenBSD | 7.8 |
| macOS | 13.0 |
| Windows | 10 |


## Additional Platforms


Zig also has varying levels of support for these targets, for which the
tier system does not quite apply:


- `aarch64-driverkit`


- `aarch64[_be]-freestanding`


- `aarch64-fuchsia`


- `aarch64-hurd`


- `aarch64-uefi`


- `alpha-freestanding`


- `amdgcn-amdhsa`


- `amdgcn-amdpal`


- `amdgcn-mesa3d`


- `arc[eb]-freestanding`


- `arm[eb]-freestanding`


- `arm-3ds`


- `arm-fuchsia`


- `arm-uefi`


- `arm-vita`


- `avr-freestanding`


- `bpf(eb,el)-freestanding`


- `csky-freestanding`


- `hexagon-freestanding`


- `hppa[64]-freestanding`


- `kalimba-freestanding`


- `kvx-freestanding`


- `lanai-freestanding`


- `loongarch(32,64)-freestanding`


- `loongarch(32,64)-uefi`


- `m68k-freestanding`


- `microblaze[el]-freestanding`


- `mips[64][el]-freestanding`


- `mipsel-psp`


- `msp430-freestanding`


- `nvptx[64]-cuda`


- `nvptx[64]-nvcl`


- `or1k-freestanding`


- `powerpc[64][le]-freestanding`


- `powerpc64-ps3`


- `propeller-freestanding`


- `riscv(32,64)[be]-freestanding`


- `riscv(32,64)-uefi`


- `riscv64-fuchsia`


- `s390x-freestanding`


- `sh[eb]-freestanding`


- `sparc[64]-freestanding`


- `spirv(32,64)-opencl`


- `spirv(32,64)-opengl`


- `spirv(32,64)-vulkan`


- `thumb[eb]-freestanding`


- `thumb-fuchsia`


- `ve-freestanding`


- `wasm(32,64)-emscripten`


- `wasm(32,64)-freestanding`


- `x86[_16,_64]-freestanding`


- `x86[_64]-hurd`


- `x86[_64]-uefi`


- `x86_64-driverkit`


- `x86_64-fuchsia`


- `x86_64-plan9`


- `x86_64-ps4`


- `x86_64-ps5`


- `xcore-freestanding`


- `xtensa[eb]-freestanding`


## Language Changes


## switch


packed struct and packed union may now be used as switch prong items. They are
compared solely based on their backing integer, just like in equality comparisons:


Other newly implemented features:


- decl literals and everything else requiring a result type (e.g. @enumFromInt) may now be used as switch prong items


- union tag captures are now allowed for all prongs, not just inline ones


- switch prongs may contain errors which are not in the error set being switched on, if these prongs contain => comptime unreachable


- switch prong captures may no longer all be discarded


Bug fixes:


- lots of issues with switching on one-possible-value types are now fixed


- the rules around unreachable else prongs when switching on errors now apply to any switch on an error, not just to switch_block_err_union, and are applied properly based on the AST


- switching on void no longer requires an else prong unconditionally


- lazy values are properly resolved before any comparisons with prong items


- evaluation order between all kinds of switch statements is now the same, with or without label


## Equality Comparisons on Packed Unions


This used to already be possible by wrapping the packed union into
a packed struct. Now it's also possible without having to do that.


## @cImport Moving to Build System


In the future, [C Translation](#C Translation) will be handled via the
[Build System](#Build System) rather than the @cImport
language builtin, which is now deprecated.


Upgrade guide:


pub const c = @cImport({
@cInclude("stdio.h");
@cInclude("math.h");
@cInclude("time.h");
@cInclude("stdlib.h");
@cInclude("epoxy/gl.h");
@cInclude("GLFW/glfw3.h");
});


⬇️

#include 
#include 
#include 
#include 
#include 
#include 


const translate_c = b.addTranslateC(.{
.root_source_file = b.path("src/c.h"),
.target = target,
.optimize = optimize,
});
translate_c.linkSystemLibrary("glfw", .{});
translate_c.linkSystemLibrary("epoxy", .{});

const exe = b.addExecutable(.{
.name = "tetris",
.root_module = b.createModule(.{
.root_source_file = b.path("src/main.zig"),
.optimize = optimize,
.target = target,
.imports = &.{
.{
.name = "c",
.module = translate_c.createModule(),
},
},
}),
});


By doing this, the translated C code will be identical to how it was before with
@cImport.


Alternately, you can add
[the official translate-c package](https://codeberg.org/ziglang/translate-c)
as an explicit dependency and gain access to more
[translation customization options](https://codeberg.org/ziglang/translate-c/src/commit/41c10fa66ac81343c33f2b8c746f181b41eaaa27/build/Translator.zig#L40).


## @Type Replaced with Individual Type-Creating Builtin Functions


Zig 0.16.0 implements long-accepted proposal [#10710](https://github.com/ziglang/zig/issues/10710) to remove the
@Type builtin from the language and replace it with individual builtins
like @Int and @Struct. While @Type is a simple parallel to
@typeInfo, in practice, it was clunky to use for common tasks, leading
users to reach for helpers like std.meta.Int. Ignoring @Vector, which
already existed, @Type has been replaced with 8 new builtin
functions:


#### Enum Literal

@EnumLiteral() returns the "enum literal" type, which is the type of uncoerced enum literals like .foo. While it is equivalent to @TypeOf(.something), the new @EnumLiteral() is preferred for consistency.


⬇️


#### Integer

@Int is perhaps the most useful new builtin for simple metaprogramming. The usage is equivalent to the now-deprecated std.meta.Int helper: given a signedness and bit count, it returns an integer type with those properties. This new usage results in significantly more concise and readable code.


⬇️


#### Tuple

@Tuple is equivalent to the now-deprecated std.meta.Tuple helper. It accepts a slice of types, and returns a tuple type whose fields have those types.


⬇️


To simplify the language, it is no longer possible to reify tuple types with comptime fields.


#### Pointer

@Pointer returns a pointer type, equivalent to @Type(.{ .pointer = ... }). Notably, it uses the new std.builtin.Type.Pointer.Attributes type, which uses struct field default values to make the usage more concise and more closely aligned with literal pointer type syntax.


⬇️


⬇️


#### Function

@Fn returns a function type, equivalent to @Type(.{ .@"fn" = ... }). Like for pointers, new helper types have been introduced to make this builtin simpler to use. Parameters are specified with two separate arguments: the first specifies all parameter types, and the second specifies "attributes" (which currently consist only of the noalias flag).


⬇️


This is one of several of the new builtins which accepts arguments in a "struct of arrays" style. An advantage of this style is that it makes it easy to specify a fixed value for all elements. For instance, to use the "default" attributes .{} for all parameters, use &@splat(.{}):


#### Struct

@Struct returns a struct type, equivalent to @Type(.{ .@"struct" = ... }). Like @Fn, it uses a "struct of arrays" strategy to pass information about fields. Fields are passed as three separate arrays—field names, field types, and field attributes—where the latter includes alignment, the comptime flag, and the field's default value (if any).


⬇️


Again, &@splat(.{}) is useful for specifying "default" field attributes. In some cases, it is even useful to use @splat for the field types. For instance, to create a struct with homogeneous field types of FieldType where the field names match the names of an enum type MyEnum:


#### Union

@Union returns a union type, equivalent to @Type(.{ .@"union" = ... }). It is quite similar to @Struct in usage.


⬇️


#### Enum

@Enum returns an enum type, equivalent to @Type(.{ .@"enum" = ... }). It is somewhat similar to @Struct in usage, but accepts an array of field *tag values* rather than field *types*.


⬇️


#### Float

There is no @Float builtin, because there are only 5 runtime floating-point types, so this functionality is trivially implemented in userland. The function std.meta.Float can be used if creating float types from a bit count is required.


#### Array

There is no @Array builtin, because this functionality is trivial to implement with normal array syntax. A general Array function would look like this:


In practice, this generality is not usually necessary, and use sites can simply be replaced with one of [len]Elem or [len:s]Elem.


#### Opaque

There is no @Opaque builtin. Instead, write opaque {}.


#### Optional

There is no @Optional builtin. Instead, write ?T.


#### Error Union

There is no @ErrorUnion builtin. Instead, write E!T.


#### Error Set

There is no @ErrorSet builtin. To simplify the language, it is no longer possible to reify error sets. Instead, declare your error sets explicitly using error{ ... } syntax.


## Allow Small Integer Types to Coerce to Floats


If all possible values of an integer type can fit in a floating point type without rounding, the integer may coerce to the float without an explicit conversion. This is determined by comparing the number of bits of precision in the integer type and the significand in the floating point type. Larger integer types will still require @floatFromInt.


⬇️


This is part of a larger effort to improve ergonomics for making video games in Zig.


## Forbid Runtime Vector Indexes


Upgrade guide:


⬇️


This was changed as part of [Reworked Byval Syntax Lowering](#Reworked Byval Syntax Lowering).


## Vectors and Arrays No Longer Support In-Memory Coercion


If you were using @ptrCast to convert between array memory and vector memory, use coercion instead.


If you were coercing from anyerror![4]i32 to anyerror!@Vector(4, i32) or similar, you need to unwrap the error first.


## Forbid Trivial Local Address Returned from Functions


One thing that Zig beginners struggle with - particularly those
unfamiliar with manual memory management - is returning pointers to local variables from functions.


This is challenging to address, because it is legal to return an invalid pointer:


This is a perfectly valid function - the illegal operation only occurs if the returned pointer
is dereferenced. Even then, it's legal to have a function that unconditionally invokes illegal behavior:


Given this function, the expression bar() is equivalent to the expression unreachable.


So how then, can we make it a compile error to return an invalid pointer from a function?
Syntactic pedantry. We forbid all expressions that trivially (i.e. without type checking) lower to
return undefined with the justification that the expression should instead be
written canonically as return undefined.


Thus the following compile error was born:


``


[More compile errors of this nature are planned.](https://github.com/ziglang/zig/issues/25312)


## Unary Float Builtins Forward Result Type


Previously Zig would not forward a result type through the following builtin functions,


This has now been changed. Where previous you couldn't write,


since @sqrt would not forward the f64 result type to @floatFromInt, now you can.


This is part of a larger effort to improve ergonomics for making video games in Zig.


## @floor, @ceil, @round, @trunc Conversion to Integers


@floor, @ceil,
@round, and @trunc now can be used
to convert a floating-point value to an integer value:


@intFromFloat is now redundant with @trunc and is
therefore deprecated.


This is part of a larger effort to improve ergonomics for making video games in Zig.


## Forbid Unused Bits in Packed Unions


There was not plainly one possible way of mapping packed union
representation to bits, a desirable feature of other packed types. For
example, enum (u5) { ... } plainly represents 5 bits
in an obvious manner and is allowed in packed contexts, but ?u8 has two
reasonable ways of mapping to 9 bits and is therefore not allowed in packed contexts.


This ambiguity is resolved by requiring all fields of a packed union to have the same @bitSizeOf as a backing integer type.


Upgrade guide:


⬇️


## Forbid Pointers in Packed Structs and Unions


Fields of packed struct and packed union types
are no longer permitted to be pointers, implementing proposal
[#24657](https://github.com/ziglang/zig/issues/24657).


The primary reason for this change is that constant values containing non-byte-aligned
pointers cannot be represented in the vast majority of binary formats. Additionally, there are
some targets on which pointers cannot be represented merely as their address bits, but have
additional metadata bits too—in this case it does not make sense to pack pointers into an
integer, as packed types purport to do.


If you were relying on pointers in packed types, you can instead use a
usize field and convert to and from a pointer using
@ptrFromInt and @intFromPtr.


## Allow Explicit Backing Integers on Packed Unions


Although previous versions of Zig allowed packed struct types to
specify their backing integer type with the syntax packed struct(T), this
was not previously permitted for packed union types. In Zig 0.16.0, this
has now been allowed.


Note that due to [Forbid Enum and Packed Types with Implicit Backing Types in Extern Contexts](#Forbid Enum and Packed Types with Implicit Backing Types in Extern Contexts),
specifying a backing type like this is sometimes required.


## Forbid Enum and Packed Types with Implicit Backing Types in Extern Contexts


enum types with inferred integer tag types, and
packed struct and packed union types with inferred
integer backing types, are no longer considered valid extern types. This
implements proposal [#24714](https://github.com/ziglang/zig/issues/24714).


This breaking change was made to avoid the ABI of a type being determined entirely implicitly
based solely on its fields. In particular, this matters because u8 and
i8 may have differing ABIs in some contexts, and it is not clear which
is being used if the choice is implicit.


If this has introduced a compile error in your code, resolve it by adding an explicit tag
type or backing type. (See [Allow Explicit Backing Integers on Packed Unions](#Allow Explicit Backing Integers on Packed Unions) for a
related language change in Zig 0.16.0.)


⬇️


## Lazy Field Analysis


A problem we noticed since introducing [I/O as an Interface](#I/O as an Interface) is
that if a type is used as a namespace, its fields will be analyzed anyway.
For instance, using std.Io.Writer in any way pulls in the vtable of
std.Io. Some cases of this could even result in unnecessary codegen,
which can bloat binaries.


Now, struct (reminder that files are structs), union, enum, and opaque are only
resolved when its size or the type of one of its fields is required. This
means that not only can you use types as namespaces without referencing
them, but you can even use non-dereferenced pointers *T without needing
T to be resolved.


This was changed as part of [Reworked Type Resolution](#Reworked Type Resolution).


## Pointers to Comptime-Only Types Are No Longer Comptime-Only


For instance, though comptime_int is a comptime-only type,
*comptime_int is not, and neither is []comptime_int. This may seem
confusing at first—the easiest way to understand it is to consider
function pointers. The type *const fn () void is a runtime type. However,
you are not allowed to dereference it at runtime, because the element
type (the function body type fn () void) is comptime-only. So these
pointers can exist at runtime, but may only be dereferenced at
compile-time. This makes them more-or-less useless at runtime—but there's
actually an exception to that! Suppose you have a
[]const std.builtin.Type.StructField, and you want to pass the name of each
field to runtime code somehow. Previously, you would have done this by
constructing a separate []const []const u8. However, now, you can pass
the []const std.builtin.Type.StructField directly to a runtime function.
Naturally, this function cannot load a StructField from this slice at
runtime. However, what it can do is load the name field, because it
has a runtime type!


This was changed as part of [Reworked Type Resolution](#Reworked Type Resolution).


## Explicitly-Aligned Pointer Types Now Distinct from Naturally-Aligned Pointer Types


Previously, *u8 and *align(1) u8 were considered by Zig to be literally
the same type; they would compare equal, and *u8 was considered the
canonical spelling (it's what the compiler would print).
Now, those two types are no longer considered equivalent.


Crucially, the two types can still be used interchangeably. They coerce
to one another, even through pointers (what the compiler calls "in-memory
coercions"), and in almost every case there is no need to care which one
you have. You could think of this difference as being like the difference
between u32 and c_uint: technically they are different types, but
(assuming your target has 32-bit int) they act identically for all
intents and purposes, and it doesn't technically matter which one you
pick.


This was changed as part of [Reworked Type Resolution](#Reworked Type Resolution).


## Simplified Dependency Loop Rules


There are new cases which are now dependency loops when they previously
were not.


However, it's now more obvious why a dependency loop exists due to simplified
type checking rules and enhanced compile errors. This also reduces the difficulty
of formally specifying the Zig language.


This was changed as part of [Reworked Type Resolution](#Reworked Type Resolution).


## Zero-bit Tuple Fields No Longer Implicitly comptime


Back in 0.14.0, a rule was unintentionally introduced that tuple fields
with zero-bit types are implicitly promoted to comptime fields:


Zig 0.16.0 reverts this change: the above tuple field is no longer considered a comptime field. However, this does *not* prevent the field value from always being comptime-known:

In other words, this change is almost entirely non-breaking. The only case where it could affect old code is if you were directly relying on std.builtin.StructField.is_comptime from @typeInfo, or on the equivalence of tuples with and without explicitly declared comptime  fields:


## Standard Library


Added:


- Io.Dir.renamePreserve: rename operation without replacing the destination file


- Io.net.Socket.createPair


Removed:


- SegmentedList


- meta.declList


- Io.GenericWriter


- Io.AnyWriter


- Io.null_writer


- Io.CountingReader


- Thread.Mutex.Recursive


Error set changes:


- error.RenameAcrossMountPoints ➡️ error.CrossDevice


- error.NotSameFileSystem ➡️ error.CrossDevice


- error.SharingViolation ➡️ error.FileBusy


- error.EnvironmentVariableNotFound ➡️ error.EnvironmentVariableMissing


- std.Io.Dir.rename returns error.DirNotEmpty rather than error.PathAlreadyExists


Uncategorized changes:


- fmt: Formatter ➡️ Alt


- fmt: format ➡️ std.Io.Writer.print


- fmt: FormatOptions ➡️ Options


- fmt: bufPrintZ ➡️ bufPrintSentinel


- compress: lzma, lzma2, and xz updated to Io.Reader / Io.Writer


- DynLib: removed Windows support. Now users must use LoadLibraryExW and GetProcAddress directly, which is probably what they were already doing anyway.


- math.sign: return smallest integer type that fits possible values


- Trigger automatic fetching of root certificates on Windows


- tar.extract: sanitize path traversal


- BitSet, EnumSet: replace initEmpty, initFull with decl literals


## I/O as an Interface


Starting with Zig 0.16.0, all input and output functionality requires
being passed an Io instance. Generally, anything
that potentially blocks control flow or
introduces nondeterminism is grounds for being owned by the I/O interface.


Along with the interface, this release comes with the following implementations:


- Io.Threaded - based on threads. With this
implementation, I/O operations are straightforward. For example, [File System](#File System)
operations directly call read, write, open, close, etc. When updating
code from Zig 0.15.x, using this implementation provides the equivalent
behavior. This implementation is feature-complete and well-tested,
including [Cancelation](#Cancelation). This is the implementation currently chosen by
["Juicy Main"](#"Juicy Main").


- -fno-single-threaded - supports task-level concurrency and cancelation.


- -fsingle-threaded - does not support task-level concurrency or cancelation.


- Io.Evented - work-in-progress, experimental,
serving to inform the evolution of the interface. This implementation is
based on userspace stack switching with work stealing, also known as M:N
threading, "green threads", or stackful coroutines.


- Io.Uring - although it was not the
focus of this release cycle, there is already a proof-of-concept
implementation based on Linux's excellent io_uring API. This backend
has really nice properties but it's not finished yet. It's lacking
[Networking](#Networking), error handling, test coverage, and minimal task
stack allocations.


- Io.Kqueue - proof-of-concept only, enough to fix
[a common bug in
other async runtimes](https://github.com/mitchellh/libxev/issues/125).


- Io.Dispatch - based on Grand Central Dispatch (macOS).


- Io.failing - simulates a system supporting no operations.


Overview:


- [Future](#Future) - task-level abstraction based on functions. Allows introducing
operational independence (asynchrony) among any set of function calls.


- [Group](#Group) - efficiently manages many independent tasks. Supports awaiting and
[canceling](#Cancelation) all tasks in the group together.


- Queue(T) - many producer, many consumer, thread-safe, runtime configurable
buffer size. When buffer is empty, consumers suspend and are resumed by
producers. When buffer is full, producers suspend and are resumed by consumers.


- Select - executes tasks together, providing a mechanism to wait until one or more tasks complete. Similar to [Batch](#Batch) but operates at the higher level task abstraction layer rather than lower level Operation abstraction layer.


- [Batch](#Batch) - lower level abstraction based on introducing independence among any set of operations.


- Clock, Duration, Timestamp, Timeout - type safety for units of measurement


Demo of making an HTTP request to a domain:


Thanks to the fact that networking is now taking advantage of the new
std.Io interface, this code has the following properties:


- It asynchronously sends out DNS queries to each configured nameserver.


- As each response comes in, it immediately, asynchronously tries to TCP connect to the
returned IP address.


- Upon the first successful TCP connection, all other in-flight connection
attempts are [canceled](#Cancelation), including DNS queries.


- The code also works when compiled with -fsingle-threaded even though the
operations happen sequentially.


- [On Windows, this all happens without ws2_32.dll dependency.](#Windows Networking Without ws2_32.dll)


init: std.process.Init is thanks to ["Juicy Main"](#"Juicy Main").


When upgrading code, if you find yourself without access to an Io instance,
you can get one like this:


This works as long as you don't need task-level concurrency, however, it
is a non-ideal workaround - like reaching for std.heap.page_allocator
when you need an Allocator and do not have one. Instead, it is better to
accept an Io parameter if you need one (or store one on a context struct
for convenience). Point is that the application's main function should
generally be responsible for constructing the Io instance used
throughout.


When testing, it is recommended to use
std.testing.io (much like
std.testing.allocator).


## Future


Futures are a task-level abstraction based on functions.


io.async creates a
Future(T) where T is the
return type of the callee. async expresses
asynchrony: that the function call is independent from
other logic. Creating such a task is therefore infallible and portable
across limited Io implementations including
those which lack a concurrency mechanism. It is legal for
Io implementations to implement
async calls simply by directly calling the function before
returning.


io.concurrent is the same as
io.async except communicates that the operation
must be done concurrently for correctness. This necessarily
requires memory allocation because that is the nature of doing things simultaneously.
This function can therefore fail with error.ConcurrencyUnavailable.


In both cases, a Future(T) is created. This struct has two methods:


- await - logically blocks control flow until the task completes, returning
the return value of the function.


- cancel - equivalent to await
except also requests the Io implementation to
interrupt the operation and return error.Canceled. Most
I/O operations now have error.Canceled in their error sets.


Use this pattern to avoid resource leaks and handle [Cancelation](#Cancelation) gracefully:


If the foo or bar function
does not return a resource that must be freed, then the
if can be simplified to _ = foo.cancel(io) catch
{}, and if the function returns void,
then the discard can also be removed. The cancel is
necessary however because it releases the async task resource when errors
(including error.Canceled) are returned.


## Group


Groups are appropriate when many tasks share the same lifetime. They offer a
O(1) overhead for spawning N tasks.


## Cancelation


Lo! Lest one learn a lone release lesson, let proclaim: "cancelation"
should seriously only be spelt thusly (single "l"). Let not evil, godless
liars lead afoul.


In the same vein as breaking out of a for loop early, once you start
doing multiple tasks concurrently, you start running into situations where one
task having completed, for example by failing, means that you would like to
interrupt other ongoing tasks since their results and/or side-effects are
already known not to matter - or perhaps even require being reversed.


[Future](#Future), [Group](#Group), and [Batch](#Batch) APIs all support
requesting cancelation. When cancelation is requested, the request may or
may not be acknowledged. Acknowledged cancelation requests cause I/O operations
to return error.Canceled. Even
Io.Threaded supports cancelation by sending a signal
to a thread, causing blocking syscalls to return
EINTR, and responding to that error code by checking
for a cancelation request before retrying the syscall.


Only the logic that made the cancelation request can soundly ignore
an error.Canceled. Otherwise, there are three ways to
handle error.Canceled. In order of most common:


- Propagate it.


- After receiving it, io.recancel() and then don't propagate it. This rearms
the cancelation request, so that the next check will have a chance to detect and acknowledge the request.


- Make it unreachable with io.swapCancelProtection().


In general, cancelation is equivalent to awaiting, aside from the request to cancel. This means you can
still receive the return value from the task - which may in fact have completed successfully
despite the request. In this case, the side effects, such as resource allocation,
should be accounted for. Here is an example of opening a file and then immediately canceling the
task. Note that we must account for the possibility that the file succeeds in being opened.


Typically, since both await and cancel are idempotent,
the most useful pattern is to defer a cancelation after creating a task.
This ensures the resources, including the concurrent tasks, are deallocated before returning
from the function.


Generally, Zig programmers don't need to explicitly add code to support
cancelation, because error.Canceled is baked into
the error sets of all the cancelable I/O operations. However, one can add
additional cancelation points by calling
io.checkCancel. It is rarely necessary to call this
function. The primary use case is in long-running CPU-bound tasks which may
need to respond to cancelation before completing.


## Batch


You can think of Batch as a low level concurrency
mechanism which provides concurrency at an Operation
layer, which is efficient and portable, but more difficult to abstract
around, particularly if you need to run some logic in between
operations.


Eventually most of the [File System](#File System) and [Networking](#Networking)
functionality are expected to migrate to become based on
Operation, making them eligible to be used with
Batch, and eligible to be used with operateTimeout,
which provides a general way to add a timeout to any I/O operation.


Currently the list is:


- FileReadStreaming


- FileWriteStreaming


- DeviceIoControl


- NetReceive


Meanwhile [Future](#Future) is the equivalent but at a function
abstraction layer, which is flexible and ergonomic, but it allocates task
memory and error.ConcurrencyUnavailable (when using
concurrent), or unwanted blocking operations (when
using async), can occur in more circumstances than
the lower level Batch APIs.


So, generally, if you're trying to write optimal, reusable software,
Batch is the way to go if you simply need to do
several operations at once, otherwise, you can always use the
[Future](#Future) APIs if that would essentially require you to reinvent
futures. Or you can start with [Future](#Future) APIs and then optimize by
reworking some stuff to use Batch later if reducing
task overhead is desirable.


## Sync Primitives


Sync APIs must be migrated to use the new std.Io APIs so that the code
being synchronized can integrate correctly with the application's chosen
I/O implementation. This will ensure, for example, when using std.Io.Threaded,
a contended mutex lock will block the thread, while when using std.Io.Evented,
it will switch stacks.


These APIs also integrate properly with [Cancelation](#Cancelation).


- std.Thread.ResetEvent ➡️ std.Io.Event


- std.Thread.WaitGroup ➡️ std.Io.Group


- std.Thread.Futex ➡️ std.Io.Futex


- std.Thread.Mutex ➡️ std.Io.Mutex


- std.Thread.Condition ➡️ std.Io.Condition


- std.Thread.Semaphore ➡️ std.Io.Semaphore


- std.Thread.RwLock ➡️ std.Io.RwLock


- std.once removed; avoid global variables, or hand-roll the logic yourself


Notably, lock-free sync primitives do not require std.Io integration.


## Entropy


Upgrade guide:


std.crypto.random.bytes


⬇️


std.crypto.random (std.Random interface)


⬇️


posix.getrandom


⬇️


std.Options.crypto_always_getrandom and std.Options.crypto_fork_safety


Rather than these being std wide options, they are two different std.Io APIs:


So if you want to keep CSPRNG state out of your process memory, call
Io.randomSecure rather than Io.random.


## Time


This release adds the ability to get clock resolution, which may fail.
This allows error.Unexpected and
error.ClockUnsupported to be removed from timeout
and clock reading error sets because they can be treated as having a
resolution of infinite, which is detectable by the user by separately
(beforehand) calling Clock.resolution.


Upgrade guide:


- std.time.Instant ➡️ std.Io.Timestamp


- std.time.Timer ➡️ std.Io.Timestamp


- std.time.timestamp ➡️ std.Io.Timestamp.now


## File System


All fs APIs are migrated to Io.


Although it's a lot of breaking changes, unlike
["writergate"](https://ziglang.org/download/0.15.1/release-notes.html#Writergate),
this changeset is expected to be generally easy for Zig programmers to
manage, because it does not require much critical thinking. For example,
typical upgrade path will look something like this:


⬇️


Although your upgrade diff might be large, it will be quite simple to understand what needs to be done.


Added:


- Io.Dir.hardLink


- Io.Dir.Reader


- Io.Dir.setFilePermissions


- Io.Dir.setFileOwner


- Io.File.NLink


Removed with no replacement:


- fs.realpathZ


- fs.realpathW


- fs.realpathW2


- fs.makeDirAbsoluteZ


- fs.deleteDirAbsoluteZ


- fs.openDirAbsoluteZ


- fs.renameAbsoluteZ


- fs.renameZ


- fs.deleteTreeAbsolute


- fs.symLinkAbsoluteW


- fs.Dir.realpathZ


- fs.Dir.realpathW


- fs.Dir.realpathW2


- fs.Dir.deleteFileZ


- fs.Dir.deleteFileW


- fs.Dir.deleteDirZ


- fs.Dir.deleteDirW


- fs.Dir.renameZ


- fs.Dir.renameW


- fs.Dir.symLinkWasi


- fs.Dir.symLinkZ


- fs.Dir.symLinkW


- fs.Dir.readLinkWasi


- fs.Dir.readLinkZ


- fs.Dir.readLinkW


- fs.Dir.adaptToNewApi


- fs.Dir.adaptFromNewApi


- fs.File.isCygwinPty


- fs.File.adaptToNewApi


- fs.File.adaptFromNewApi


Changed:


- fs.copyFileAbsolute ➡️ std.Io.Dir.copyFileAbsolute


- fs.makeDirAbsolute ➡️ std.Io.Dir.createDirAbsolute


- fs.deleteDirAbsolute ➡️ std.Io.Dir.deleteDirAbsolute


- fs.openDirAbsolute ➡️ std.Io.Dir.openDirAbsolute


- fs.openFileAbsolute ➡️ std.Io.Dir.openFileAbsolute


- fs.accessAbsolute ➡️ std.Io.Dir.accessAbsolute


- fs.createFileAbsolute ➡️ std.Io.Dir.createFileAbsolute


- fs.deleteFileAbsolute ➡️ std.Io.Dir.deleteFileAbsolute


- fs.renameAbsolute ➡️ std.Io.Dir.renameAbsolute


- fs.readLinkAbsolute ➡️ std.Io.Dir.readLinkAbsolute


- fs.symLinkAbsolute ➡️ std.Io.Dir.symLinkAbsolute


- fs.has_executable_bit ➡️ std.Io.File.Permissions.has_executable_bit


- fs.realpath ➡️ std.Io.Dir.realPathFileAbsolute


- fs.rename ➡️ std.Io.Dir.rename


- fs.cwd ➡️ std.Io.Dir.cwd


- fs.defaultWasiCwd ➡️ std.os.defaultWasiCwd


- fs.realpathAlloc ➡️ std.Io.Dir.realPathFileAbsoluteAlloc


- fs.openSelfExe ➡️ std.process.openExecutable


- fs.selfExePathAlloc ➡️ std.process.executablePathAlloc


- fs.selfExePath ➡️ std.process.executablePath


- fs.selfExeDirPath ➡️ std.process.executableDirPath


- fs.selfExeDirPathAlloc ➡️ std.process.executableDirPathAlloc


- fs.Dir.setAsCwd ➡️ std.process.setCurrentDir


- fs.Dir.realpath ➡️ std.Io.Dir.realPathFile


- fs.Dir.realpathAlloc ➡️ std.Io.Dir.realPathFileAlloc


- fs.Dir ➡️ std.Io.Dir


- fs.File ➡️ std.Io.File


- fs.Dir.makeDir ➡️ std.Io.Dir.createDir


- fs.Dir.makePath ➡️ std.Io.Dir.createDirPath


- fs.Dir.makeOpenDir ➡️ std.Io.Dir.createDirPathOpen


- fs.Dir.rename: now accepts two Dirparameters (plus Io)


- fs.Dir.atomicSymLink ➡️ std.Io.Dir.symLinkAtomic


- fs.Dir.chmod ➡️ std.Io.Dir.setPermissions


- fs.Dir.chown ➡️ std.Io.Dir.setOwner


- fs.File.Mode ➡️ std.Io.File.Permissions


- fs.File.PermissionsWindows ➡️ std.Io.File.Permissions


- fs.File.PermissionsUnix ➡️ std.Io.File.Permissions


- fs.File.default_mode ➡️ std.Io.File.Permissions.default_file


- fs.File.getOrEnableAnsiEscapeSupport ➡️ std.Io.File.enableAnsiEscapeCodes


- fs.File.setEndPos ➡️ std.Io.File.setLength


- fs.File.getEndPos ➡️ std.Io.File.length


- fs.File.seekTo, std.fs.File.seekBy, std.fs.File.seekFromEnd ➡️ std.Io.File.Reader.seekTo, std.Io.File.Reader.seekBy, std.Io.File.Writer.seekTo


- fs.File.getPos ➡️ std.Io.File.Reader.logicalPos, std.Io.Writer.logicalPos


- fs.File.mode ➡️ std.Io.File.stat().permissions.toMode


- fs.File.chmod ➡️ std.Io.File.setPermissions


- fs.File.chown ➡️ std.Io.File.setOwner


- fs.File.updateTimes ➡️ std.Io.File.setTimestamps, std.Io.File.setTimestampsNow


- fs.File.read ➡️ std.Io.File.readStreaming


- fs.File.readv ➡️ std.Io.File.readStreaming


- fs.File.pread ➡️ std.Io.File.readPositional


- fs.File.preadv ➡️ std.Io.File.readPositional


- fs.File.preadAll ➡️ std.Io.File.readPositionalAll


- fs.File.write ➡️ std.Io.File.writeStreaming


- fs.File.writev ➡️ std.Io.File.writeStreaming


- fs.File.pwrite ➡️ std.Io.File.writePositional


- fs.File.pwritev ➡️ std.Io.File.writePositional


- fs.File.writeAll ➡️ std.Io.File.writeStreamingAll


- fs.File.pwriteAll ➡️ std.Io.File.writePositionalAll


- fs.File.copyRange, std.fs.File.copyRangeAll ➡️ std.Io.File.writer


Many functions now have an Io parameter.


Deprecated:


- fs.path ➡️ std.Io.Dir.path


- fs.max_path_bytes ➡️ std.Io.Dir.max_path_bytes


- fs.max_name_bytes ➡️ std.Io.Dir.max_name_bytes


## Networking


All net APIs are migrated to Io.


[Io.Evented does not yet implement networking.](https://codeberg.org/ziglang/zig/issues/31723)


[Io.net currently lacks a way to do non-IP networking.](https://codeberg.org/ziglang/zig/issues/30892)


## Process


Spawning a child process:


⬇️


Running a child process and capturing its output:


⬇️


Replacing current process image:


⬇️


## File.MemoryMap


The pointer contents are defined to only be synchronized after explicit
sync points, making it legal to have a fallback implementation based on file
operations while still supporting a handful of use cases for memory
mapping.


Furthermore, it makes it legal for evented I/O implementations to use
evented file I/O for the sync points rather than memory mapping.


Technically this is a breaking change because the positional
file reading and writing error sets are more constrained. Also on WASI, you now get
error.IsDir correctly instead of error.NotOpenForReading.


## posix and os.windows removals


Most std.posix and
std.os.windows functions existed at an awkward
medium-level abstraction and have thus been removed.
Therefore, if you were using any functions removed from those namespaces,
you must now choose a direction:


- Go higher: use std.Io


- Go lower: use std.posix.system directly


[More removals are planned](https://codeberg.org/ziglang/zig/issues/31694).


## heap.ArenaAllocator Becomes Thread-Safe and Lock-Free


Lock-free and thread-safe plays better with [std.Io integration](#I/O as an Interface) and
libc integration. By avoiding locks, we avoid needing [Sync Primitives](#Sync Primitives) and thereby
avoid needing an Io instance, and also allow the Allocator to be
used as the backing allocator for an Io instance.


The new implementation offers comparable performance to the previous one
when only being accessed by a single thread and a slight speedup compared
to the previous implementation wrapped into a ThreadSafeAllocator up to ~7
threads performing operations on it concurrently.


[more details](https://codeberg.org/ziglang/zig/pulls/31320)


[same thing is planned for heap.DebugAllocator](https://codeberg.org/ziglang/zig/issues/31186)


## heap.ThreadSafe Allocator Removed


The only reasonable way to implement ThreadSafeAllocator, which wraps
an underlying Allocator, is with a mutex, which necessarily requires an
Io instance and is generally inefficient. Meanwhile, essentially every
Allocator in which thread safety is desired, can be adjusted to be lock
free and avoid slow, blocking mutexes altogether - or at least in some of
the hot paths! ThreadSafeAllocator is an anti-pattern. This is a situation
when tighter coupling is called for.


## Add Deflate Compression, Simplify Decompression


Adds deflate compression, implemented from scratch. A history window is
kept in the writer's buffer for matching and a chained hash table is used
to find matches. Tokens are accumulated until a threshold is reached and
then outputted as a block.


Additionally, two other deflate writers are provided:


- Raw writes only in store blocks (the uncompressed bytes). It utilizes data vectors to efficiently send block headers and data.


- Huffman only performs Huffman compression on data and no matching.


The above are also able to take advantage of writer semantics since they do not need to keep a history.


Literal and distance code parameters in token have also been reworked.
Their parameters are now derived mathematically, however the more expensive
ones are still obtained through a lookup table (except on ReleaseSmall).


Decompression bit reading has been greatly simplified, taking advantage
of the ability to peek on the underlying reader. Additionally, a few bugs
with limit handling have been fixed.


## Zlib Comparison


zlib achieves a 1.00% better compression ratio at the default compression
level and 0.77% better at the best compression level. It seems that zlib
selects slightly different matches, however the total matched bytes is
less. In the future, it would be nice to figure this out and be on par with
zlib.


Here is a benchmark of the performance versus zlib using the equivalent parameters (i.e. levels).


With default compression level:


``


With best compression level:


``


Benchmark for decompression vs before:


``
[[source](https://github.com/ziglang/zig/pull/25301#issue-3436311980)]


## Expanded target support for segfault handling/unwinding


On every target that sees real use with Zig (and probably even a few
that don't), we now have working stack traces on crashes and when using
DebugAllocator.


Additionally, inline callers are now resolved from debug info when
printing stack traces on Windows. If the debug info is
[ambiguous](https://github.com/llvm/llvm-project/issues/191787), all candidate callers are printed.
[Support for resolving
inline traces from DWARF is planned](https://github.com/ziglang/zig/issues/19407).
Windows was prioritized as PDB initially associates return addresses
with the outermost inline caller leading to a particularly poor
debugging experience if the other callers aren't resolved. Error
return traces now include inline callers on all platforms.


This is part of a larger effort to improve the use case of making video games in Zig.


## Removal of ucontext_t and related types/functions


This type was useful for two things:


- Doing non-local control flow with ucontext.h functions.


- Inspecting machine state in a signal handler.


The first use case is not one we support; we no longer expose bindings
to those functions in the standard library. They're also deprecated in
POSIX and, as a result, not available in musl.


The second use case is valid, but is very poorly served by the standard
library. As evidenced by changes to
std.debug.cpu_context.signal_context_t in this release, users will be better served
rolling their own ucontext_t and especially mcontext_t types which fit
their specific situation. Further, these types tend to evolve frequently as
architectures evolve, and the standard library has not done a good job
keeping up, or even providing them for all supported targets.


## Debug Information Reworked


Zig 0.16.0 reworks many standard library APIs related to debug information, and in particular
stack traces. The motivation behind the changes was allowing fast stack tracing (without needing
to [check every stack frame for invalid
memory addresses](https://github.com/ziglang/zig/pull/24960)) without introducing potential crashes in cases where frame pointers are
unavailable (such as a libc compiled with `-fomit-frame-pointer`).


This is a surprisingly complex problem. Solving it requires "unwind information", which is
encoded in different ways on different targets. The Zig standard library already supported using
unwind information, but this support was buggy and incomplete, and often suffered from poor
performance. In Zig 0.16.0, the Zig standard library will always use "safe" stack unwinding by
default if it is available, and the performance impact (compared with naive "frame pointer"
unwinding) is usually acceptable.


The interface for printing a std.builtin.StackTrace is
std.debug.writeStackTrace:


For debugging purposes, there is also std.debug.dumpStackTrace, which
writes to stderr rather than accepting a std.Io.Terminal.


To capture the current call stack into a std.builtin.StackTrace value,
use std.debug.captureCurrentStackTrace, which also accepts some options
to control the stack trace collection behavior:


Lastly, to print the current stack trace, there are analogues to
writeStackTrace and dumpStackTrace:


Most of these function already existed in previous versions of Zig (albeit with different
signatures), but there were also several more in the past which have now been consolidated into
the above functions. Here's the API you want if using one of the removed functions:


- captureStackTrace ➡️ captureCurrentStackTrace


- dumpStackTraceFromBase ➡️ dumpCurrentStackTrace


- walkStackWindows ➡️ captureCurrentStackTrace


- writeStackTraceWindows ➡️ writeCurrentStackTrace


std.debug.StackIterator is now considered an internal API and is no
longer pub. If you were previously using it, consider whether
captureCurrentStackTrace is suitable for your needs. If for some reason
it is not, take a look at the API exposed by std.debug.SelfInfo, which is
the standard library's abstraction over the platform's debug information.


The std.debug.SelfInfo implementation can be overridden by exposing
@import("root").debug.SelfInfo. This allows stack traces to be made
functional on targets which the Zig Standard Library does not support—even freestanding
ones!


## Inter-Process Progress Reporting for Windows


std.Progress supports reporting information from child processes on Windows now.


Maximum node length bumped from 40 to 120.


## Windows Networking Without ws2_32.dll


All networking API on Windows now is implemented via direct AFD access.


This fixes a handful of bugs, makes [Cancelation](#Cancelation) and
[Batch](#Batch) work properly for networking operations, and avoids the
performance pitfalls that exist within ws2_32.dll's implementation of
networking, such as maintaining an entirely unnecessary hash table for side
data attached to socket handles that requires allocation and
synchronization, rather than simply passing socket mode and protocol to the
accept function.


## Completed Migration to NtDll


On Windows, all standard library functionality is now implemented based
on calls to the lowest level stable syscall API. The remaining extern
functions in the standard library which make calls to Windows DLLs are:


This avoids bugs, performance pitfalls, and missing functionality on
Windows, making Zig programs more robust, lean, and fast than other
programming languages that target this platform.


Notably the [Batch](#Batch) API and [Cancelation](#Cancelation) have full Windows support
with efficient implementations thanks to these efforts.


Users who wish to target older versions of Windows such as XP, or for
whatever reason would rather their applications use higher level DLLs such
as kernel32 are encouraged to collaborate on a third-party [I/O implementation](#I/O as an Interface)
that eschews NtDll.


There are no plans to migrate away from using the above listed functions.


## "Juicy Main"


Starting in Zig 0.16.0, by adding a process.Init
parameter to main, one gains access to these values:


Usage example:


The first parameter of pub fn main may be one of three things:


- Missing. Empty main parameter list is still legal, however it now means you can't access CLI arguments or environment variables.


- process.Init.Minimal. Only argv and environ available in raw form.


- process.Init. Provides a bunch of pre-initialized goodies.


An additional enhancement is being considered to add CLI arg parsing as a second parameter, however
there are some competing ideas behind the best way to do this.


## Environment Variables and Process Arguments Become Non-Global


The "environment" (a set of key-value string mappings inherited by child
processes) being global state, while a very common abstraction, is
problematic. In C, it is unsound to call environment-modifying functions
like setenv in a threaded context, because
environ can be (and often is) directly accessed
without any kind of lock. Additionally, the Zig standard library had [a major footgun](https://github.com/ziglang/zig/issues/4524):
std.os.environ was meant to be equivalent to C's
environ, but it was impossible to populate it in a
library which does not link libc.


Now, environment variables are available only in the application's main function.
Therefore, functions which need access environment variables should
accept parameters for the needed values, or accept a
*const process.Environ.Map parameter. An instance of this
environment variable map can be obtained conveniently from ["Juicy Main"](#"Juicy Main").


Accessing environment variables:


const std = @import("std");

pub fn main(init: std.process.Init) !void {
for (init.environ_map.keys(), init.environ_map.values()) |key, value| {
std.log.info("env: {s}={s}", .{ key, value });
}
}


Accessing environment variables (minimal):


const std = @import("std");

pub fn main(init: std.process.Init.Minimal) !void {
var arena_allocator: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
defer arena_allocator.deinit();
const arena = arena_allocator.allocator();

std.log.info("contains HOME: {any}", .{init.environ.contains(arena, "HOME")});
std.log.info("contains HOME (unempty): {any}", .{init.environ.containsUnempty(arena, "HOME")});
std.log.info("contains EDITOR: {any}", .{init.environ.containsConstant("EDITOR")});
std.log.info("contains EDITOR (unempty): {any}", .{init.environ.containsConstant("EDITOR")});

std.log.info("HOME: {?s}", .{init.environ.getPosix("HOME")});
std.log.info("EDITOR: {s}", .{try init.environ.getAlloc(arena, "EDITOR")});

const environ_map = try init.environ.createMap(arena);

for (environ_map.keys(), environ_map.values()) |key, value| {
std.log.info("env: {s}={s}", .{ key, value });
}
}


Accessing CLI arguments (iterate):


const std = @import("std");

pub fn main(init: std.process.Init.Minimal) void {
var args = init.args.iterate();
while (args.next()) |arg| {
std.log.info("arg: {s}", .{arg});
}
}


Accessing CLI arguments (toSlice):


const std = @import("std");

pub fn main(init: std.process.Init) !void {
const args = try init.minimal.args.toSlice(init.arena.allocator());
for (args) |arg| {
std.log.info("arg: {s}", .{arg});
}
}


## mem: introduce cut functions; rename "index of" to "find"


- Introduce cut functions: cut, cutPrefix, cutSuffix, cutScalar, cutLast, cutLastScalar


- Moving towards our function naming convention of having one word per concept and constructing function names out of concatenated concepts.


In std.mem the concepts are:


- "find" - return index of substring


- "pos" - starting index parameter


- "last" - search from the end


- "linear" - simple for loop rather than fancy algo


- "scalar" - substring is a single element


## Selectively Walking Directory Trees


std.Io.Dir.walk can be used to recursively walk a directory tree, but it does not support skipping certain directories along the way. To support that use case, std.Io.Dir.walkSelectively has been added, which requires opting-in to recursing into each directory entry encountered. This design allows avoiding redundant open/close syscalls for directories that are skipped.


Migration guide if you have a use case that benefits from selectively walking:


⬇️


Additionally, a depth function has been added to Walker.Entry, and leave functions have been added to both Walker and SelectiveWalker to allow for bailing out of iterating a particular directory part-way through.


## fs.path Windows Paths


All functions in std.fs.path now handle Windows paths more correctly
and consistently, mostly with regards to UNC, "rooted", and drive-relative
path types. This involves behavior changes in many functions, see
[#25993](https://github.com/ziglang/zig/pull/25993) for details.


API changes:


- windowsParsePath/diskDesignator/diskDesignatorWindows ➡️ parsePath, parsePathWindows, parsePathPosix


- Added getWin32PathType


- componentIterator/ComponentIterator.init can no longer fail


## fs.path.relative Became Pure


relative, relativeWindows, and relativePosix are now pure
functions that require passing the CWD path and (optionally) an environment
map as inputs instead of internally querying the OS for that information
(the environment map is needed to resolve certain path types on
Windows).


Upgrade guide:


⬇️


## File.Stat: Make Access Time Optional


Filesystems generally find this value problematic to keep updated since
it turns read-only file system accesses into file system mutations. Some
systems report stale values, and some systems explicitly refuse to report
this value. The latter case is now handled by null.


ZFS has been observed to not report atime from statx.


Also take the opportunity to make setting timestamps API more flexible
and match the APIs widely available, which have UTIME_OMIT and
UTIME_NOW constants that can be independently set for both fields.


This is needed to handle smoothly the case when atime is null.


Upgrade guide:


⬇️


For accessing Io.File.Stat.atime:


⬇️


## "Preopens"


Upgrade guide:


⬇️


Or simply get them from ["Juicy Main"](#"Juicy Main") via std.Process.Init.preopens.


Data is void on non-WASI systems; you don't pay for it if you don't use it. However,
this API is future proof in case other operating systems add equivalent functionality.


## Atomic/Temporary Files


Main motivation for this change was to move the call to std.crypto.random below the std.Io.VTable. Specifically, the one in std.Io.File.Atomic.init.


At the same time, I took the opportunity to integrate it with O_TMPFILE on Linux. I'd like to take the opportunity to complain about this API. First of all, it's almost very good. It gives the ability to create an ephemeral, unnamed file descriptor, which one can operate on freely until ready to materialize it onto the file system. If the process terminates before it gets around to doing that, the OS garbage collects the file, rather than leaving temporary, insecure trash around. Brilliant! Unfortunately, due to multiple bugs and a debilitating design limitation, the API is nearly useless.


First of all, O_TMPFILE is split across 2 bits on some architectures, and missing from another. Wtf? That's not a real problem though, moving on.


When using O_TMPFILE, how would you guess that openat() indicates that the file system does not support that operation? Perhaps with ENOSYS? Or OPNOTSUPP perchance? The all-singing, all-dancing EINVAL? Those would be two very reasonable guesses, and an acceptable third, however, wrong!! It returns either EISDIR or ENOENT. As a reminder, this is openat() we're talking about, so we very much need to know whether the path doesn't exist, or the temp file mechanism doesn't work.


Next up we have a missing API. linkat() doesn't support the AT_REPLACE flag even though there was
[a patch](https://patchwork.kernel.org/project/linux-fsdevel/patch/c823982d5b46ea888dc1fdf26c067a7aa0f3585f.1490103963.git.osandov@fb.com/)
for it submitted nearly 10 years ago that was perfectly fine. Linus said it was OK, and then it just never got merged. Without this flag, O_TMPFILE cannot be used to atomically overwrite an existing file. This means if you want to do that you have to create a regular old non temp file with random numbers or something, and then use renameat().


So the only time that this O_TMPFILE trick actually does any good is if you want hard link semantics, i.e. you want error.PathAlreadyExists when the destination path already exists. Think about it, if you deleted the file to make room, then it wouldn't be atomic any more!


OK, rant over.


Anyway the upshot of this is, the moment any OS fixes their shitty APIs with respect to temporary files, we can change std.Io.Threaded accordingly, and all the Zig code that uses std.Io can remain unchanged and gain those benefits transparently.


Finally, this branch introduces std.Io.File.hardLink API, which only works on Linux, and is needed in order to materialize a O_TMPFILE file descriptor without replacement semantics.


Upgrade guide:


⬇️


## Memory Locking and Protection API Moved to process


mmap and mprotect flags now have type safety:


⬇️


mlock, mlock2, mlockall:


⬇️


## Current Directory API Renamed


In Zig standard library, Dir means an open directory handle. path
represents a file system identifier string. This function is better named
after "current path" than "current dir". "get" and "working" are
superfluous.


Upgrade guide:


⬇️


## Migration to "Unmanaged" Containers


In the past, Zig standard library offered two variants of dynamically growing data structures:
one with the Allocator instance as a field of the struct ("managed"), one where it
must be passed into every method that needs it ("unmanaged").


Over time, Zig programmers realized together that the variant without the allocator field is
more versatile and the other one should be removed. With only one variant,
we no longer need this vague word "managed" to distinguish them. In this
release, several APIs took migratory steps:


- Added heap.MemoryPoolUnmanaged, heap.MemoryPoolAlignedUnmanaged, heap.MemoryPoolExtraUnmanaged ([#23234](https://github.com/ziglang/zig/pull/23234))


- [PriorityDequeue](#PriorityDequeue) no longer has an Allocator field.


- [PriorityQueue](#PriorityQueue) no longer has an Allocator field.


- ArrayHashMap, AutoArrayHashMap, StringArrayHashMap removed.


- AutoArrayHashMapUnmanaged ➡️ array_hash_map.Auto


- StringArrayHashMapUnmanaged ➡️ array_hash_map.String


- ArrayHashMapUnmanaged ➡️ array_hash_map.Custom


## PriorityDequeue


Changes follow Deque closely:


- Methods containing add have been renamed to push and remove have been renamed to pop.


- popMinOrNull and popMaxOrNull have been merged into the popMin and popMax respectively (without any loss in functionality).


- Default field values are initialized using a .empty constant instead of the init() method.


Upgrade guide:


- init             ➡️  .empty


- add              ➡️  push


- addSlice         ➡️  pushSlice


- addUnchecked     ➡️  pushUnchecked


- removeMinOrNull  ➡️  popMin


- removeMin        ➡️  popMin


- removeMaxOrNull  ➡️  popMax


- removeMax        ➡️  popMax


- removeIndex      ➡️  popIndex


## PriorityQueue


A priority queue with default field values can be initialized using .empty.


For example, a priority queue can be used to initialize a min and max heap with a compare function like:


fn lessThan(context: void, a: u32, b: u32) Order {
_ = context;
return std.math.order(a, b);
}

const MinHeap = std.PriorityQueue(u32, void, lessThan);

var queue: MinHeap = .empty;


fn greaterThan(context: void, a: u32, b: u32) Order {
_ = context;
return std.math.order(a, b).invert();
}

const MaxHeap = std.PriorityQueue(u32, void, greaterThan);

var queue: MaxHeap = .empty;


Upgrade guide:


- init ➡️ initContext


- add ➡️ push


- addUnchecked ➡️ pushUnchecked


- addSlice ➡️ pushSlice


- remove ➡️ pop


- removeOrNull ➡️ pop


- removeIndex ➡️ popIndex


## Thread.Pool Removed


The thread pool implementation previously at std.Thread.Pool has been
removed in Zig 0.16.0, in favor of the multiprocessing primitives in the
[new std.Io interface](#I/O as an Interface).


Uses of std.Thread.Pool.spawnWg should likely be replaced with calls to std.Io.async or std.Io.Group.async, though note that this assumes the task does not need to synchronize with the caller (in other words, it assume the new task is *asynchronous* with the caller). For instance, one migration might look like this:


⬇️


Note that when switching from std.Thread.Pool to std.Io, it is
required for correctness that any Thread.Mutex, Thread.Condition,
Thread.ResetEvent, or other thread synchronization primitive in the code,
be converted to its equivalent Io type, such as Io.Mutex,
Io.Condition, or Io.Event.


For complex usages of std.Thread.Pool (where two or more tasks must
synchronize somehow), async may not be appropriate: consult the
documentation for std.Io.async and std.Io.concurrent for more
information.


## Remove builtin.subsystem


The subsystem detection was flaky and often incorrect and was not
actually needed by the compiler or standard library. The actual subsystem
won't be known until at link time, so it doesn't make sense to try to
determine it at compile time.


Removing std.builtin.subsystem is a breaking change but it is unlikely many
users were using it in the first place.
[If
your code absolutely needs to know the subsystem there are ways to determine it at runtime](https://github.com/ziglang/zig/issues/25127#issuecomment-3249505063).


## Move Target.SubSystem to zig.Subsystem and update field names


std.zig is where options like SanitizeC or LtoMode reside, so it
is an appropriate place. std.Target.SubSystem remains as a
deprecated alias and the old field names remain as deprecated decls to avoid
breaking e.g. exe.subsystem = .Windows in build.zig scripts.


## Io: delete GenericReader, AnyReader, FixedBufferStream


Migration guide:


- std.io ➡️ std.Io


- std.Io.GenericReader ➡️ std.Io.Reader


- std.Io.AnyReader ➡️ std.Io.Reader


- std.leb.readUleb128 ➡️ std.Io.Reader.takeLeb128


- std.leb.readIleb128 ➡️ std.Io.Reader.takeLeb128


FixedBufferStream (reading)


⬇️


FixedBufferStream (writing)


⬇️


## Replace {D} format specifier with Io.Duration format method


The {D} duration format specifier has been removed in order to enhance type safety in light of the new std.Io.Duration type.


Migration guide:


⬇️


## fs.getAppDataDir Removed


This API was a bit too opinionated for the Zig standard library.
Applications should contain this logic instead.
Users may consider third party package [known-folders](https://github.com/ziglibs/known-folders)
as an alternative.


## Io.Writer.Allocating Alignment Field

This API now has a new field:

This is a runtime-known alignment value. The Allocator API supports this if
you use the "raw" function variants.


## fs.Dir.readFileAlloc


⬇️


Note that the limit has a difference; if it's reached it also
returns the error. Also the error has been changed from FileTooBig to
StreamTooLong.


## fs.File.readToEndAlloc


⬇️


## std.crypto: add AES-SIV and AES-GCM-SIV


The Zig standard library was missing schemes that are resistant to nonce reuse.


AES-SIV and AES-GCM-SIV are the standard solutions for this.


AES-GCM-SIV is particularly useful when Zig is targeting embedded systems, while AES-SIV is especially valuable for key wrapping.


## std.crypto: add Ascon-AEAD, Ascon-Hash, Ascon-CHash


Ascon is the family of cryptographic constructions standardized by NIST for lightweight cryptography.


The Zig standard library already included the Ascon permutation itself, but higher-level constructions built on top of it were intentionally postponed until NIST released the final specification.


That specification has now been published as [NIST SP 800-232](https://csrc.nist.gov/pubs/sp/800/232/final).


With this publication, we can now confidently include these constructions in the standard library.


## Build System


Uncategorized changes:


- std.Build.Step.ConfigHeader: handle leading whitespace for cmake


## Ability to Override Packages Locally


Introduces a new zig build flag:


``


This is a project override option. The path provided contains a build.zig.zon file which contains name and fingerprint fields. Any time the dependency tree would resolve to a package with matching name and fingerprint, it resolves to the override instead, across the entire tree, completely ignoring version. This resolves before the package is potentially fetched. So if you find yourself without Internet, forgot to fetch, but you have a git repository lying around, you're one CLI flag away from being unblocked.


This is an easy way to temporarily use one or more forks which are in entirely separate directories. One can iterate on their entire dependency tree until everything is working, while using comfortably the development environment and source control of the dependency projects.


The fact that it is a CLI flag makes it appropriately ephemeral. The moment you drop the flags, you're back to using your pristine, fetched dependency tree.


If the project does not match, an error occurs, preventing confusion:


``


If the project does match, you get a reminder that you are using a fork, preventing confusion:


``


This functionality is intended to enhance the workflow of dealing with ecosystem breakage.


This feature depends on the new hash format; therefore legacy hash format support is removed.


## Fetch Packages Into Project-Local Directory


Instead of being fetched into `$GLOBAL_ZIG_CACHE/p/$HASH`, package dependencies are now fetched into a "zig-pkg" directory relative to the build root (next to build.zig). Users are generally encouraged to not commit these files to source control, however it is understood that some will choose to do so for convenience.


After a package is fetched, the filters are applied
(paths field in
`build.zig.zon`) in order to delete files not part of
the hash, and then the package is recompressed into a canonical
`$GLOBAL_ZIG_CACHE/p/$HASH.tar.gz` in order to avoid
network next time the same package is needed.


The motivation for this change is to make it easier to tinker. Go ahead
and edit those files, see what happens. Swap out your package directory
with a git clone. Grep your dependencies all together. Configure your IDE
to auto-complete based on zig-pkgs directory.
[Run baobab on your dependency tree](https://codeberg.org/awebo-chat/awebo/issues/61).
Furthermore, by having the global cache have compressed files instead makes
it easier to share that cached data between computers.


zig build will now fail when encountering package dependencies without fingerprint field or with name as a string rather than enum literal. Fingerprint is needed in order to determine that two packages with different versions are intended to be different versions of the same project. It will become an error to have the same fingerprint, same version, different hash in your dependency tree because it means somebody forgot to bump a version number, or somebody is trying to do a hostile package fork and now you have to choose a side.


Zig no longer observes ZIG_BTRFS_WORKAROUND environment variable. The
bug has been fixed in upstream Linux a long time ago by now ([#17095](https://github.com/ziglang/zig/issues/17095)).


## Unit Test Timeouts


It is now possible to specify a timeout to apply to all individual Zig unit tests (i.e.
test blocks). Using the `--test-timeout` flag to
`zig build`, you can specify a timeout value, after which the build system will
forcibly terminate the current unit test (by killing and restarting the test process) and
move on to the next.


For instance, running `zig build test --test-timeout 500ms` will run the step
named `test`, except if any individual Zig unit test fails to finish within 500ms of
real time, the test will be terminated and an error emitted:


``


This is useful to detect slow tests or tests which are failing to terminate. However, bear in
mind that the timeouts are specified in real time rather than CPU time, so on a system under
heavy load, scheduler stress could cause unexpected timeouts.


## Added --error-style Flag


The new `--error-style` CLI flag of `zig build` allows customizing how
error messages from build steps are written to stderr. The default style, `verbose`,
will print the full context, including the relevant step dependency tree showing why this step
is being built, and failed commands where applicable. Alternatively, the `minimal`
style can be specified to omit these pieces of information in favour of simply printing the
failed step name and its error message.


In addition, two more error styles are available, `verbose_clear` and
`minimal_clear`. These are similar to `verbose` and `minimal`
respectively, but when using `--watch`, they will clear the terminal when a rebuild
is triggered due to an input file changing. These modes are particularly useful if you make use
of [Incremental Compilation](#Incremental Compilation).


If the `--error-style` flag is not specified, the build system will also check for
the environment variable `ZIG_BUILD_ERROR_STYLE`, and if present, use that value.
This allows globally specifying your preferred mode by setting a persistent environment variable
in your shell configuration.


This flag replaces the `--prominent-compile-errors` flag, which has been removed.
If you were previously using `--prominent-compile-errors`, the equivalent in Zig
0.16.x is `--error-style minimal`.


## Added --multiline-errors Flag


The new `--multiline-errors` CLI flag of `zig build` controls how the
build system prints errors which span multiple lines. The available options are
`indent` (the new default), `newline`, and `none`:


``


If the `--multiline-errors` flag is not specified, the build system will also
check for the environment variable `ZIG_BUILD_MULTILINE_ERRORS`, and if present, use
that value. This allows globally specifying your preferred mode by setting a persistent
environment variable in your shell configuration.


## Temporary Files API


The RemoveDir step is gone with no replacement. This step had no valid
purpose. Mutating source files? That should be done with UpdateSourceFiles
step. Deleting temporary directories? That required creating the tmp
directories in the configure phase which is broken. Deleting cached
artifacts? That's going to cause problems.


Similarly, Build.makeTempPath function is gone. This was used to
create a temporary path in the configure place which, again, is the
wrong place to do it.


Instead, the WriteFile step has been updated with more functionality:


tmp mode: In this mode, the directory will be placed inside "tmp" rather
than "o", and caching will be skipped. During the make phase, the step
will always do all the file system operations, and on successful build
completion, the dir will be deleted along with all other tmp directories.
The directory is therefore eligible to be used for mutations by other
steps. Build.addTempFiles is introduced to initialize a WriteFile step
with this mode.


mutate mode: The operations will not be performed against a freshly
created directory, but instead act against a temporary directory.
Build.addMutateFiles is introduced to initialize a WriteFile step with
this mode.


Build.tmpPath is introduced, which is a shortcut for
Build.addTempFiles followed by WriteFile.getDirectory.


Upgrade guide:


If you were calling b.makeTempPath() followed by addRemoveDirTree,
instead you can now call b.addTempFiles and use the
std.Build.Step.WriteFile API. No need to do anything else, the build
runner will clean up the tmp files for you, and it will understand that the
tmp files cannot be cached.


## Compiler


## C Translation


Zig's implementation of translate-c is now based on
[arocc](https://github.com/Vexu/arocc/) and [translate-c](https://codeberg.org/ziglang/translate-c) instead of libclang. Goodbye and good riddance to 5,940 lines of our remaining C++ code in
the compiler source tree, with 3,763 remaining.


The implementation is compiled lazily from source the first time @cImport is encountered. [In the future, Zig will drop the @cImport language builtin](#@cImport Moving to Build System), but for
now it remains, backed by Aro instead of Clang.


This is progress towards [transitioning from a library dependency on LLVM to a process dependency on Clang](https://github.com/ziglang/zig/issues/16270).


This is technically a non-breaking change. While breakage is likely due
to one C compiler being swapped out for another, if it occurs it is a bug
rather than a feature. So, cross your fingers when you upgrade and report a bug if something breaks.


## LLVM Backend


- Experimental support for [Incremental Compilation](#Incremental Compilation)


- 3-7% decrease in LLVM bitcode size


- Slightly faster compilation (~3%) in some cases


- Fixed debug information for unions with zero-bit payloads


- Debug information now includes correct names for all types


- Error set types are now lowered as enums so that error names are visible at runtime


Matthew also looked into changing the representation of tagged union and error union types in debug
information to use [variant types](https://dwarfstd.org/doc/DWARF5.pdf#page=141),
which would allow debuggers to understand which field is "active" and only show that one.
Unfortunately, while GDB supports this feature, LLDB does not, and fails to print the type's
fields whatsoever when variant types are used. (Bizarrely, LLDB does have partial
support, but [it's only enabled when the language is marked as Rust](https://github.com/llvm/llvm-project/blob/0c0ae3786ef4ec04ba0dc9cdd565b68ec486498a/lldb/source/Plugins/SymbolFile/DWARF/DWARFASTParserClang.cpp#L3203-L3207)). He may revisit this in the future if
the situation improves downstream.


We have made some internal changes to try and work towards fully parallelising this backend,
so that there can be multiple threads generating LLVM IR for different functions which then get
glued together by a "linker" thread. Expect more progress towards this in the future!


Compared to the [x86 Backend](#x86 Backend), the LLVM backend is passing
2004/2010 (100%) of the behavior tests.


## Reworked Byval Syntax Lowering


When writing the self-hosted compiler, there was an early experiment to
attempt to slightly reduce the number of intermediate instructions emitted
in the pipeline, by lowering expressions with "byval" semantics. The experiment
was a failure, because it lead to the following issues:


- [Array access performance issues](https://github.com/ziglang/zig/issues/13938)


- [Surprising aliasing despite explicit copy](https://github.com/ziglang/zig/issues/22906)


- [Extremely poor code quality in degenerate cases](https://github.com/ziglang/zig/issues/25111)


The frontend now lowers expressions "byref" until the final load, fixing all of those issues.


[more details](https://github.com/ziglang/zig/pull/25154)


## Reworked Type Resolution


Zig 0.16.0 [significantly reworks](https://codeberg.org/ziglang/zig/pulls/31403)
how the Zig compiler handles type resolution internally. The motivation behind this change was
to simplify the process of writing the Zig language specification, and to resolve a huge number
of compiler bugs, in particular related to [Incremental Compilation](#Incremental Compilation).


The new type resolution semantics are, on the whole, more permissive than the old
behavior. This means that most code which previously worked will continue to work, and some
examples which previously did not work (likely with a "dependency loop" error) will now
work.


However, the new system is not strictly more permissive. There are certain things
which were previously accepted by the Zig compiler and are now not, such as the following:


The rules of the new system are generally more intuitive—for instance, while the above
code snippet could theoretically work, it also seems clear why it might not.
In other words, the dependency loop errors do not seem unreasonable or wholly unexpected, which
they often did in previous versions of Zig.


Unfortunately, it is difficult to give general advice if you are experiencing dependency loop
errors, because the appropriate solution is highly contextual. However, Zig 0.16.0 also
significantly improves error reporting in dependency loop situations, which should hopefully
make it easier to understand where dependency loops actually come from:


If you are struggling to resolve a dependency loop, consider joining a Zig
[community](https://ziglang.org/community/) to get help from fellow Zig users!


## Incremental Compilation


Incremental compilation is a feature of the Zig compiler which allows it to only compile code
which has been modified since the previous build, making small changes take milliseconds to
build instead of seconds or minutes. In Zig 0.16.0, support for this feature has improved
significantly.


Here are some of the main improvements in this release cycle:


- Incremental updates have been made significantly faster by avoiding "over-analysis" (where
the compiler rebuilds more code than it needs to) in the vast majority of cases. For
instance, when using incremental compilation on the Zig compiler itself, changes which
previously recompiled almost the entire compiler now complete in milliseconds. This is
thanks to [Reworked Type Resolution](#Reworked Type Resolution) making the compiler's internal dependency graph
acyclic (except in the case of dependency loops).


- Incremental compilation no longer triggers "dependency loop" compile errors which do not
occur in non-incremental builds (and vice versa). This was the biggest inconsistency between
incremental and non-incremental builds in previous releases, and was resolved as a part of
[Reworked Type Resolution](#Reworked Type Resolution).


- When using a self-hosted backend targeting ELF, the [New ELF Linker](#New ELF Linker) is now enabled
by default, which is faster and has much more stable support for incremental compilation.
This linker is not yet feature-complete—see [New ELF Linker](#New ELF Linker) for details.


- General stability has greatly improved—crashes and miscompilations in incremental
updates are far less common than in previous versions of Zig.


- The [LLVM Backend](#LLVM Backend) now supports incremental compilation. This does not speed up the
"LLVM Emit Object" phase of compilation: that step is entirely LLVM's responsibility
and there is little we can do to speed it up. However, it does speed up the building of LLVM
bitcode in the Zig compiler. This also means that in cases where your code emits compilation
errors, you can get near-instant feedback even with the LLVM backend (since "LLVM Emit
Object" is skipped when compile errors exist).


Incremental compilation [still has known bugs, including some
miscompilations](#This Release Contains Bugs), and therefore remains
disabled by default in 0.16.0. Despite this, we still encourage
enabling it. Users are frequently surprised by just how much
time they can save even just with near-instant compile error feedback, let
alone near-instant compilation!


Because incremental compilation is now usable with both the [self-hosted ELF linker](#New ELF Linker)
and the [LLVM Backend](#LLVM Backend), opting in is usually as simple as running
`zig build -fincremental --watch`. This command will spawn a build process which can
detect when any source files change and automatically perform an incremental update.


[Future release cycles](#Roadmap) will continue to focus on
incremental compilation, with more bug fixes, improved testing
infrastructure, performance enhancements, and better [Linker](#Linker)
support.


## x86 Backend


- 11 bugs fixed.


- Generates better constant memcpy code ([#25353](https://github.com/ziglang/zig/pull/25353)).


Compared to the [LLVM Backend](#LLVM Backend), this backend passes more behavior
tests, has significantly faster compilation speed, superior debug
information, and inferior machine code quality. It remains the default when
compiling in Debug mode.


## aarch64 Backend


Still a work-in-progress. Progress was paused during this release cycle
due to the [I/O as an Interface](#I/O as an Interface) churn. Currently crashes when
running the behavior tests. Progress is expected to pick up as the
[Standard Library](#Standard Library) churn subsides.


## WebAssembly Backend


Compared to the [LLVM Backend](#LLVM Backend), Zig's WebAssembly backend is passing
1813/1970 (92%) of behavior tests.


## Generating Import Libraries from .def Files Without LLVM


Eliminates a dependency on LLVM with regards to the set of [MinGW-w64](#MinGW-w64) .def
files shipped with Zig. This implementation is largely based on the LLVM
implementation (specifically
[COFFModuleDefinition.cpp](https://github.com/llvm/llvm-project/blob/main/llvm/lib/Object/COFFModuleDefinition.cpp)
and
[COFFImportFile.cpp](https://github.com/llvm/llvm-project/blob/main/llvm/lib/Object/COFFImportFile.cpp)).


This is progress towards [transitioning from a library dependency on LLVM to a process dependency on Clang](https://github.com/ziglang/zig/issues/16270).


## Improved Code Generation of For Loop Safety Checks


Looping over slices generates ~30% less code.


## Linker


## New ELF Linker


The new linker can be used with -fnew-linker in the CLI, or by setting
exe.use_new_linker = true in a build script. It is now the default when
passing -fincremental and targeting ELF.


Performance data point [[source](https://github.com/ziglang/zig/pull/25299#issuecomment-3321207092)]:
building the Zig [Compiler](#Compiler), then making a single-line change to a function, and then another:


- Old linker: 14s, 194ms, 191ms


- New linker: 14s, 65ms, 64ms (66% faster)


- Skip linking altogether: 14s, 62ms, 62ms (68% faster)


The performance is fast enough that there is
no longer much benefit to exposing a `-Dno-bin` build step.
You might as well keep codegen and linking always enabled because the
compilation speed difference is negligible, and then you get an executable
at the end.


However, this new linker is not feature complete versus the old one nor
versus LLD. For example, executables produced this way lack DWARF
information. Therefore, the old linker and LLD are both still available.
When the new linker is feature complete, the old linker will be deleted and
LLD will be removed as a dependency.


## Fuzzer


## Smith


The []const u8 parameter of fuzz tests has been replaced with
*std.testing.Smith. This new interface is used to generate values from
the fuzzer. It contains the following base methods:


-  value for generating any type.


-  eos for generating end-of-stream markers. Provides the additional
guarantee that true will eventually by returned.


-  bytes for filling a byte array.


-  slice for filling part of a buffer and providing the length.


Values can be given a probability of being selected with
[]const Smith.Weight. This is useful to


- make interesting values be chosen more often


- reduce the chance for more work


- constrain selectable values


In an empty slice of weights, every value has a weight of zero and
will not be selected. Weights can only be used with types fitting in
64-bits. Each base methods has corresponding ones that accept weights.
Additionally, the following functions are provided:


- baselineWeights which provides a set of weights containing every
possible value of a type.


- boolWeighted and eosSimpleWeighted for
conveniently weighing true and false.


- valueRangeAtMost and valueRangeLessThan for
generating only a range of values.


Each method also has a counterpart which accepts a hash where values with the same hash are
more more likely to be mutated in respect to each other. The regular methods already use hashes
based off the callee's return address, so it is usually redundant to directly call these
functions, but they can be useful in case of inlining.


Example upgrade:


⬇️


## Multiprocess Fuzzing


The fuzzer now is able to utilize multiple cores. This is controllable
with the -j build option. Limited fuzzing still uses one core.


## Fuzzing Infinite Mode


When provided multiple tests, the fuzzer now switches between them and prioritizes the most
effective and interesting ones. Over time already explored tests will become barely run compared
to tests yielding new inputs.


## Crash Dumps


Crashing inputs are now saved to a file indicated by the crash message. It is recommended to
use these files to reproduce the crash using
std.testing.FuzzInputOptions.corpus and
@embedFile.


## Numerous bugs found and fixed with the help of an AST smith


The new smith interface has already seen use in testing the toolchain with the creation of an
AST Smith which is used to generate random valid ASTs.


When run against zig fmt (in addition to some earlier simpler random
source testing) 20 unique bugs were found and fixed, some of which had
been previously reported and many newly discovered.


It also found several inconsistencies between the specified PEG and the parser:
notably, a tuple could not contain types starting with extern or
inline; for example,
const T = struct { u64, extern struct { a: u64 }, u32 }
would result in an error. A detailed list of PEG and Parser changes can be found on
[add an ast smith](https://codeberg.org/ziglang/zig/pulls/31635).


## Bug Fixes


Full list of the 345 bug reports closed during this release cycle:


- [Tracked on GitHub](https://github.com/ziglang/zig/issues?q=is%3Aclosed+is%3Aissue+label%3Abug+milestone%3A0.16.0)


- [Tracked on Codeberg](https://codeberg.org/ziglang/zig/issues?q=&type=all&sort=relevance&state=closed&labels=741711&milestone=32343&project=0&assignee=0&poster=0)


Many bugs were both introduced and resolved within this release cycle.
Most bug fixes are omitted from these release notes for the sake of
brevity.


## This Release Contains Bugs


Zig has known
[bugs](https://codeberg.org/ziglang/zig/issues?q=&type=all&sort=relevance&labels=741711&state=open&milestone=0&project=0&assignee=0&poster=0),
[miscompilations](https://codeberg.org/ziglang/zig/issues?q=&type=all&sort=relevance&labels=746970&state=open&milestone=0&project=0&assignee=0&poster=0), and
[regressions](https://codeberg.org/ziglang/zig/issues?q=&type=all&sort=relevance&labels=741714&state=open&milestone=0&project=0&assignee=0&poster=0).


Even with Zig 0.16.x, working on a non-trivial project using Zig may
require participating in the development process.


When Zig reaches 1.0.0, Tier 1 support will gain a bug policy as an additional
requirement.


## Toolchain


## LLVM 21


This release of Zig upgrades to
[LLVM 21.1.0](https://releases.llvm.org/21.1.0/docs/ReleaseNotes.html). This
covers Clang ([zig cc](#zig cc)), libc++, libc++abi, libunwind, and
libtsan as well.


## Loop Vectorization Disabled to Work Around Regression


The regression is serious for Zig because it causes the compiler
itself to be miscompiled in common configurations. Trying to work
around this by disabling certain CPU features is too brittle, so we have
disabled loop vectorization entirely until we upgrade to a version of LLVM
where this bug is fixed. This pessimises codegen in some cases, which,
while unfortunate, is preferable to miscompilations.


This has been [reported](https://github.com/llvm/llvm-project/issues/186922) and
[fixed](https://github.com/llvm/llvm-project/pull/187023) upstream, however at time
of writing the fix has not been cherry-picked into LLVM's 22.x release branch,
therefore we expect this performance regression to affect not only Zig
0.16.x but also 0.17.x, finally resolved in 0.18.x.


## musl 1.2.5


Zig 0.16.0 distributes musl 1.2.5 plus backported security fixes.
Meanwhile, upstream has tagged 1.2.6. A future release of Zig will update
to musl 1.2.6.


When targeting musl statically, many functions are now provided by [zig libc](#zig libc) rather
than source files copied from musl. Specifically, 331 fewer musl C source files are now distributed
with Zig, with 1,206 remaining. Therefore, if you encounter bugs with musl libc provided by Zig,
please respect upstream by reporting them to Zig's issue tracker rather than musl's.


Note that Zig 0.16.0 is not believed to be affected by
[CVE-2026-40200](https://www.openwall.com/lists/oss-security/2026/04/10/13) due to
musl's `qsort` and `qsort_r` no longer being used.


## glibc 2.43


glibc version 2.43 is now available when cross-compiling.


## Linux 6.19 Headers


This release includes Linux kernel headers for version 6.19.


## macOS 26.4 Headers


This release includes macOS system headers for version 26.4.


## MinGW-w64


Zig 0.16.0 continues to distribute MinGW-w64 commit `38c8142f660b6ba11e7c408f2de1e9f8bfaf839e`.


However, many functions are now provided by [zig libc](#zig libc) rather
than source files copied from MinGW-w64. Specifically, 99 fewer MinGW-w64 C source files are now distributed
with Zig, with 398 remaining. Therefore, if you encounter bugs with MinGW-w64 libc provided by Zig,
please respect upstream by reporting them to Zig's issue tracker rather than MinGW-w64's.


## FreeBSD 15.0 libc


FreeBSD libc version 15.0 is now available when cross-compiling.


## WASI libc


Zig 0.16.0 updates to WASI libc commit `c89896107d7b57aef69dcadede47409ee4f702ee`.


However, many functions are now provided by [zig libc](#zig libc) rather
than source files copied from WASI libc.


In spite of this, the number of WASI libc C source files distributed with Zig increased
from 196 to 228 due to the newer WASI libc adding pthread shims and the fact that most WASI libc
source files are shared with [musl](#musl 1.2.5).


## zig libc


Zig's libc implementation gained many new functions, leading to the corresponding C source
files being deleted from [musl](#musl 1.2.5) and [MinGW-w64](#MinGW-w64). In this release,
the number of C source files distributed went from 2,270 to 1,873 (-17%).


Notably this includes many math functions, as well as `malloc` and friends.
Special thanks to Szabolcs Nagy for [libc-test](https://wiki.musl-libc.org/libc-test.html).


## zig cc


`zig cc` and `zig c++` are now based on Clang 21.1.8.


9 bugs were fixed: [GitHub](https://github.com/ziglang/zig/issues/?q=is%3Aissue%20state%3Aclosed%20label%3A%22zig%20cc%22%20milestone%3A0.16.0) [Codeberg](https://codeberg.org/ziglang/zig/issues?q=&type=all&sort=relevance&state=closed&labels=741711%2C747024&milestone=32343&project=0&assignee=0&poster=0&archived=false)


## Support dynamically-linked OpenBSD libc when cross-compiling


Zig now allows cross-compiling to OpenBSD 7.8+ by providing stub
libraries for dynamic libc, similar to how cross-compilation for glibc is
handled. Additionally, all libc headers and most system headers are provided.


## Roadmap


The 0.17.0 release cycle will be short, aiming mainly to upgrade to LLVM 22 and finish
[separating the make process (build runner) from the configure process (build.zig)](https://codeberg.org/ziglang/zig/issues/31691).


After that, the major initiatives will be:


- Completing and stabilizing the language.


- Completing the [aarch64 Backend](#aarch64 Backend), making it the default backend for debug mode.


- Enhancing [Linker](#Linker) implementations, eliminating dependency on
[LLD](https://lld.llvm.org/) and supporting [Incremental Compilation](#Incremental Compilation).


- Enhancing the integrated [Fuzzer](#Fuzzer) to be competitive with AFL and other state-of-the-art fuzzers.


- [Transitioning from a library dependency on LLVM to a process dependency on Clang](https://github.com/ziglang/zig/issues/16270).


## Thank You Contributors!


Here are all the people who landed at least one contribution into this release:


- Andrew Kelley


- Alex Rønne Petersen


- Matthew Lugg


- Jacob Young


- Ryan Liptak


- Justus Klausecker


- Frank Denis


- Kendall Condon


- GasInfinity


- mihael


- Mason Remaley


- rpkak


- Brandon Black


- Michael Dusan


- Carl Åstholm


- David Rubin


- Linus Groh


- Casey Banner


- Adrià Arrufat


- xdBronch


- Meghan Denny


- Lukas Lalinsky


- Jay Petacat


- Techatrix


- Mateusz Poliwczak


- Pat Tullmann


- Saurabh Mishra


- kj4tmp


- Henry Kupty


- Isaac Freund


- John Benediktsson


- Loris Cro


- Luna Schwalbe


- Pavel Verigo


- mercenary


- pentuppup


- Bingwu Zhang


- Michael Pfaff


- Stephen Gregoratto


- Veikka Tuominen


- hemisputnik


- lzm-build


- David Senoner


- Giuseppe Cesarano


- Jan200101


- Mathieu Suen


- Nathan Bourgeois


- unplanned


- Antonin Décimo


- Hila Friedman


- Jake Greenfield


- Khitiara


- Pablo Alessandro Santos Hugen


- Pivok


- Ryan Zezeski


- Sardorbek Imomaliev


- TemariVirus


- Vadym Prodan


- Wim de With


- Zirunis


- brickmonster


- murtaza


- squidy239


- taylor.fish


- Andrew Kraevskiii


- FnControlOption


- George Huebner


- Huang Zhichao


- IOKG04


- Ian Johnson


- InKryption


- Ivel


- Jon Parise


- Josh Megnauth


- Maciej 'vesim' Kuliński


- Marcel W. Wysocki


- Mason Remaley


- Michael Neumann


- Nashwan Azhari


- Neel


- Nico Elbers


- Prokop Randáček


- Steven Casper


- Tom Read Cutting


- Yusuf Bham


- Zhenming-Lin


- Zihad


- ashpil


- binarycraft007


- eshom


- glowsquid


- jsentity


- marko


- marximimus


- snoire


- traxar


- whatisaphone


- 0x4a61636f62


- 87


- Aaron Ang


- AdamGoertz


- Adrian


- Adrià Arrufat


- Aidan Welch


- Ali Cheraghi


- Antti Harju


- Arnau Camprubí


- Becker A.


- Ben Buhse


- Ben Krieger


- Benjamin Jurk


- Brandon Freeman


- Brandon Mercer


- Brian Orora


- Carmen


- Carter Snook


- Chadwain Holness


- Chris Boesch


- Cooksey99


- Corentin Kerisit


- Daggerfall-is-the-best-TES-game


- David


- David Gonzalez Martin


- DivergentClouds


- Doug Coleman


- Eamon Burns


- Erik Schlyter


- Evgenii Orlov


- Felipe Cardozo


- Fri3dNstuff


- Gregory Mullen


- Guillaume


- Harold


- Henry John Kupty


- Igor Anić


- Iku Iwasa


- IntegratedQuantum


- Ivan Agafonov


- Jakub Konka


- Jonathan Marler


- Josh GM Walker


- Karel Marek


- Karol Kosek


- Kevin Primm


- Koko Bhadra


- Kristoffer


- Krzysztof Antonowski


- Krzysztof Wolicki


- Kyle Schwarz


- Leon Lombar


- Leslie Lau


- Lucas Santos


- LukaTD


- Lwazi Dube


- Mathias Lafeldt


- Mick Sayson


- Motiejus Jakštys


- Nathan Michaels


- Nathaniel Ketema


- Nicholas McDaniel


- Nikolay Govorov


- Nils Juto


- Nils Koch


- Nir Lahad


- PeterMcKinnis


- Petr Pučil


- Purple


- Qun He


- Raiden1411


- Rajiv Singh


- Rick Calixte


- Robby Zambito


- Robert Ancell


- Rohlem


- Rue


- Rue04


- Sam Bossley


- Sam K


- Samuel Fiedler


- Sean


- Sertonix


- Silver


- Sivecano


- So1aric


- Steeve Morin


- Tadej Gašparovič


- Tea


- TibboddiT


- Timothy Bess


- Tobias Simetsreiter


- Toufiq Shishir


- Travis Staloch


- UraniaZPM


- Vladislav Shabanov


- Yanfeng Liu


- Yefeng Li


- aarvay


- achan1989


- akhildevelops


- angus


- antme0


- badayvedat


- baltevl


- bartimaeusnek


- bgthompson


- bnuuydev


- breakmit


- database64128


- doclic


- e820


- estevesnp


- fardragon


- fkobi


- hixuyuming


- hubidubi


- inf


- inge4pres


- invlpg


- johan0A


- jonascloud


- just_some_entity


- kanpura


- kbz_8


- kineye


- llogick


- meowjesty


- mintonmu


- moriazoso


- nash1111


- nekogirl


- nyx-xyn


- ptrstr


- pyk


- qilme


- regp


- rohlem


- samy007


- skewb1k


- tehlordvortex


- tokyo4j


- unerr


- usebeforefree


- vitalii


- xeondev


## Thank You Sponsors!


Special thanks to those who [sponsor Zig](/zsf/).
Because of diverse, recurring donations, Zig is driven by the open source community, rather
than the goal of making profit. In particular, those below sponsor Zig for $50/month or more
using our [preferred donation platform](https://www.every.org/zig-software-foundation-inc):


- Synadia Communications


- TigerBeetle


- ZML


- Mitchell Kember


- Kirk Scheibelhut


- David Vanderson


- Freddi Linse


- Numan Sachwani


- Dylan Conway


- Thomas Manner


- Kazuhiro Kondo


- Trevor John


- Andrew Mangogna


- Karrick McDermott


- Alex Kladov


- Jason Watson


- Daniele Cocca


- Matthew Knight


- Greg Clark


- Wolfgang Sanyer


- Erik Dunteman


- Kyle Hill


- Merlyn Morgan-Graham


- Jacob Sandlund


- Igor Anic


- Caleb Hearon


- Aurélien Cibrario


- Ondra Voves


- Fawzi Mohamed


- Yaroslav Zhavoronkov


- David Jones


- Richard Levitte


- Merlyn Morgan-Graham


- Mitchell Gayner


- Miles McGruder


- Felix Queißner


- Srinivasan Balram


- Jorge De León


- Nick Macholl


- Flavius Gruian


- Erik Mållberg


- FELIPE SOARES GONCALVES SA ROSA


- Peter Ronnquist


- Will Pragnell


- William Canan


- Gauthier Voron


- Saurabh Mishra


- Álvaro Justen


- Ian Johnson


- Benjamin Crist


- Chris Baldwin


- Pete Dietl


- Lajos Nagy


- Malcolm Still


- Jeff Fowler


- Alexander Weavers


- Peyman Mortazavi


- Jeremiah Oard


- Paul Sargent


- Natalie Vais


- James Cox-Morton


- Peter Snelgrove


- Stevie Hryciw


- Michael Keathley


- Simon Ekström


- Wilson Bilkovich
