# Zig Build System {#zig-build-system .title}

-   [When to bust out the Zig Build System?](#build-system)
-   [Getting Started](#getting-started)
    -   [Simple Executable](#simple)
    -   [Installing Build Artifacts](#installing-artifacts)
    -   [Adding a Convenience Step for Running the
        Application](#run-step)
-   [The Basics](#basics)
    -   [User-Provided Options](#user-options)
    -   [Standard Configuration Options](#standard-options)
    -   [Options for Conditional Compilation](#conditional-compilation)
    -   [Static Library](#static-library)
    -   [Dynamic Library](#dynamic-library)
    -   [Testing](#testing)
    -   [Linking to System Libraries](#linking-to-system-libraries)
-   [Generating Files](#generating-files)
    -   [Running System Tools](#system-tools)
    -   [Running the Project's Tools](#project-tools)
    -   [Producing Assets for `@embedFile`](#embed-file)
    -   [Generating Zig Source Code](#generating-zig)
    -   [Dealing With One or More Generated Files](#write-files)
    -   [Mutating Source Files in Place](#mutating-source)
-   [Handy Examples](#examples)
    -   [Build for multiple targets to make a release](#release)

# When to bust out the Zig Build System? {#build-system}

The fundamental commands `zig build-exe`, `zig build-lib`,
`zig build-obj`, and `zig test` are often sufficient. However, sometimes
a project needs another layer of abstraction to manage the complexity of
building from source.

For example, perhaps one of these situations applies:

-   The command line becomes too long and unwieldy, and you want some
    place to write it down.
-   You want to build many things, or the build process contains many
    steps.
-   You want to take advantage of concurrency and caching to reduce
    build time.
-   You want to expose configuration options for the project.
-   The build process is different depending on the target system and
    other options.
-   You have dependencies on other projects.
-   You want to avoid an unnecessary dependency on cmake, make, shell,
    msvc, python, etc., making the project accessible to more
    contributors.
-   You want to provide a package to be consumed by third parties.
-   You want to provide a standardized way for tools such as IDEs to
    semantically understand how to build the project.

If any of these apply, the project will benefit from using the Zig Build
System.

# Getting Started {#getting-started}

## Simple Executable {#simple}

This build script creates an executable from a Zig file that contains a
public `main` function definition.

```zig

const std = @import(&quot;std&quot;);

pub fn main() !void {
    std.debug.print(&quot;Hello World!\n&quot;, .{});
}
```

```zig

const std = @import(&quot;std&quot;);

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = &quot;hello&quot;,
        .root_module = b.createModule(.{
            .root_source_file = b.path(&quot;hello.zig&quot;),
            .target = b.graph.host,
        }),
    });

    b.installArtifact(exe);
}
```

```text
$ zig build--summary all
Build Summary: 3/3 steps succeeded
install success
+- install hello success
   +- compile exe hello Debug native success 1s MaxRSS:139M
```

## Installing Build Artifacts {#installing-artifacts}

The Zig build system, like most build systems, is based on modeling the
project as a directed acyclic graph (DAG) of steps, which are
independently and concurrently run.

By default, the main step in the graph is the **Install** step, whose
purpose is to copy build artifacts into their final resting place. The
Install step starts with no dependencies, and therefore nothing will
happen when `zig build` is run. A project's build script must add to the
set of things to install, which is what the `installArtifact` function
call does above.

**Output**

    ├── build.zig
    ├── hello.zig
    ├── .zig-cache
    └── zig-out
        └── bin
            └── hello

There are two generated directories in this output: `.zig-cache` and
`zig-out`. The first one contains files that will make subsequent builds
faster, but these files are not intended to be checked into
source-control and this directory can be completely deleted at any time
with no consequences.

The second one, `zig-out`, is an "installation prefix". This maps to the
standard file system hierarchy concept. This directory is not chosen by
the project, but by the user of `zig build` with the `--prefix` flag
(`-p` for short).

You, as the project maintainer, pick what gets put in this directory,
but the user chooses where to install it in their system. The build
script cannot hardcode output paths because this would break caching,
concurrency, and composability, as well as annoy the final user.

## Adding a Convenience Step for Running the Application {#run-step}

It is common to add a **Run** step to provide a way to run one's main
application directly from the build command.

```zig

const std = @import(&quot;std&quot;);

pub fn main() !void {
    std.debug.print(&quot;Hello World!\n&quot;, .{});
}
```

```zig

const std = @import(&quot;std&quot;);

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = &quot;hello&quot;,
        .root_module = b.createModule(.{
            .root_source_file = b.path(&quot;hello.zig&quot;),
            .target = b.graph.host,
        }),
    });

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);

    const run_step = b.step(&quot;run&quot;, &quot;Run the application&quot;);
    run_step.dependOn(&amp;run_exe.step);
}
```

```text
$ zig buildrun --summary all
Hello World!
Build Summary: 3/3 steps succeeded
run success
+- run exe hello success 1ms
   +- compile exe hello Debug native success 879ms MaxRSS:144M
```

# The Basics {#basics}

## User-Provided Options {#user-options}

Use `b.option` to make the build script configurable to end users as
well as other projects that depend on the project as a package.

```zig

const std = @import(&quot;std&quot;);

pub fn build(b: *std.Build) void {
    const windows = b.option(bool, &quot;windows&quot;, &quot;Target Microsoft Windows&quot;) orelse false;

    const exe = b.addExecutable(.{
        .name = &quot;hello&quot;,
        .root_module = b.createModule(.{
            .root_source_file = b.path(&quot;example.zig&quot;),
            .target = b.resolveTargetQuery(.{
                .os_tag = if (windows) .windows else null,
            }),
        }),
    });

    b.installArtifact(exe);
}
```

```text
$ zig build--help
Usage: /home/ci/deps/zig-x86_64-linux-0.16.0/zig build [steps] [options]

Steps:
  install (default)            Copy build artifacts to prefix path
  uninstall                    Remove build artifacts from prefix path

Project-Specific Options:
  -Dwindows=[bool]             Target Microsoft Windows

System Integration Options:
  --search-prefix [path]       Add a path to look for binaries, libraries, headers
  --sysroot [path]             Set the system root directory (usually /)
  --libc [file]                Provide a file which specifies libc paths

  --system [pkgdir]            Disable package fetching; enable all integrations
  -fsys=[name]                 Enable a system integration
  -fno-sys=[name]              Disable a system integration

  -fdarling,  -fno-darling     Integration with system-installed Darling to
                               execute macOS programs on Linux hosts
                               (default: no)
  -fqemu,     -fno-qemu        Integration with system-installed QEMU to execute
                               foreign-architecture programs on Linux hosts
                               (default: no)
  --libc-runtimes [path]       Enhances QEMU integration by providing dynamic libc
                               (e.g. glibc or musl) built for multiple foreign
                               architectures, allowing execution of non-native
                               programs that link with libc.
  -frosetta,  -fno-rosetta     Rely on Rosetta to execute x86_64 programs on
                               ARM64 macOS hosts. (default: no)
  -fwasmtime, -fno-wasmtime    Integration with system-installed wasmtime to
                               execute WASI binaries. (default: no)
  -fwine,     -fno-wine        Integration with system-installed Wine to execute
                               Windows programs on Linux hosts. (default: no)

  Available System Integrations:                Enabled:
  (none)                                        -

General Options:
  -h, --help                   Print this help and exit
  -l, --list-steps             Print available steps

  -p, --prefix [path]          Where to install files (default: zig-out)
  --prefix-lib-dir [path]      Where to install libraries
  --prefix-exe-dir [path]      Where to install executables
  --prefix-include-dir [path]  Where to install C header files
  --release[=mode]             Request release mode, optionally specifying a
                               preferred optimization mode: fast, safe, small

  --verbose                    Print commands before executing them
  --color [auto|off|on]        Enable or disable colored error messages
  --error-style [style]        Control how build errors are printed
    verbose                    (Default) Report errors with full context
    minimal                    Report errors after summary, excluding context like command lines
    verbose_clear              Like &#39;verbose&#39;, but clear the terminal at the start of each update
    minimal_clear              Like &#39;minimal&#39;, but clear the terminal at the start of each update
  --multiline-errors [style]   Control how multi-line error messages are printed
    indent                     (Default) Indent non-initial lines to align with initial line
    newline                    Include a leading newline so that the error message is on its own lines
    none                       Print as usual so the first line is misaligned
  --summary [mode]             Control the printing of the build summary
    all                        Print the build summary in its entirety
    new                        Omit cached steps
    failures                   (Default if short-lived) Only print failed steps
    line                       (Default if long-lived) Only print the single-line summary
    none                       Do not print the build summary
  -j&lt;N&gt;                        Limit concurrent jobs (default is to use all CPU cores)
  --maxrss &lt;bytes&gt;             Limit memory usage (default is to use available memory)
  --skip-oom-steps             Instead of failing, skip steps that would exceed --maxrss
  --test-timeout &lt;timeout&gt;     Limit execution time of unit tests, terminating if exceeded.
                               The timeout must include a unit: ns, us, ms, s, m, h
  --watch                      Continuously rebuild when source files are modified
  --debounce &lt;ms&gt;              Delay before rebuilding after changed file detected
  --webui[=ip]                 Enable the web interface on the given IP address
  --fuzz[=limit]               Continuously search for unit test failures with an optional
                               limit to the max number of iterations. The argument supports
                               an optional &#39;K&#39;, &#39;M&#39;, or &#39;G&#39; suffix (e.g. &#39;10K&#39;). Implies
                               &#39;--webui&#39; when no limit is specified.
  --time-report                Force full rebuild and provide detailed information on
                               compilation time of Zig source code (implies &#39;--webui&#39;)
     -fincremental             Enable incremental compilation
  -fno-incremental             Disable incremental compilation

Package Management Options:
  --fetch[=mode]               Fetch dependency tree (optionally choose laziness) and exit
    needed                     (Default) Lazy dependencies are fetched as needed
    all                        Lazy dependencies are always fetched
  --fork=[path]                Override one or more projects from dependency tree

Advanced Options:
  -freference-trace[=num]      How many lines of reference trace should be shown per compile error
  -fno-reference-trace         Disable reference trace
  -fallow-so-scripts           Allows .so files to be GNU ld scripts
  -fno-allow-so-scripts        (default) .so files must be ELF files
  --build-file [file]          Override path to build.zig
  --cache-dir [path]           Override path to local Zig cache directory
  --global-cache-dir [path]    Override path to global Zig cache directory
  --zig-lib-dir [arg]          Override path to Zig lib directory
  --build-runner [file]        Override path to build runner
  --seed [integer]             For shuffling dependency traversal order (default: random)
  --build-id[=style]           At a minor link-time expense, embeds a build ID in binaries
      fast                     8-byte non-cryptographic hash (COFF, ELF, WASM)
      sha1, tree               20-byte cryptographic hash (ELF, WASM)
      md5                      16-byte cryptographic hash (ELF)
      uuid                     16-byte random UUID (ELF, WASM)
      0x[hexstring]            Constant ID, maximum 32 bytes (ELF, WASM)
      none                     (default) No build ID
  --debug-log [scope]          Enable debugging the compiler
  --debug-pkg-config           Fail if unknown pkg-config flags encountered
  --debug-rt                   Debug compiler runtime libraries
  --verbose-link               Enable compiler debug output for linking
  --verbose-air                Enable compiler debug output for Zig AIR
  --verbose-llvm-ir[=file]     Enable compiler debug output for LLVM IR
  --verbose-llvm-bc=[file]     Enable compiler debug output for LLVM BC
  --verbose-cimport            Enable compiler debug output for C imports
  --verbose-cc                 Enable compiler debug output for C compilation
  --verbose-llvm-cpu-features  Enable compiler debug output for LLVM CPU features
```

```zig

const std = @import(&quot;std&quot;);

pub fn main() !void {
    std.debug.print(&quot;Hello World!\n&quot;, .{});
}
```

Please direct your attention to these lines:

    Project-Specific Options:
      -Dwindows=[bool]             Target Microsoft Windows

This part of the help menu is auto-generated based on running the
`build.zig` logic. Users can discover configuration options of the build
script this way.

## Standard Configuration Options {#standard-options}

Previously, we used a boolean flag to indicate building for Windows.
However, we can do better.

Most projects want to provide the ability to change the target and
optimization settings. In order to encourage standard naming conventions
for these options, Zig provides the helper functions,
`standardTargetOptions` and `standardOptimizeOption`.

Standard target options allows the person running `zig build` to choose
what target to build for. By default, any target is allowed, and no
choice means to target the host system. Other options for restricting
supported target set are available.

Standard optimization options allow the person running `zig build` to
select between `Debug`, `ReleaseSafe`, `ReleaseFast`, and
`ReleaseSmall`. By default none of the release options are considered
the preferable choice by the build script, and the user must make a
decision in order to create a release build.

```zig

const std = @import(&quot;std&quot;);

pub fn main() !void {
    std.debug.print(&quot;Hello World!\n&quot;, .{});
}
```

```zig

const std = @import(&quot;std&quot;);

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = &quot;hello&quot;,
        .root_module = b.createModule(.{
            .root_source_file = b.path(&quot;hello.zig&quot;),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(exe);
}
```

```text
$ zig build-Dtarget=x86_64-windows -Doptimize=ReleaseSmall --summary all
Build Summary: 3/3 steps succeeded
install success
+- install hello success
   +- compile exe hello ReleaseSmall x86_64-windows success 3s MaxRSS:155M
```

Now, our `--help` menu contains more items:

    Project-Specific Options:
      -Dtarget=[string]            The CPU architecture, OS, and ABI to build for
      -Dcpu=[string]               Target CPU features to add or subtract
      -Doptimize=[enum]            Prioritize performance, safety, or binary size (-O flag)
                                     Supported Values:
                                       Debug
                                       ReleaseSafe
                                       ReleaseFast
                                       ReleaseSmall

It is entirely possible to create these options via `b.option` directly,
but this API provides a commonly used naming convention for these
frequently used settings.

In our terminal output, observe that we passed
`-Dtarget=x86_64-windows -Doptimize=ReleaseSmall`. Compared to the first
example, now we see different files in the installation prefix:

    zig-out/
    └── bin
        └── hello.exe

## Options for Conditional Compilation {#conditional-compilation}

To pass options from the build script and into the project's Zig code,
use the `Options` step.

```zig

const std = @import(&quot;std&quot;);
const config = @import(&quot;config&quot;);

const semver = std.SemanticVersion.parse(config.version) catch unreachable;

extern fn foo_bar() void;

pub fn main() !void {
    if (semver.major &lt; 1) {
        @compileError(&quot;too old&quot;);
    }
    std.debug.print(&quot;version: {s}\n&quot;, .{config.version});

    if (config.have_libfoo) {
        foo_bar();
    }
}
```

```zig

const std = @import(&quot;std&quot;);

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = &quot;app&quot;,
        .root_module = b.createModule(.{
            .root_source_file = b.path(&quot;app.zig&quot;),
            .target = b.graph.host,
        }),
    });

    const version = b.option([]const u8, &quot;version&quot;, &quot;application version string&quot;) orelse &quot;0.0.0&quot;;
    const enable_foo = detectWhetherToEnableLibFoo();

    const options = b.addOptions();
    options.addOption([]const u8, &quot;version&quot;, version);
    options.addOption(bool, &quot;have_libfoo&quot;, enable_foo);

    exe.root_module.addOptions(&quot;config&quot;, options);

    b.installArtifact(exe);
}

fn detectWhetherToEnableLibFoo() bool {
    return false;
}
```

```text
$ zig build-Dversion=1.2.3 --summary all
Build Summary: 4/4 steps succeeded
install success
+- install app success
   +- compile exe app Debug native success 1s MaxRSS:143M
      +- options success
```

In this example, the data provided by `@import("config")` is
comptime-known, preventing the `@compileError` from triggering. If we
had passed `-Dversion=0.2.3` or omitted the option, then we would have
seen the compilation of `app.zig` fail with the "too old" error.

## Static Library {#static-library}

This build script creates a static library from Zig code, and then also
an executable from other Zig code that consumes it.

```zig

export fn fizzbuzz(n: usize) ?[*:0]const u8 {
    if (n % 5 == 0) {
        if (n % 3 == 0) {
            return &quot;fizzbuzz&quot;;
        } else {
            return &quot;fizz&quot;;
        }
    } else if (n % 3 == 0) {
        return &quot;buzz&quot;;
    }
    return null;
}
```

```zig

const std = @import(&quot;std&quot;);
const Io = std.Io;

extern fn fizzbuzz(n: usize) ?[*:0]const u8;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buf: [1024]u8 = undefined;
    const file_writer = Io.File.stdout().writer(io, &amp;buf);
    const w = &amp;file_writer.interface;
    for (0..100) |n| {
        if (fizzbuzz(n)) |s| {
            try w.print(&quot;{s}\n&quot;, .{s});
        } else {
            try w.print(&quot;{d}\n&quot;, .{n});
        }
    }
    try w.flush();
}
```

```zig

const std = @import(&quot;std&quot;);

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libfizzbuzz = b.addLibrary(.{
        .name = &quot;fizzbuzz&quot;,
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path(&quot;fizzbuzz.zig&quot;),
            .target = target,
            .optimize = optimize,
        }),
    });

    const exe = b.addExecutable(.{
        .name = &quot;demo&quot;,
        .root_module = b.createModule(.{
            .root_source_file = b.path(&quot;demo.zig&quot;),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.root_module.linkLibrary(libfizzbuzz);

    b.installArtifact(libfizzbuzz);

    if (b.option(bool, &quot;enable-demo&quot;, &quot;install the demo too&quot;) orelse false) {
        b.installArtifact(exe);
    }
}
```

```text
$ zig build--summary all
Build Summary: 3/3 steps succeeded
install success
+- install fizzbuzz success
   +- compile lib fizzbuzz Debug native success 209ms MaxRSS:93M
```

In this case, only the static library ends up being installed:

    zig-out/
    └── lib
        └── libfizzbuzz.a

However, if you look closely, the build script contains an option to
also install the demo. If we additionally pass `-Denable-demo`, then we
see this in the installation prefix:

    zig-out/
    ├── bin
    │   └── demo
    └── lib
        └── libfizzbuzz.a

Note that despite the unconditional call to `addExecutable`, the build
system in fact does not waste any time building the `demo` executable
unless it is requested with `-Denable-demo`, because the build system is
based on a Directed Acyclic Graph with dependency edges.

## Dynamic Library {#dynamic-library}

Here we keep all the files the same from the [Static
Library](#static-library) example, except the `build.zig` file is
changed.

```zig

const std = @import(&quot;std&quot;);

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libfizzbuzz = b.addLibrary(.{
        .name = &quot;fizzbuzz&quot;,
        .linkage = .dynamic,
        .version = .{ .major = 1, .minor = 2, .patch = 3 },
        .root_module = b.createModule(.{
            .root_source_file = b.path(&quot;fizzbuzz.zig&quot;),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(libfizzbuzz);
}
```

```text
$ zig build--summary all
Build Summary: 3/3 steps succeeded
install success
+- install fizzbuzz success
   +- compile lib fizzbuzz Debug native success 831ms MaxRSS:142M
```

**Output**

    zig-out
    └── lib
        ├── libfizzbuzz.so -> libfizzbuzz.so.1
        ├── libfizzbuzz.so.1 -> libfizzbuzz.so.1.2.3
        └── libfizzbuzz.so.1.2.3

As in the static library example, to make an executable link against it,
use code like this:

```zig
exe.linkLibrary(libfizzbuzz);
```

## Testing {#testing}

Individual files can be tested directly with `zig test foo.zig`,
however, more complex use cases can be solved by orchestrating testing
via the build script.

When using the build script, unit tests are broken into two different
steps in the build graph, the **Compile** step and the **Run** step.
Without a call to `addRunArtifact`, which establishes a dependency edge
between these two steps, the unit tests will not be executed.

The *Compile* step can be configured the same as any executable,
library, or object file, for example by [linking against system
libraries](#linking-to-system-libraries), setting target options, or
adding additional compilation units.

The *Run* step can be configured the same as any Run step, for example
by skipping execution when the host is not capable of executing the
binary.

When using the build system to run unit tests, the build runner and the
test runner communicate via *stdin* and *stdout* in order to run
multiple unit test suites concurrently, and report test failures in a
meaningful way without having their output jumbled together. This is one
reason why [writing to *standard out* in unit tests is
problematic](https://github.com/ziglang/zig/issues/15091){target="_blank"} -
it will interfere with this communication channel. On the flip side,
this mechanism will enable an upcoming feature, which is is the [ability
for a unit test to expect a
*panic*](https://github.com/ziglang/zig/issues/1356){target="_blank"}.

```zig

const std = @import(&quot;std&quot;);

test &quot;simple test&quot; {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit();
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
```

```zig

const std = @import(&quot;std&quot;);

const test_targets = [_]std.Target.Query{
    .{}, // native
    .{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
    },
    .{
        .cpu_arch = .aarch64,
        .os_tag = .macos,
    },
};

pub fn build(b: *std.Build) void {
    const test_step = b.step(&quot;test&quot;, &quot;Run unit tests&quot;);

    for (test_targets) |target| {
        const unit_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(&quot;main.zig&quot;),
                .target = b.resolveTargetQuery(target),
            }),
        });

        const run_unit_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&amp;run_unit_tests.step);
    }
}
```

```text
$ zig buildtest --summary all
test
+- run test
   +- compile test Debug x86_64-linux 1 errors
/home/ci/.cache/act/6303cd4d50321361/hostexecutor/zig-code/build-system/unit-testing/main.zig:4:34: error: struct &#39;array_list.Aligned(i32,null)&#39; has no member named &#39;init&#39;
    var list = std.ArrayList(i32).init(std.testing.allocator);
               ~~~~~~~~~~~~~~~~~~^~~~~
/home/ci/deps/zig-x86_64-linux-0.16.0/lib/std/array_list.zig:576:12: note: struct declared here
    return struct {
           ^~~~~~
error: 1 compilation errors
failed command: /home/ci/deps/zig-x86_64-linux-0.16.0/zig test -target x86_64-linux -mcpu baseline -Mroot=../../../zig-code/build-system/unit-testing/main.zig --cache-dir /home/ci/.cache/act/6303cd4d50321361/hostexecutor/zig-code/build-system/unit-testing/.zig-cache --global-cache-dir /home/ci/.cache/zig --name test --zig-lib-dir /home/ci/deps/zig-x86_64-linux-0.16.0/lib/ --listen=-

test
+- run test
   +- compile test Debug native 1 errors
/home/ci/.cache/act/6303cd4d50321361/hostexecutor/zig-code/build-system/unit-testing/main.zig:4:34: error: struct &#39;array_list.Aligned(i32,null)&#39; has no member named &#39;init&#39;
    var list = std.ArrayList(i32).init(std.testing.allocator);
               ~~~~~~~~~~~~~~~~~~^~~~~
/home/ci/deps/zig-x86_64-linux-0.16.0/lib/std/array_list.zig:576:12: note: struct declared here
    return struct {
           ^~~~~~
error: 1 compilation errors
failed command: /home/ci/deps/zig-x86_64-linux-0.16.0/zig test -Mroot=../../../zig-code/build-system/unit-testing/main.zig --cache-dir /home/ci/.cache/act/6303cd4d50321361/hostexecutor/zig-code/build-system/unit-testing/.zig-cache --global-cache-dir /home/ci/.cache/zig --name test --zig-lib-dir /home/ci/deps/zig-x86_64-linux-0.16.0/lib/ --listen=-

test
+- run test
   +- compile test Debug aarch64-macos 1 errors
/home/ci/.cache/act/6303cd4d50321361/hostexecutor/zig-code/build-system/unit-testing/main.zig:4:34: error: struct &#39;array_list.Aligned(i32,null)&#39; has no member named &#39;init&#39;
    var list = std.ArrayList(i32).init(std.testing.allocator);
               ~~~~~~~~~~~~~~~~~~^~~~~
/home/ci/deps/zig-x86_64-linux-0.16.0/lib/std/array_list.zig:576:12: note: struct declared here
    return struct {
           ^~~~~~
error: 1 compilation errors
failed command: /home/ci/deps/zig-x86_64-linux-0.16.0/zig test -target aarch64-macos -mcpu baseline -Mroot=../../../zig-code/build-system/unit-testing/main.zig --cache-dir /home/ci/.cache/act/6303cd4d50321361/hostexecutor/zig-code/build-system/unit-testing/.zig-cache --global-cache-dir /home/ci/.cache/zig --name test --zig-lib-dir /home/ci/deps/zig-x86_64-linux-0.16.0/lib/ --listen=-

Build Summary: 0/7 steps succeeded (3 failed)
test transitive failure
+- run test transitive failure
|  +- compile test Debug native 1 errors
+- run test transitive failure
|  +- compile test Debug x86_64-linux 1 errors
+- run test transitive failure
   +- compile test Debug aarch64-macos 1 errors

error: the following build command failed with exit code 1:
/home/ci/.cache/act/6303cd4d50321361/hostexecutor/zig-code/build-system/unit-testing/.zig-cache/o/37028e3218a0a3409d6d8394982bc7a0/build /home/ci/deps/zig-x86_64-linux-0.16.0/zig /home/ci/deps/zig-x86_64-linux-0.16.0/lib ../../../zig-code/build-system/unit-testing /home/ci/.cache/act/6303cd4d50321361/hostexecutor/zig-code/build-system/unit-testing/.zig-cache /home/ci/.cache/zig --seed 0x88ef6700 -Ze20aa4bd366af3ea test --summary all
```

In this case it might be a nice adjustment to enable
`skip_foreign_checks` for the unit tests:

``` diff
@@ -23,6 +23,7 @@
         });

         const run_unit_tests = b.addRunArtifact(unit_tests);
+        run_unit_tests.skip_foreign_checks = true;
         test_step.dependOn(&run_unit_tests.step);
     }
 }
```

```zig

const std = @import(&quot;std&quot;);

const test_targets = [_]std.Target.Query{
    .{}, // native
    .{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
    },
    .{
        .cpu_arch = .aarch64,
        .os_tag = .macos,
    },
};

pub fn build(b: *std.Build) void {
    const test_step = b.step(&quot;test&quot;, &quot;Run unit tests&quot;);

    for (test_targets) |target| {
        const unit_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(&quot;main.zig&quot;),
                .target = b.resolveTargetQuery(target),
            }),
        });

        const run_unit_tests = b.addRunArtifact(unit_tests);
        run_unit_tests.skip_foreign_checks = true;
        test_step.dependOn(&amp;run_unit_tests.step);
    }
}

// zig-doctest: build-system --collapseable -- test --summary all
```

```text
$ zig build--summary all
Build Summary: 1/1 steps succeeded
install cached
```

## Linking to System Libraries {#linking-to-system-libraries}

For satisfying library dependencies, there are two choices:

1.  Provide these libraries via the Zig Build System (see [Package
    Management](#) and [Static Library](#static-library)).
2.  Use the files provided by the host system.

For the use case of upstream project maintainers, obtaining these
libraries via the Zig Build System provides the least friction and puts
the configuration power in the hands of those maintainers. Everyone who
builds this way will have reproducible, consistent results as each
other, and it will work on every operating system and even support
cross-compilation. Furthermore, it allows the project to decide with
perfect precision the exact versions of its entire dependency tree it
wishes to build against. This is expected to be the generally preferred
way to depend on external libraries.

However, for the use case of packaging software into repositories such
as Debian, Homebrew, or Nix, it is mandatory to link against system
libraries. So, build scripts must [detect the build
mode](https://github.com/ziglang/zig/issues/14281){target="_blank"} and
configure accordingly.

```zig

const std = @import(&quot;std&quot;);

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = &quot;zip&quot;,
        .root_module = b.createModule(.{
            .root_source_file = b.path(&quot;zip.zig&quot;),
            .target = b.graph.host,
            .link_libc = true,
        }),
    });

    exe.root_module.linkSystemLibrary(&quot;z&quot;, .{});

    b.installArtifact(exe);
}
```

```text
$ zig build--summary all
Build Summary: 3/3 steps succeeded
install success
+- install zip success
   +- compile exe zip Debug native success 873ms MaxRSS:138M
```

Users of `zig build` may use `--search-prefix` to provide additional
directories that are considered "system directories" for the purposes of
finding static and dynamic libraries.

# Generating Files {#generating-files}

## Running System Tools {#system-tools}

This version of hello world expects to find a `word.txt` file in the
same path, and we want to use a system tool to generate it starting from
a JSON file.

Be aware that system dependencies will make your project harder to build
for your users. This build script depends on `jq`, for example, which is
not present by default in most Linux distributions and which might be an
unfamiliar tool for Windows users.

The next section will replace `jq` with a Zig tool included in the
source tree, which is the preferred approach.

**`words.json`**

``` json
{
  "en": "world",
  "it": "mondo",
  "ja": "世界"
}
```

```zig

const std = @import(&quot;std&quot;);
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    const self_exe_dir_path = try std.process.executableDirPathAlloc(io, arena);
    var self_exe_dir = try Io.Dir.cwd().openDir(io, self_exe_dir_path, .{});
    defer self_exe_dir.close(io);

    const word = try self_exe_dir.readFileAlloc(io, &quot;word.txt&quot;, arena, .limited(1000));

    var stdout_buffer: [1000]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &amp;stdout_buffer);
    const stdout = &amp;stdout_writer.interface;

    try stdout.print(&quot;Hello {s}\n&quot;, .{word});
    try stdout.flush();
}
```

```zig

const std = @import(&quot;std&quot;);

pub fn build(b: *std.Build) void {
    const lang = b.option([]const u8, &quot;language&quot;, &quot;language of the greeting&quot;) orelse &quot;en&quot;;
    const tool_run = b.addSystemCommand(&amp;.{&quot;jq&quot;});
    tool_run.addArgs(&amp;.{
        b.fmt(
            \\.[&quot;{s}&quot;]
        , .{lang}),
        &quot;-r&quot;, // raw output to omit quotes around the selected string
    });
    tool_run.addFileArg(b.path(&quot;words.json&quot;));

    const output = tool_run.captureStdOut(.{});

    b.getInstallStep().dependOn(&amp;b.addInstallFileWithDir(output, .prefix, &quot;word.txt&quot;).step);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = &quot;hello&quot;,
        .root_module = b.createModule(.{
            .root_source_file = b.path(&quot;src/main.zig&quot;),
            .target = target,
            .optimize = optimize,
        }),
    });

    const install_artifact = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .prefix },
    });
    b.getInstallStep().dependOn(&amp;install_artifact.step);
}
```

```text
$ zig build-Dlanguage=ja --summary all
Build Summary: 5/5 steps succeeded
install success
+- install generated to word.txt success
|  +- run jq success 40ms
+- install hello success
   +- compile exe hello Debug native success 1s MaxRSS:145M
```

**Output**

    zig-out
    ├── hello
    └── word.txt

Note how `captureStdOut` creates a temporary file with the output of the
`jq` invocation.

## Running the Project's Tools {#project-tools}

This version of hello world expects to find a `word.txt` file in the
same path, and we want to produce it at build-time by invoking a Zig
program on a JSON file.

**`tools/words.json`**

``` json
{
  "en": "world",
  "it": "mondo",
  "ja": "世界"
}
```

```zig

const std = @import(&quot;std&quot;);
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    const self_exe_dir_path = try std.process.executableDirPathAlloc(io, arena);
    var self_exe_dir = try Io.Dir.cwd().openDir(io, self_exe_dir_path, .{});
    defer self_exe_dir.close(io);

    const word = try self_exe_dir.readFileAlloc(io, &quot;word.txt&quot;, arena, .limited(1000));

    var stdout_buffer: [1000]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &amp;stdout_buffer);
    const stdout = &amp;stdout_writer.interface;

    try stdout.print(&quot;Hello {s}\n&quot;, .{word});
    try stdout.flush();
}
```

```zig

const std = @import(&quot;std&quot;);
const Io = std.Io;

const usage =
    \\Usage: ./word_select [options]
    \\
    \\Options:
    \\  --input-file INPUT_JSON_FILE
    \\  --output-file OUTPUT_TXT_FILE
    \\  --lang LANG
    \\
;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);

    var opt_input_file_path: ?[]const u8 = null;
    var opt_output_file_path: ?[]const u8 = null;
    var opt_lang: ?[]const u8 = null;

    {
        var i: usize = 1;
        while (i &lt; args.len) : (i += 1) {
            const arg = args[i];
            if (std.mem.eql(u8, &quot;-h&quot;, arg) or std.mem.eql(u8, &quot;--help&quot;, arg)) {
                try Io.File.stdout().writeStreamingAll(io, usage);
                return std.process.cleanExit(io);
            } else if (std.mem.eql(u8, &quot;--input-file&quot;, arg)) {
                i += 1;
                if (i &gt; args.len) fatal(&quot;expected arg after &#39;{s}&#39;&quot;, .{arg});
                if (opt_input_file_path != null) fatal(&quot;duplicated {s} argument&quot;, .{arg});
                opt_input_file_path = args[i];
            } else if (std.mem.eql(u8, &quot;--output-file&quot;, arg)) {
                i += 1;
                if (i &gt; args.len) fatal(&quot;expected arg after &#39;{s}&#39;&quot;, .{arg});
                if (opt_output_file_path != null) fatal(&quot;duplicated {s} argument&quot;, .{arg});
                opt_output_file_path = args[i];
            } else if (std.mem.eql(u8, &quot;--lang&quot;, arg)) {
                i += 1;
                if (i &gt; args.len) fatal(&quot;expected arg after &#39;{s}&#39;&quot;, .{arg});
                if (opt_lang != null) fatal(&quot;duplicated {s} argument&quot;, .{arg});
                opt_lang = args[i];
            } else {
                fatal(&quot;unrecognized arg: &#39;{s}&#39;&quot;, .{arg});
            }
        }
    }

    const input_file_path = opt_input_file_path orelse fatal(&quot;missing --input-file&quot;, .{});
    const output_file_path = opt_output_file_path orelse fatal(&quot;missing --output-file&quot;, .{});
    const lang = opt_lang orelse fatal(&quot;missing --lang&quot;, .{});

    var input_file = Io.Dir.cwd().openFile(io, input_file_path, .{}) catch |err| {
        fatal(&quot;unable to open &#39;{s}&#39;: {s}&quot;, .{ input_file_path, @errorName(err) });
    };
    defer input_file.close(io);
    var input_file_buffer: [1000]u8 = undefined;
    var input_file_reader = input_file.reader(io, &amp;input_file_buffer);

    var output_file = Io.Dir.cwd().createFile(io, output_file_path, .{}) catch |err| {
        fatal(&quot;unable to open &#39;{s}&#39;: {s}&quot;, .{ output_file_path, @errorName(err) });
    };
    defer output_file.close(io);

    var json_reader: std.json.Reader = .init(arena, &amp;input_file_reader.interface);
    var words = try std.json.ArrayHashMap([]const u8).jsonParse(arena, &amp;json_reader, .{
        .allocate = .alloc_if_needed,
        .max_value_len = 1000,
    });

    const w = words.map.get(lang) orelse fatal(&quot;Lang not found in JSON file&quot;, .{});

    try output_file.writeStreamingAll(io, w);
    return std.process.cleanExit(io);
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
```

```zig

const std = @import(&quot;std&quot;);

pub fn build(b: *std.Build) void {
    const lang = b.option([]const u8, &quot;language&quot;, &quot;language of the greeting&quot;) orelse &quot;en&quot;;
    const tool = b.addExecutable(.{
        .name = &quot;word_select&quot;,
        .root_module = b.createModule(.{
            .root_source_file = b.path(&quot;tools/word_select.zig&quot;),
            .target = b.graph.host,
        }),
    });

    const tool_step = b.addRunArtifact(tool);
    tool_step.addArg(&quot;--input-file&quot;);
    tool_step.addFileArg(b.path(&quot;tools/words.json&quot;));
    tool_step.addArg(&quot;--output-file&quot;);
    const output = tool_step.addOutputFileArg(&quot;word.txt&quot;);
    tool_step.addArgs(&amp;.{ &quot;--lang&quot;, lang });

    b.getInstallStep().dependOn(&amp;b.addInstallFileWithDir(output, .prefix, &quot;word.txt&quot;).step);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = &quot;hello&quot;,
        .root_module = b.createModule(.{
            .root_source_file = b.path(&quot;src/main.zig&quot;),
            .target = target,
            .optimize = optimize,
        }),
    });

    const install_artifact = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .prefix },
    });
    b.getInstallStep().dependOn(&amp;install_artifact.step);
}
```

```text
$ zig build--summary all
Build Summary: 6/6 steps succeeded
install success
+- install generated to word.txt success
|  +- run exe word_select (word.txt) success 39ms
|     +- compile exe word_select Debug native success 1s MaxRSS:148M
+- install hello success
   +- compile exe hello Debug native success 1s MaxRSS:154M
```

**Output**

    zig-out
    ├── hello
    └── word.txt

## Producing Assets for `@embedFile` {#embed-file}

This version of hello world wants to `@embedFile` an asset generated at
build time, which we're going to produce using a tool written in Zig.

**`tools/words.json`**

``` json
{
  "en": "world",
  "it": "mondo",
  "ja": "世界"
}
```

```zig

const std = @import(&quot;std&quot;);
const word = @embedFile(&quot;word&quot;);

pub fn main() !void {
    std.log.info(&quot;Hello {s}\n&quot;, .{word});
}
```

```zig

const std = @import(&quot;std&quot;);
const Io = std.Io;

const usage =
    \\Usage: ./word_select [options]
    \\
    \\Options:
    \\  --input-file INPUT_JSON_FILE
    \\  --output-file OUTPUT_TXT_FILE
    \\  --lang LANG
    \\
;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);

    var opt_input_file_path: ?[]const u8 = null;
    var opt_output_file_path: ?[]const u8 = null;
    var opt_lang: ?[]const u8 = null;

    {
        var i: usize = 1;
        while (i &lt; args.len) : (i += 1) {
            const arg = args[i];
            if (std.mem.eql(u8, &quot;-h&quot;, arg) or std.mem.eql(u8, &quot;--help&quot;, arg)) {
                try Io.File.stdout().writeStreamingAll(io, usage);
                return std.process.cleanExit(io);
            } else if (std.mem.eql(u8, &quot;--input-file&quot;, arg)) {
                i += 1;
                if (i &gt; args.len) fatal(&quot;expected arg after &#39;{s}&#39;&quot;, .{arg});
                if (opt_input_file_path != null) fatal(&quot;duplicated {s} argument&quot;, .{arg});
                opt_input_file_path = args[i];
            } else if (std.mem.eql(u8, &quot;--output-file&quot;, arg)) {
                i += 1;
                if (i &gt; args.len) fatal(&quot;expected arg after &#39;{s}&#39;&quot;, .{arg});
                if (opt_output_file_path != null) fatal(&quot;duplicated {s} argument&quot;, .{arg});
                opt_output_file_path = args[i];
            } else if (std.mem.eql(u8, &quot;--lang&quot;, arg)) {
                i += 1;
                if (i &gt; args.len) fatal(&quot;expected arg after &#39;{s}&#39;&quot;, .{arg});
                if (opt_lang != null) fatal(&quot;duplicated {s} argument&quot;, .{arg});
                opt_lang = args[i];
            } else {
                fatal(&quot;unrecognized arg: &#39;{s}&#39;&quot;, .{arg});
            }
        }
    }

    const input_file_path = opt_input_file_path orelse fatal(&quot;missing --input-file&quot;, .{});
    const output_file_path = opt_output_file_path orelse fatal(&quot;missing --output-file&quot;, .{});
    const lang = opt_lang orelse fatal(&quot;missing --lang&quot;, .{});

    var input_file = Io.Dir.cwd().openFile(io, input_file_path, .{}) catch |err| {
        fatal(&quot;unable to open &#39;{s}&#39;: {s}&quot;, .{ input_file_path, @errorName(err) });
    };
    defer input_file.close(io);
    var input_file_buffer: [1000]u8 = undefined;
    var input_file_reader = input_file.reader(io, &amp;input_file_buffer);

    var output_file = Io.Dir.cwd().createFile(io, output_file_path, .{}) catch |err| {
        fatal(&quot;unable to open &#39;{s}&#39;: {s}&quot;, .{ output_file_path, @errorName(err) });
    };
    defer output_file.close(io);

    var json_reader: std.json.Reader = .init(arena, &amp;input_file_reader.interface);
    var words = try std.json.ArrayHashMap([]const u8).jsonParse(arena, &amp;json_reader, .{
        .allocate = .alloc_if_needed,
        .max_value_len = 1000,
    });

    const w = words.map.get(lang) orelse fatal(&quot;Lang not found in JSON file&quot;, .{});

    try output_file.writeStreamingAll(io, w);
    return std.process.cleanExit(io);
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
```

```zig

const std = @import(&quot;std&quot;);

pub fn build(b: *std.Build) void {
    const lang = b.option([]const u8, &quot;language&quot;, &quot;language of the greeting&quot;) orelse &quot;en&quot;;
    const tool = b.addExecutable(.{
        .name = &quot;word_select&quot;,
        .root_module = b.createModule(.{
            .root_source_file = b.path(&quot;tools/word_select.zig&quot;),
            .target = b.graph.host,
        }),
    });

    const tool_step = b.addRunArtifact(tool);
    tool_step.addArg(&quot;--input-file&quot;);
    tool_step.addFileArg(b.path(&quot;tools/words.json&quot;));
    tool_step.addArg(&quot;--output-file&quot;);
    const output = tool_step.addOutputFileArg(&quot;word.txt&quot;);
    tool_step.addArgs(&amp;.{ &quot;--lang&quot;, lang });

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = &quot;hello&quot;,
        .root_module = b.createModule(.{
            .root_source_file = b.path(&quot;src/main.zig&quot;),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.root_module.addAnonymousImport(&quot;word&quot;, .{
        .root_source_file = output,
    });

    b.installArtifact(exe);
}
```

```text
$ zig build--summary all
Build Summary: 5/5 steps succeeded
install success
+- install hello success
   +- compile exe hello Debug native success 471ms MaxRSS:145M
      +- run exe word_select (word.txt) success 10ms
         +- compile exe word_select Debug native success 427ms MaxRSS:153M
```

**Output**

    zig-out/
    └── bin
        └── hello

## Generating Zig Source Code {#generating-zig}

This build file uses a Zig program to generate a Zig file and then
exposes it to the main program as a module dependency.

```zig

const std = @import(&quot;std&quot;);
const Person = @import(&quot;person&quot;).Person;

pub fn main() !void {
    const p: Person = .{};
    std.log.info(&quot;Hello {any}\n&quot;, .{p});
}
```

```zig

const std = @import(&quot;std&quot;);
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);

    if (args.len != 2) fatal(&quot;wrong number of arguments&quot;, .{});

    const output_file_path = args[1];

    var output_file = Io.Dir.cwd().createFile(io, output_file_path, .{}) catch |err| {
        fatal(&quot;unable to open &#39;{s}&#39;: {s}&quot;, .{ output_file_path, @errorName(err) });
    };
    defer output_file.close(io);

    try output_file.writeStreamingAll(io,
        \\pub const Person = struct {
        \\   age: usize = 18,
        \\   name: []const u8 = &quot;foo&quot;
        \\};
    );
    return std.process.cleanExit(io);
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
```

```zig

const std = @import(&quot;std&quot;);

pub fn build(b: *std.Build) void {
    const tool = b.addExecutable(.{
        .name = &quot;generate_struct&quot;,
        .root_module = b.createModule(.{
            .root_source_file = b.path(&quot;tools/generate_struct.zig&quot;),
            .target = b.graph.host,
        }),
    });

    const tool_step = b.addRunArtifact(tool);
    const output = tool_step.addOutputFileArg(&quot;person.zig&quot;);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = &quot;hello&quot;,
        .root_module = b.createModule(.{
            .root_source_file = b.path(&quot;src/main.zig&quot;),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.root_module.addAnonymousImport(&quot;person&quot;, .{
        .root_source_file = output,
    });

    b.installArtifact(exe);
}
```

```text
$ zig build--summary all
Build Summary: 5/5 steps succeeded
install success
+- install hello success
   +- compile exe hello Debug native success 726ms MaxRSS:143M
      +- run exe generate_struct (person.zig) success 20ms
         +- compile exe generate_struct Debug native success 942ms MaxRSS:153M
```

**Output**

    zig-out/
    └── bin
        └── hello

## Dealing With One or More Generated Files {#write-files}

The **WriteFiles** step provides a way to generate one or more files
which share a parent directory. The generated directory lives inside the
local `.zig-cache`, and each generated file is independently available
as a `std.Build.LazyPath`. The parent directory itself is also available
as a `LazyPath`.

This API supports writing arbitrary strings to the generated directory
as well as copying files into it.

```zig

const std = @import(&quot;std&quot;);

pub fn main() !void {
    std.debug.print(&quot;hello world\n&quot;, .{});
}
```

```zig

const std = @import(&quot;std&quot;);

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = &quot;app&quot;,
        .root_module = b.createModule(.{
            .root_source_file = b.path(&quot;src/main.zig&quot;),
            .target = b.graph.host,
        }),
    });

    const version = b.option([]const u8, &quot;version&quot;, &quot;application version string&quot;) orelse &quot;0.0.0&quot;;

    const wf = b.addWriteFiles();
    const app_exe_name = b.fmt(&quot;project/{s}&quot;, .{exe.out_filename});
    _ = wf.addCopyFile(exe.getEmittedBin(), app_exe_name);
    _ = wf.add(&quot;project/version.txt&quot;, version);

    const tar = b.addSystemCommand(&amp;.{ &quot;tar&quot;, &quot;czf&quot; });
    tar.setCwd(wf.getDirectory());
    const out_file = tar.addOutputFileArg(&quot;project.tar.gz&quot;);
    tar.addArgs(&amp;.{&quot;project/&quot;});

    const install_tar = b.addInstallFileWithDir(out_file, .prefix, &quot;project.tar.gz&quot;);
    b.getInstallStep().dependOn(&amp;install_tar.step);
}
```

```text
$ zig build--summary all
Build Summary: 5/5 steps succeeded
install success
+- install generated to project.tar.gz success
   +- run tar (project.tar.gz) success 616ms
      +- WriteFile project/app success
         +- compile exe app Debug native success 1s MaxRSS:143M
```

**Output**

    zig-out/
    └── project.tar.gz

## Mutating Source Files in Place {#mutating-source}

It is uncommon, but sometimes the case that a project commits generated
files into version control. This can be useful when the generated files
are seldomly updated and have burdensome system dependencies for the
update process, but *only* during the update process.
**UpdateSourceFiles** provides a way to accomplish this task.

Be careful with this functionality; it should not be used during the
normal build process, but as a utility run by a developer with intention
to update source files, which will then be committed to version control.
If it is done during the normal build process, it will cause caching and
concurrency bugs.

```zig

const std = @import(&quot;std&quot;);

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);

    if (args.len != 2) fatal(&quot;wrong number of arguments&quot;, .{});

    const output_file_path = args[1];

    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch |err| {
        fatal(&quot;unable to open &#39;{s}&#39;: {s}&quot;, .{ output_file_path, @errorName(err) });
    };
    defer output_file.close();

    try output_file.writeAll(
        \\pub const Header = extern struct {
        \\    magic: u64,
        \\    width: u32,
        \\    height: u32,
        \\};
    );
    return std.process.cleanExit();
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
```

```zig

const std = @import(&quot;std&quot;);
const Protocol = @import(&quot;protocol.zig&quot;);

pub fn main() !void {
    const header = try std.io.getStdIn().reader().readStruct(Protocol.Header);
    std.debug.print(&quot;header: {any}\n&quot;, .{header});
}
```

```zig

pub const Header = extern struct {
    magic: u64,
    width: u32,
    height: u32,
};
```

```zig

const std = @import(&quot;std&quot;);

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const exe = b.addExecutable(.{
        .name = &quot;demo&quot;,
        .root_source_file = b.path(&quot;src/main.zig&quot;),
        .target = target,
    });
    b.installArtifact(exe);

    const proto_gen = b.addExecutable(.{
        .name = &quot;proto_gen&quot;,
        .root_source_file = b.path(&quot;tools/proto_gen.zig&quot;),
        .target = target,
    });

    const run = b.addRunArtifact(proto_gen);
    const generated_protocol_file = run.addOutputFileArg(&quot;protocol.zig&quot;);

    const wf = b.addUpdateSourceFiles();
    wf.addCopyFileToSource(generated_protocol_file, &quot;src/protocol.zig&quot;);

    const update_protocol_step = b.step(&quot;update-protocol&quot;, &quot;update src/protocol.zig to latest&quot;);
    update_protocol_step.dependOn(&amp;wf.step);
}

fn detectWhetherToEnableLibFoo() bool {
    return false;
}
```

``` shell
$ zig build update-protocol --summary all
Build Summary: 4/4 steps succeeded
update-protocol success
└─ WriteFile success
   └─ run proto_gen (protocol.zig) success 401us MaxRSS:1M
      └─ zig build-exe proto_gen Debug native success 1s MaxRSS:183M
```

After running this command, `src/protocol.zig` is updated in place.

# Handy Examples {#examples}

## Build for multiple targets to make a release {#release}

In this example we're going to change some defaults when creating an
`InstallArtifact` step in order to put the build for each target into a
separate subdirectory inside the install path.

```zig

const std = @import(&quot;std&quot;);

const targets: []const std.Target.Query = &amp;.{
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    .{ .cpu_arch = .aarch64, .os_tag = .linux },
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .x86_64, .os_tag = .windows },
};

pub fn build(b: *std.Build) !void {
    for (targets) |t| {
        const exe = b.addExecutable(.{
            .name = &quot;hello&quot;,
            .root_module = b.createModule(.{
                .root_source_file = b.path(&quot;hello.zig&quot;),
                .target = b.resolveTargetQuery(t),
                .optimize = .ReleaseSafe,
            }),
        });

        const target_output = b.addInstallArtifact(exe, .{
            .dest_dir = .{
                .override = .{
                    .custom = try t.zigTriple(b.allocator),
                },
            },
        });

        b.getInstallStep().dependOn(&amp;target_output.step);
    }
}
```

```text
$ zig build--summary all
Build Summary: 11/11 steps succeeded
install success
+- install hello success
|  +- compile exe hello ReleaseSafe aarch64-macos success 19s MaxRSS:398M
+- install hello success
|  +- compile exe hello ReleaseSafe aarch64-linux success 23s MaxRSS:492M
+- install hello success
|  +- compile exe hello ReleaseSafe x86_64-linux-gnu success 22s MaxRSS:422M
+- install hello success
|  +- compile exe hello ReleaseSafe x86_64-linux-musl success 22s MaxRSS:421M
+- install hello success
   +- compile exe hello ReleaseSafe x86_64-windows success 18s MaxRSS:375M
```

```zig

const std = @import(&quot;std&quot;);

pub fn main() !void {
    std.debug.print(&quot;Hello World!\n&quot;, .{});
}
```

**Output**

    zig-out
    ├── aarch64-linux
    │   └── hello
    ├── aarch64-macos
    │   └── hello
    ├── x86_64-linux-gnu
    │   └── hello
    ├── x86_64-linux-musl
    │   └── hello
    └── x86_64-windows
        ├── hello.exe
        └── hello.pdb
