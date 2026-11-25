---
adr: "03"
title: "Choose Qt for the Tickoni desktop terminal UI"
status: "proposed"
date: "2026-08-05"
authors: deeprnd
deciders:
  - "Tickoni architecture maintainers"
tags:
  - "terminal-ui"
  - "desktop"
  - "cross-platform"
  - "qt"
  - "zig"
  - "licensing"
supersedes: []
superseded_by:
  - "ADR-04: Constrained MVVM in `tk_ui` over internal tile channels (local transport override)"
related:
  - "V2.19: Tickoni Native Investment Terminal"
---

# ADR-03: Choose Qt for the Tickoni desktop terminal UI

## Decision Summary

In the context of Tickoni's professional desktop terminal, facing the need
for a dense, keyboard-first, multi-window UI on Linux, macOS, and Windows while
preserving the Zig runtime's financial and licensing boundaries, it was decided to
build the official terminal with Qt 6 Quick/QML and a thin C++ application layer.
For local operation, the terminal communicates with the Zig runtime through
`tk_gate` over bounded shared-memory channels inside the `tk_ui` composite tile
(see ADR-04). For remote operation, it communicates through `tk_gateway` over
HTTP, WebSocket, or QUIC. We will not use Tauri, Flutter, a
browser/Electron-style shell, a Qt Widgets-only UI, or direct Qt bindings from
Zig as the default architecture.
This provides one native cross-platform terminal with strong model/view and
custom styling capabilities, accepting a C++/QML toolchain, Qt packaging work,
and GPLv3 obligations for the terminal when GPL-only Qt modules are used.
The terminal build will use CMake as its authoritative build system, with
CMake presets and explicit compiler/architecture lanes. The Zig runtime and CLI
remain under `build.zig`; Qt Creator kits are developer conveniences rather than
the source of truth for supported builds.

## Context and Problem Statement

Tickoni already has a Zig runtime and CLI that implement governed investment
flows, policy decisions, audit, replay, diagnostics, and cross-platform builds.
V2.19 introduces the first operator-facing product surface. The UI must present
large amounts of financial and policy state without moving financial correctness
into the frontend.

The intended product is a persistent professional terminal rather than a
consumer dashboard. It needs dense tables, aligned numerical data, keyboard
commands, multiple windows, high-DPI support, live `tkgate` updates, and a
consistent visual system across Linux, macOS, and Windows.

The requirements suggest the long-term workload as 10–50 dockable panels, 
thousands of live-updating cells, multiple monitors, heavy keyboard usage, 
low latency, native desktop behavior, and potentially 8–12 hours of continuous use.
These are architecture-level design targets, not a requirement that V2.19 implement
every panel or trading function in its first release.

Qt's industry marketing does not identify finance as a primary vertical, but
Tickoni does not require a finance-specific UI framework. Finance-specific
policy, execution, audit, replay, and provider behavior remains in Tickoni. The
UI framework must provide general desktop application, model/view, windowing,
networking, styling, and rendering capabilities.

Tauri 2 and Flutter Desktop were also evaluated as non-Qt alternatives. Tauri
uses a Rust core with HTML/CSS/JavaScript rendered by the operating system
WebView. Flutter uses Dart and a bundled rendering engine to compile native
Windows, macOS, and Linux applications. Both are credible cross-platform UI
frameworks, but their fit must be judged against Tickoni's dense terminal
workflow, required native architecture matrix, and non-MSVC Windows policy.

The supplied reviews expose two legitimate but different optimization targets.
The CLI/GUI review recommends a web-first React/Tauri route as the fastest way
to reuse mature grids, financial charts, and terminal components, while keeping
all authority behind `tkgate`. The trading-framework review recommends Qt for the
long-lived premium desktop workstation because its model/view, windowing,
keyboard, and workspace foundations better match a professional
market-data/trading-desk terminal. This ADR chooses the second target for the official desktop terminal
without rejecting a future web product, Tauri companion client, mobile client,
or the existing CLI/TUI.

The same source material also concludes that Tickoni should expose multiple
shells around one agent core, API, command model, approval model, audit trail,
and replay model. The CLI/TUI remains a first-class client for power users,
local operation, audit, and replay; it is not replaced by the Qt terminal and
must not contain financial business logic.

**Decision question:** Which UI framework and runtime boundary should Tickoni use
for its official Linux, macOS, and Windows professional desktop terminal?

This decision matters now because V2.19 otherwise leaves framework, language,
process, packaging, data-model, and licensing choices to individual stories.
Those choices affect repository structure, CI, contributors, API contracts, and
every later terminal function.

## Scope

### In scope

- The framework for the official Tickoni desktop terminal.
- Responsibility boundaries between QML, C++, and Zig.
- The process/API boundary between the terminal and the runtime.
- Cross-platform build, compiler, architecture, and packaging expectations.
- Licensing boundaries between the terminal and the Apache-2.0 runtime, CLI,
  API schemas, and SDKs.
- The default approach for large tables, live state, and terminal styling.

### Out of scope

- Exact V2.19 screen layouts, workflows, commands, and color tokens.
- Market-data, brokerage, exchange, LLM, billing, or identity providers.
- Financial policy, execution, audit, replay, adapter, or storage semantics.
- Mobile, browser, or WebAssembly clients.
- Commercial terms for hosted Tickoni services.
- A final legal opinion on Qt or GPL compliance.

## Decision Drivers

- Deliver a native professional terminal rather than a conventional dashboard.
- Support Linux, macOS, and Windows from one primary UI codebase.
- Support dense, virtualized tables and incremental updates.
- Support a long-term envelope of many dockable panels, thousands of updating
  cells, multiple monitors, and 8–12 hour operator sessions.
- Support keyboard-first operation, multiple windows, saved workspaces, and
  high-DPI displays.
- Allow a strongly customized but consistent Tickoni visual system.
- Keep financial correctness and execution authority in the Zig runtime.
- Keep the runtime and CLI buildable and usable without Qt.
- Preserve a provider-neutral `tkgate` for official and third-party clients.
- Avoid maintaining direct Zig bindings to Qt's C++ meta-object system.
- Make licensing boundaries explicit and mechanically testable.
- Preserve Tickoni's existing GNU/Clang-oriented toolchain policy and avoid an
  accidental dependency on MSVC, including for native Windows ARM64 releases.
- Make every supported compiler/architecture pair reproducible in CI without
  depending on local Qt Creator state.
- Preserve one deterministic command grammar and API contract across CLI/TUI,
  desktop, web, and future mobile shells.
- Isolate charting as a replaceable module because no evaluated framework
  provides a complete professional trading-chart system out of the box.

Quality attributes affected:

- Correctness: the UI displays runtime-owned semantics and does not recompute
  policy or financial outcomes.
- Maintainability: one UI codebase replaces multiple platform clients, but adds
  C++, QML, CMake, and Qt packaging responsibilities.
- Portability: one framework targets Linux, macOS, and Windows, with platform
  packaging tested separately.
- Performance: C++ models and reusable Qt Quick delegates support dense tables
  when QML remains presentation-only.
- Operability/testability: fixture and `tkgate` transports share typed models;
  terminal and runtime can fail and restart independently.
- Security/compliance: the UI cannot call providers, adapters, brokers, stores,
  or execution systems directly.

## Constraints and Assumptions

- The runtime, CLI, public API schemas, and non-UI SDKs remain Apache-2.0 unless
  changed by another decision.
- The official Qt terminal is a separate executable and is not required to build
  or run the runtime or CLI.
- `tk_gate` is the semantic boundary for governed reads and actions. A separate
  `tk_ui` tile wraps the Qt application for local operation.
- Local transport uses bounded shared-memory channels (see ADR-04).
- Remote transport uses HTTP, WebSocket, or QUIC through `tk_gateway`.
- QML owns presentation, layout, focus, and bindings only.
- C++ owns Qt application lifecycle, typed UI models, command dispatch,
  transport, connection state, and QML type registration.
- Zig owns all financial semantics and runtime truth.
- QML must not perform direct network, filesystem, shell, provider, adapter,
  broker, or execution calls.
- The terminal must operate against deterministic fixtures without live external
  dependencies.
- Qt module licenses must be checked for the exact pinned Qt release.
- Qt Graphs is GPLv3-only for open-source users in the Qt licensing information
  reviewed for this ADR. If it is included, the official terminal is distributed
  under GPL-3.0-only unless Tickoni obtains a suitable commercial Qt license.
- Production packages should dynamically link Qt where practical. Static linking
  requires a separate packaging and licensing review.
- A small Apache-2.0 API schema or generated client library may be linked into
  the GPL terminal. The Zig runtime remains a separate process by default.
- Hosted market-data, brokerage, and LLM services are separate network services
  and outside this ADR.
- The CLI/TUI and Qt terminal are separate clients of the same `tkgate`; neither
  is allowed to become the execution engine or the source of financial truth.
- Commands, sessions, streaming, approval gates, audit, replay, policy errors,
  and case state must be represented through shared API contracts and command
  metadata rather than reimplemented independently in each shell.
- Charting is a replaceable presentation subsystem. The choice of terminal
  framework must not permanently couple Tickoni to Qt Graphs, TradingView, or a
  particular commercial chart vendor.

- The term `x86` in this ADR means `x86_64`; 32-bit x86 desktop builds are not
  part of the supported Qt 6 target matrix.
- Tickoni requires non-MSVC native Windows builds. On Windows, the terminal
  uses a mingw-w64 environment. The x86_64 and ARM64 release lanes use the
  MSYS2 LLVM/MinGW environments (`CLANG64` and `CLANGARM64`) so both targets
  share Clang, LLD, UCRT, and libc++. GCC is not a valid Windows ARM64 compiler
  backend.
- A Qt Creator custom compiler or kit does not by itself make a compiler/target
  combination supported. The Qt libraries, application objects, C++ runtime,
  plugins, and deployment tools must use a compatible ABI and architecture.

## Compilation and Toolchain Strategy

The UI build and the Zig build remain separate, reproducible build graphs:

```text
CMake + Qt toolchain                     build.zig
        |                                   |
        v                                   v
tickoni-terminal-qt                   tickoni-runtime
                                      tickoni-cli
        |                                   |
        +----------- package/test ----------+
```

CMake is the authoritative build system for `tickoni-terminal-qt`. `qmake` is
not used for new Tickoni terminal code. Qt Creator may consume the CMake project,
but committed `CMakePresets.json`, toolchain files, pinned Qt versions, and CI
jobs define the supported builds. Developer-specific Qt Creator kits and
`CMakeLists.txt.user` files are not release configuration.

The initial compiler and architecture matrix is:

| Platform | Architecture | Terminal compiler/toolchain | Support level | Decision |
| --- | --- | --- | --- | --- |
| macOS | `x86_64` | Apple Clang from the pinned Xcode toolchain | Required release lane | Build and test a native x86_64 slice. |
| macOS | `arm64` | Apple Clang from the pinned Xcode toolchain | Required release lane | Build and test a native arm64 slice. |
| Linux | `x86_64` | GCC baseline; Clang compatibility lane | Required | Release artifacts follow a pinned Qt-compatible ABI; both Tickoni compiler lanes are tested. |
| Linux | `arm64` | GCC baseline; Clang compatibility lane | Required | Use a matching arm64 Qt build and native or controlled cross-build environment. |
| Windows | `x86_64` | MSYS2 `CLANG64`: LLVM/Clang, LLD, mingw-w64, UCRT, libc++ | Required native release lane | Use the same non-MSVC toolchain family as Windows ARM64. An additional UCRT64/GCC compatibility lane may remain, but it is not the terminal release baseline. |
| Windows on ARM | `ARM64` | MSYS2 `CLANGARM64`: LLVM/Clang, LLD, mingw-w64, UCRT, libc++ | Required native release lane; Tickoni-owned support | Build and test native ARM64 binaries. This configuration is packaged by MSYS2 but is not listed in Qt Company's officially supported Windows compiler matrix. |

Native Windows ARM64 without MSVC is feasible through MSYS2's `CLANGARM64`
environment. MSYS2 publishes native ARM64 packages for Qt Base, Qt
Declarative/Quick, Qt WebSockets, Qt Graphs, Qt tools, CMake, Ninja, and Qt
Creator. The compiler is LLVM/Clang rather than GCC because GCC does not target
Windows on ARM; the ABI and Windows runtime environment remain mingw-w64/UCRT.

Qt Company's Qt 6.11 support matrix lists Windows ARM64 only with MSVC 2022.
Therefore, Tickoni classifies the `CLANGARM64` lane as a required product target
with project-owned support, rather than an upstream-supported Qt configuration.
Tickoni must pin and mirror the complete MSYS2/Qt dependency set, run native CI,
validate every required Qt plugin and module, and maintain a documented rollback
path. This is an accepted support responsibility, not a blocked target.

Build-system rules:

1. Use modern Qt CMake APIs: `qt_standard_project_setup()`,
   `qt_add_executable()`, and `qt_add_qml_module()`.
2. Keep `AUTOMOC` enabled so Qt's meta-object code is generated by the build.
3. Embed UI assets through Qt resources; do not add hand-written resource-copy
   logic where `qt_add_qml_module()` or `rcc` already provides it.
4. Keep QML cache compilation enabled for release builds. QML/JavaScript listed
   through `qt_add_qml_module()` is compiled and embedded by Qt's build tooling;
   do not invoke `qmlcachegen` manually.
5. Run `qmllint` in CI and treat new actionable diagnostics as build failures.
6. Prefer Ninja as the CMake generator in CI and local documented builds, while
   keeping generator-specific assumptions out of project logic.
7. Define named CMake presets for each supported operating-system,
   architecture, compiler, build type, and sanitizer combination.
8. Pin the Qt minor release and compiler family for release artifacts. Do not
   mix Qt binaries built for MSVC with MinGW application objects or combine
   incompatible C++ runtime/ABI families.
9. A non-standard compiler requires a matching Qt build, deployment test, and
   explicit support classification; registering it as a Qt Creator custom kit
   is insufficient evidence.
10. `build.zig` remains authoritative for the runtime and CLI. CMake may invoke
    packaging/orchestration commands but must not absorb or reimplement the Zig
    runtime build graph.
11. A top-level developer command may orchestrate both graphs, for example
    `just build-terminal`, `just test-terminal`, and `just package-terminal`,
    but failures must remain attributable to the Qt or Zig build independently.
12. Packaging must verify that every shipped Qt library and plugin matches the
    terminal's architecture, compiler ABI, build mode, and pinned Qt version.
13. Windows release builds use native MSYS2 environments: `CLANG64` on
    Windows x86_64 and `CLANGARM64` on Windows ARM64. Do not mix UCRT64/GCC,
    CLANG64/libc++, MSVC, or cross-architecture objects within one package.
14. The Windows ARM64 release is built and tested natively on a Windows 11 ARM64
    runner or device. Linux-hosted LLVM-MinGW cross-compilation may be used as a
    secondary reproducibility lane, but it is not the sole release gate because
    Qt cross-builds require matching host tools such as `moc`, `rcc`,
    `qmlcachegen`, and `qsb`.
15. CI installs a pinned MSYS2 snapshot or Tickoni-controlled mirror containing
    the exact `clangarm64` Qt and toolchain packages. Floating `pacman -Syu`
    results are not sufficient for reproducible releases.
16. Windows packaging uses the architecture-matching `windeployqt6` and then
    validates the PE architecture and dependency graph of the executable, Qt
    DLLs, QML plugins, TLS backend, image plugins, and platform plugin.
17. The native ARM64 gate includes application launch, QML import, table render,
    HTTP/TLS, WebSocket, reconnect, Qt Graphs when enabled, keyboard input,
    high-DPI, multi-window, package install/uninstall, and update smoke tests.
18. At least one native physical Windows-on-ARM device is included in release
    qualification in addition to virtual or hosted CI.

macOS may publish separate `x86_64` and `arm64` packages initially. A universal
binary may be added only after both slices are independently built, tested, and
combined with matching universal Qt libraries and plugins.

Linux GCC is the release baseline because it follows Qt's documented desktop
configurations. Clang remains a Tickoni compatibility lane and must use a Qt
build and standard-library combination shown to be ABI-compatible by compile,
link, package, and runtime tests; successful compilation alone is not enough.

## Charting Strategy

The supplied framework comparison reaches one conclusion that applies to every
option: none of Qt, Tauri, or Flutter provides a complete TradingView-class
financial chart out of the box.

Qt Graphs provides general line, area, bar, scatter, axis, annotation, and theme
primitives, but it is not a professional trading-chart system. A serious chart
would still need Tickoni-specific or third-party support for candlesticks/OHLC,
volume, crosshairs, time-axis compression, zoom and pan semantics, indicators,
drawing tools, synchronized panes, market-session breaks, corporate-action
adjustments, and order or position markers.

Tauri has the lowest initial chart-development burden because its web frontend
can use the existing JavaScript ecosystem, including TradingView Lightweight
Charts, Advanced Charts, Highcharts Stock, LightningChart, SciChart, Apache
ECharts, and Canvas/WebGL implementations. This is a genuine Tauri advantage,
not a reason to pretend that browser rendering has the same long-term desktop
trade-offs as Qt.

Flutter provides custom painting and commercial or open-source chart packages,
but advanced TradingView integration normally introduces a WebView and a
Dart-to-JavaScript bridge. That adds focus, resizing, clipping, multi-instance,
and platform-WebView concerns inside the Flutter application.

Tickoni therefore treats charting as an independent module with a documented
input and interaction API:

```text
tkgate snapshots/deltas
        |
        v
C++ chart model / normalized series API
        |
        +--> basic Qt-native renderer
        +--> optional embedded web renderer
        +--> future custom GPU renderer
```

Standing rules:

1. V2.19 is table-first. Advanced technical-analysis charting is not required to
   prove the first governed investment workflow.
2. A basic Qt-native chart may use approved Qt primitives or Qt Graphs, subject
   to the terminal's GPL licensing decision.
3. An embedded web chart is allowed only behind the chart-module interface and
   requires a separate dependency, licensing, security, packaging, memory, and
   keyboard/focus review. Qt WebEngine is not a default dependency because it
   embeds a Chromium-class runtime and materially increases package size and
   complexity.
4. If charts become a primary product surface, a later ADR may choose a
   specialist commercial component, an embedded web implementation, or a custom
   `QQuickItem`/scene-graph renderer without replacing the Qt terminal shell.
5. Chart implementations consume governed snapshots and batched deltas; they do
   not connect directly to market-data vendors, brokers, adapters, or the Zig
   runtime internals.

This preserves the strongest long-term decomposition identified in the supplied
review: Qt owns the desktop shell, workspaces, windows, keyboard handling, and
data grids; Zig owns networking, market data, business logic, and analytics;
charting remains the highest-risk replaceable component.

## Considered Options

1. **Qt Quick/QML with C++ models over `tkgate`.** Build one native terminal with
   QML presentation, C++ Qt integration, and a separate Zig runtime process.
2. **Qt Widgets-only over `tkgate`.** Build the terminal with traditional Qt
   Widgets and C++ models.
3. **Tauri 2 with a web frontend and Rust shell over `tkgate`.** Build the
   terminal with HTML/CSS/TypeScript in operating-system WebViews and a small
   Rust desktop shell.
4. **Flutter Desktop over `tkgate`.** Build the terminal in Dart using Flutter's
   cross-platform rendering engine and native desktop embedders.
5. **Web-first UI with an optional desktop wrapper.** Build React/Next.js and use
   a browser or Electron-like shell for desktop delivery.
6. **Direct Zig integration with Qt.** Create custom Qt bindings for Zig or link
   substantial Zig runtime logic into the Qt process through a C ABI.

## Option Analysis

### Option 1: Qt Quick/QML with C++ models over `tkgate`

Build `tickoni-terminal-qt` as a Qt 6 application. Use QML and Qt Quick Controls
for visual composition, C++ `QObject` and `QAbstractItemModel` implementations
for application state and tables, and HTTP/WebSocket for the independently built
Zig runtime.

Good, because:

- The target workload favors a mature desktop framework: many panels, thousands
  of updating cells, multiple monitors, heavy keyboard operation, low latency,
  native behavior, and long-running sessions.
- One native desktop codebase supports Linux, macOS, and Windows.
- CMake and Qt's generated build steps handle MOC, resources, QML modules, and
  cached QML compilation consistently across supported lanes.
- QML provides strong control over a dense, branded terminal visual system.
- C++ models integrate with Qt's model/view and change-notification system.
- Qt provides windowing, keyboard, accessibility, networking, TLS, WebSocket,
  high-DPI, and deployment facilities.
- Qt's model/view architecture, reusable views, shortcuts, menus, splitters, and
  multi-window foundations reduce the amount of workstation infrastructure that
  Tickoni must invent compared with a general mobile or web application stack.
- The process boundary preserves `tkgate` authority and runtime ownership.
- The runtime and CLI remain usable without Qt.
- Third parties can build other clients against the same API.

Bad, because:

- The project must maintain C++, QML, CMake, Qt deployment, and Zig expertise.
- Qt's open-source trading-widget ecosystem is materially smaller than the web
  ecosystem; a mature terminal is likely to own or license its chart renderer.
- QML does not remove the need to design and validate docking, workspace
  persistence, panel detachment, and multi-monitor coordination.
- Packaging differs across Linux, macOS, and Windows.
- Qt Company does not officially support the Windows ARM64 + LLVM/MinGW
  configuration, so Tickoni owns toolchain, packaging, regression, and upgrade
  support for that required target.
- Poor QML ownership or complex delegates can cause performance problems.
- GPL-only Qt modules affect the terminal's distribution license.

Neutral or conditional:

- Qt does not supply finance-domain functionality; Tickoni already owns it.
- The custom style should be based on a cross-platform Qt Quick Controls style,
  initially Basic, rather than modifying native Windows and macOS styles.
- QML is the primary presentation technology, but a selective Qt Widgets or
  native-window host is permitted under this ADR when a prototype proves it is
  the lower-risk way to implement docking, menus, accessibility, or platform
  integration. This does not authorize a Widgets-only product rewrite.

Validation needed:

- Build and package a minimal terminal for macOS x86_64/arm64, Linux
  x86_64/arm64, Windows x86_64 `CLANG64`, and native Windows ARM64
  `CLANGARM64`.
- Run native Windows ARM64 tests on GitHub Actions `windows-11-arm` and on at
  least one physical Windows-on-ARM device. Also test the x86_64 package under
  emulation as a fallback compatibility lane.
- Update a synthetic 10,000-row table using C++ models and reusable delegates.
- Verify keyboard focus, multiple windows, high-DPI, and reconnect behavior.
- Run a workspace spike with 10–50 logical panels, detach/reattach, saved layout,
  multiple monitors, and an 8-hour update soak. The panels may use synthetic
  content; the objective is to validate the shell architecture, not V2.19 scope.
- Verify runtime and CLI builds with Qt absent.
- Complete licensing review for the pinned Qt modules.

### Option 2: Qt Widgets-only over `tkgate`

Build the terminal with `QMainWindow`, dock widgets, item views, and C++ models.

Good, because:

- Qt Widgets is mature for desktop forms, menus, docks, and tables.
- UI behavior and models use one primary language.
- Traditional desktop focus behavior is well established.

Bad, because:

- A distinctive, highly customized terminal requires more imperative code and
  custom painting.
- Responsive composition and compact bespoke controls are less natural than in
  QML.
- It better fits a conventional administration tool than the intended product
  identity.

Neutral or conditional:

- Widgets remain acceptable for a specialized utility or dialog if separately
  justified.

Validation needed:

- No full spike is required unless the QML prototype fails a stated accessibility
  or performance gate.

### Option 3: Tauri 2 with a web frontend and Rust shell over `tkgate`

Build a Tauri 2 desktop application with a TypeScript frontend and a minimal
Rust core. The frontend runs in the operating system WebView: WebView2 on
Windows, WKWebView on macOS, and WebKitGTK on Linux. The Tauri core would manage
windows, local settings, updates, and a typed `tkgate` client; financial behavior
would remain in the separate Zig runtime.

Good, because:

- Tauri itself is MIT/Apache-2.0, so the official UI could remain permissively
  licensed without the Qt Graphs GPL decision.
- It uses system WebViews rather than bundling Chromium, producing a smaller
  application than Electron-style packaging.
- Rust provides a memory-safe native shell and a capability/IPC boundary between
  the WebView and operating-system functionality.
- Any frontend framework that produces HTML, CSS, and JavaScript can be used.
- The web ecosystem provides a fast route to mature grids, charting, and terminal
  components such as AG Grid, TradingView-style libraries, and xterm.js.
- The process/API boundary with the Zig runtime remains straightforward.
- Rust supports the `aarch64-pc-windows-gnullvm` target through LLVM-MinGW or
  MSYS2 CLANG environments, so a non-MSVC ARM64 executable is technically
  possible at the Rust toolchain level.

Bad, because:

- The UI is still a WebView application. Windows, macOS, and Linux use different
  WebView engines and independently updated runtimes, so rendering, fonts,
  keyboard behavior, accessibility, and CSS edge cases require platform-specific
  qualification.
- A professional trading-desk terminal with large mutable tables, deterministic keyboard
  routing, detachable windows, and long-running high-frequency updates would
  rely on web-application techniques rather than Qt's mature desktop model/view
  and windowing APIs.
- Market and state updates cross a Rust/WebView IPC and browser-rendering
  boundary. Batching can work well, but thousands of rapidly changing cells and
  many synchronized panels require careful backpressure, serialization, and
  rendering design.
- Tauri adds Rust plus TypeScript/JavaScript, a web bundler, browser security
  controls, and frontend dependency management alongside the existing Zig
  runtime.
- Tauri's documented Windows ARM64 installer path uses
  `aarch64-pc-windows-msvc` and Visual Studio ARM64 build tools. Using Rust's
  `aarch64-pc-windows-gnullvm` target would require Tickoni to validate Tauri,
  WebView2 bindings, native plugins, signing, and installer generation outside
  Tauri's documented ARM64 release path.
- Linux deployment depends on WebKitGTK and its distribution-specific packaging,
  which increases the surface for rendering and dependency differences.

Neutral or conditional:

- Tauri is the strongest evaluated option when fastest access to the web chart
  and data-grid ecosystem is more important than owning a predictable native
  workstation shell.
- Tauri is a stronger fit for a compact companion app, configuration utility,
  hosted web-derived client, or rapid chart-heavy MVP than for the primary
  long-lived Tickoni terminal.
- It is materially lighter than Electron but does not remove the web runtime and
  frontend security model.

Validation needed:

- Prove native Windows ARM64 packaging with
  `aarch64-pc-windows-gnullvm`/LLVM-MinGW and no Visual Studio or MSVC tools.
- Test identical visual layout and keyboard behavior across WebView2, WKWebView,
  and WebKitGTK.
- Benchmark a 10,000-row live table, multi-window synchronization, command focus,
  reconnect handling, and long-running memory stability.
- Verify installer, updater, code-signing, WebView availability, and Linux
  distribution compatibility on every supported architecture.

### Option 4: Flutter Desktop over `tkgate`

Build a Dart application using Flutter's declarative widget system and bundled
rendering engine. The Flutter desktop embedders host the engine in native
Windows, macOS, and Linux applications, while all financial state is loaded from
`tkgate`.

Good, because:

- Flutter is BSD-3-Clause licensed, allowing the Tickoni UI to remain under an
  Apache-compatible permissive licensing model.
- Flutter renders through its own engine rather than three different system
  WebViews, providing strong control over a custom, consistent visual identity.
- Flutter compiles release applications to native machine code and officially
  lists Windows x64/ARM64, macOS x64/ARM64, and Linux x64/ARM64 as supported
  desktop deployment targets in Flutter 3.44.7.
- Declarative widgets, custom painting, animation control, and cross-platform
  layout are strong matches for a polished and visually consistent terminal
  surface.
- Flutter can deliver rapid UI iteration when the product behaves more like a
  custom application than a traditional workstation.
- The separate `tkgate` boundary remains straightforward and no C++ financial
  logic is required.

Bad, because:

- It introduces Dart, the Flutter SDK, Flutter engine packaging, pub dependency
  management, and platform plugin maintenance into a Zig-based project.
- Flutter desktop uses a custom-rendered widget environment rather than mature
  native desktop model/view components. Dense data grids, advanced docking,
  multiple independent windows, keyboard routing, and desktop accessibility
  require more application/framework work and careful plugin selection.
- The workload stresses areas Flutter is not primarily optimized for: very large
  virtualized tables, complex desktop docking, extensive keyboard-driven
  workflows, and extremely dense information layouts.
- Advanced financial charts require a third-party package, commercial vendor,
  custom painter, or embedded WebView. The WebView route introduces Dart/JS
  communication and focus, resizing, clipping, and platform-specific behavior.
- The official Windows desktop host is a C++ Win32 application, and Flutter's
  documented Windows build and redistribution path is tied to Visual Studio and
  the Visual C++ runtime. That conflicts directly with Tickoni's no-MSVC release
  policy even though Windows ARM64 is now an officially supported deployment
  architecture.
- Desktop plugin quality and architecture coverage vary; every plugin required
  by the terminal would need x64/ARM64 validation across all three operating
  systems.
- macOS Intel support is being phased out by Flutter, while Tickoni currently
  requires macOS x86_64 as a supported release lane.

Neutral or conditional:

- Flutter is especially strong when mobile and desktop share one product codebase;
  mobile is outside this ADR and not a current Tickoni driver.
- The visual consistency advantage is meaningful, but it does not by itself
  provide a professional terminal interaction model.
- The supplied comparison places Flutter between Qt and Tauri for this use case:
  stronger than a system-WebView shell for consistent custom rendering, but
  without a decisive advantage in either mature workstation primitives or the
  web financial-component ecosystem.

Validation needed:

- Demonstrate a supported Windows x86_64 and ARM64 build that satisfies the
  no-MSVC policy; absent that evidence, Flutter cannot meet the current required
  toolchain matrix.
- Confirm the macOS x86_64 support horizon is compatible with Tickoni's release
  commitments.
- Benchmark large live tables, multi-window workflows, keyboard focus, screen
  reader behavior, high-DPI scaling, and long-running memory stability.
- Audit every desktop plugin for license, architecture support, maintenance, and
  native toolchain requirements.

### Option 5: Web-first UI with an optional desktop wrapper

Build the UI with React/Next.js and use a browser or desktop wrapper.

Good, because:

- The ecosystem has broad developer familiarity and mature testing tools.
- Hosted deployment and HTTP/WebSocket integration are straightforward.
- It offers the fastest access to AG Grid, TradingView-style charting, xterm.js,
  and shared browser/desktop code, which makes it a credible hosted-product or
  rapid-MVP strategy.

Bad, because:

- It is less aligned with the persistent, keyboard-first, multi-window terminal
  goal.
- A desktop wrapper adds a browser runtime, packaging size, memory overhead, and
  another update surface.
- OS-level focus, menu, window, and high-DPI behavior require wrapper-specific
  work.
- It encourages dashboard interaction patterns rather than a terminal function
  model.

Neutral or conditional:

- A later web review or partner portal can use the same `tkgate`.

Validation needed:

- Reconsider only if browser-first distribution becomes a primary requirement.

### Option 6: Direct Zig integration with Qt

Expose Qt through custom C/C++ wrappers to Zig, or link substantial Zig runtime
logic into the Qt process through a C ABI.

Good, because:

- More code could remain in Zig.
- In-process calls avoid local API serialization overhead.

Bad, because:

- Qt depends on C++ classes, `QObject`, signals and slots, MOC, QML type
  registration, and CMake; custom Zig bindings create a large maintenance layer.
- Embedding the runtime weakens process isolation and the existing `tkgate`
  authority boundary.
- Shared address space introduces allocator, ownership, lifecycle, crash, and ABI
  concerns.
- It complicates the Apache/GPL boundary and packaging explanation.
- No measured UI latency currently justifies the complexity.

Neutral or conditional:

- A small, stable C-ABI library may be considered later for a narrowly measured
  need through another ADR.

Validation needed:

- Profile first. Do not implement unless the process boundary prevents a stated
  product SLO after transport and batching optimization.

## Comparison

| Criterion | Weight | Qt Quick + `tkgate` | Qt Widgets + `tkgate` | Tauri 2 | Flutter Desktop | Web/Electron wrapper | Direct Zig/Qt |
| --- | ---: | --- | --- | --- | --- | --- | --- |
| Professional terminal fit | High | Strong | Medium/Strong | Medium | Medium | Medium | Depends on wrapper |
| Docking, workspaces, and multi-monitor | High | Strong Qt foundation; QML shell still needs a validated panel manager | Strong traditional Qt support | Medium; custom web/wrapper coordination | Medium; plugin/custom work | Medium; wrapper-specific | Depends on wrapper |
| Large live-table model support | High | Strong through C++ models and reusable views | Strong | Strong with AG Grid/web virtualization, but update pipeline needs batching | Medium; requires grid/custom work | Strong with mature web grids | Depends on wrapper |
| Keyboard-first operation | High | Strong | Strong | Medium; WebView and wrapper focus coordination | Medium; desktop-specific implementation | Medium | Depends on wrapper |
| Long-running 8–12 hour sessions | High | Strong candidate; requires soak validation | Strong candidate | Medium; browser/WebView memory and update behavior need careful validation | Medium; engine/plugin soak validation required | Medium | Depends on wrapper |
| Advanced financial-chart ecosystem | Medium | Limited native ecosystem; custom or commercial renderer likely | Limited native ecosystem | Strongest and fastest through web libraries | Medium through packages/commercial SDKs/WebView | Strongest through web libraries | Depends on chosen renderer |
| Ability to own a custom native chart engine | Medium | Strong through Qt Quick scene graph/`QQuickItem` | Strong through custom painting/OpenGL | Medium through Canvas/WebGL | Strong through custom painting | Medium/Strong through Canvas/WebGL | Strong but high effort |
| Cross-platform visual consistency | High | Strong | Strong | Medium because OS WebViews differ | Strong through Flutter engine | Strong with bundled browser | Medium |
| Native Windows ARM64 without MSVC | High | Feasible through MSYS2 CLANGARM64; Tickoni-owned support | Same | Rust gnullvm is feasible, but Tauri packaging is not its documented ARM64 path | Weak under current policy; official Windows build path uses Visual Studio/MSVC runtime | Depends on wrapper/toolchain | Weak/High effort |
| macOS x86_64 and ARM64 continuity | High | Strong under pinned Qt | Strong | Strong while WebKit/host OS supports target | Medium; Flutter is phasing out macOS Intel | Depends on wrapper | Medium |
| Separation from runtime truth | High | Strong | Strong | Strong | Strong | Strong | Weak |
| Runtime and CLI remain UI-framework-free | High | Strong | Strong | Strong | Strong | Strong | Weak/Medium |
| Fastest chart-heavy MVP | Medium | Medium/slow | Medium/slow | Strongest | Medium | Strongest | Weak |
| Long-term workstation maintainability | High | Strong; mature desktop APIs and predictable behavior | Strong | Medium; younger stack and three WebViews | Medium; younger desktop stack | Medium | Weak/Medium |
| Initial effort | High | Medium | Medium | Low/Medium for a web-skilled team | Medium | Low/Medium | High |
| Ongoing maintenance | High | Medium | Medium | Medium/High across Rust, web stack, and three WebViews | Medium/High across Dart, engine, plugins, and native hosts | Medium/High | High |
| Licensing clarity | High | Strong with explicit GPL terminal split when needed | Strong with split | Strong; MIT/Apache-2.0 framework | Strong; BSD-3-Clause framework | Strong subject to wrapper dependencies | Weak/Medium |

## Decision

**We will build the official Tickoni desktop terminal with Qt 6 Quick/QML and a
thin C++ application/model layer, as a separate executable communicating with
the Zig runtime exclusively through `tkgate` over HTTP/WebSocket.**

This is the default for the Linux, macOS, and Windows operator terminal. V2.19
and later desktop terminal work must use it unless a deviation criterion applies.

The decisive factor is that Qt Quick with C++ models provides the required
native desktop, model/view, keyboard, multi-window, workspace, and visual-control
foundation for a long-lived workstation from one codebase, while the `tkgate`
process boundary preserves Zig ownership of financial truth and keeps the
runtime and CLI independent of Qt. Tauri wins the narrower comparison for rapid
access to web charts and grids; Qt wins the broader comparison for the official
premium desktop terminal that must remain predictable under dense, multi-window,
long-running operation.

Implementation rules:

1. The official executable is `tickoni-terminal-qt` or an equivalently explicit
   UI-scoped name.
2. Qt UI source is isolated under `src/tickoni/ui/` or an equivalent standalone
   application directory with its own CMake target and license declaration.
3. The Zig runtime and CLI must not depend on or link Qt UI code.
4. QML contains presentation behavior only.
5. C++ exposes typed services and `QAbstractItemModel`-based models to QML.
6. All governed reads and actions pass through a typed `tkgate` client.
7. A local runtime may be started as a child process, but is accessed through the
   same API as a remote runtime.
8. Qt Quick Controls uses a Tickoni style based initially on Basic.
9. The command grammar and command metadata are shared with the CLI/TUI through
   versioned contracts; the desktop does not invent incompatible command names
   or authorization semantics.
10. Charting is accessed through a replaceable chart-module interface. Advanced
    chart vendor or WebEngine dependencies require separate approval.
11. Selective Qt Widgets or native desktop hosting may be used for docking,
    workspace, menu, accessibility, or platform-integration infrastructure when
    validated by a prototype; QML remains the primary product presentation
    layer.
12. Production packages dynamically link Qt where practical; static linking needs
   explicit release approval.
13. If GPL-only Qt modules such as Qt Graphs are used under the open-source Qt
    license, the terminal is distributed under GPL-3.0-only.
14. Runtime, CLI, API schemas, and provider SDKs remain Apache-2.0 and usable by
    alternative clients.
15. The terminal uses CMake, not qmake, with committed CMake presets and pinned
    Qt/compiler combinations.
16. Qt Creator kits are optional developer configuration and do not define the
    supported build matrix.
17. Required release lanes are macOS x86_64/arm64 with Apple Clang, Linux
    x86_64/arm64 with a GCC baseline plus Clang compatibility tests, Windows
    x86_64 with MSYS2 `CLANG64`, and native Windows ARM64 with MSYS2
    `CLANGARM64`.
18. Windows ARM64 is a first-class native target. It is supported by Tickoni
    through a pinned MSYS2/LLVM-MinGW/Qt stack even though Qt Company does not
    list that compiler combination as officially supported.

Rejected alternatives:

- Qt Widgets-only: rejected as the default because it is less suitable for the
  intended customized and compositional terminal product.
- Tauri 2: rejected as the primary terminal despite being the fastest route to
  AG Grid, TradingView-style charts, xterm.js, and web-skilled delivery. It
  inherits three different operating-system WebViews, routes updates through a
  Rust/WebView boundary, and its documented native Windows ARM64 build path uses
  MSVC. Rust's LLVM-MinGW ARM64 target makes a non-MSVC port plausible, but the
  complete Tauri/WebView/installer lane is not established enough to replace the
  Qt choice without a successful dedicated spike.
- Flutter Desktop: rejected because its official Windows desktop build and
  redistribution workflow depends on Visual Studio/MSVC components, conflicting
  with Tickoni's toolchain policy; it also adds Dart/Flutter engine ownership,
  requires more custom work for very dense tables, docking, and keyboard
  workflows, and has an unfavorable macOS x86_64 support trajectory for
  Tickoni's current matrix.
- Web-first UI: rejected as the primary terminal because native desktop workflow
  is a strategic requirement, not only a packaging option.
- Direct Zig/Qt integration: rejected because wrapper, ABI, lifecycle, isolation,
  and licensing costs exceed any demonstrated latency benefit.

## Consequences

### Positive consequences

- One official native terminal codebase serves all supported desktop platforms.
- Dense tables and live state use typed C++ models and incremental updates.
- Financial calculations and policy remain in one governed Zig source of truth.
- Runtime and CLI remain usable without the terminal or Qt.
- Third parties can build another UI or CLI against Apache-2.0 API contracts.
- CLI/TUI, desktop, web, and mobile clients can evolve around one command and
  API model rather than duplicating business logic.
- Terminal and runtime failures can be isolated and diagnosed independently.
- Licensing scope is visible through executable and directory boundaries.

### Negative consequences

- Terminal contributors need C++, QML, Qt, CMake, and deployment expertise.
- CI and release engineering must maintain multiple operating-system,
  architecture, and compiler lanes rather than only three generic desktop jobs.
- The repository becomes multi-language and multi-build-system.
- QML performance requires discipline around bindings and delegate complexity.
- The terminal may be GPLv3 while runtime and CLI remain Apache-2.0.
- Installers, signing, updates, and Qt dependency packaging add complexity.
- The process boundary adds serialization and local transport overhead.
- Tickoni assumes support responsibility for native Windows ARM64 because the
  MSYS2 LLVM-MinGW Qt build is outside Qt Company's official compiler matrix.
- Qt does not eliminate the charting problem. A professional chart engine is a
  separate product investment and may require custom native rendering, an
  approved commercial dependency, or a controlled embedded web component.
- Docking and workspace behavior must be designed and validated; choosing Qt
  does not make a professional-grade trading-desk workspace automatic.

### Neutral consequences

- Qt remains an application framework, not a finance-domain dependency.
- A web client, Tauri companion application, or Flutter mobile/companion client
  may coexist later without changing this terminal decision, provided it uses
  the same governed `tkgate` boundary.
- Hosted market-data, brokerage, and LLM services remain separate APIs.
- A fork may replace the GPL terminal while continuing to use the Apache runtime.

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation | Owner |
| --- | --- | --- | --- | --- |
| QML performs poorly under live updates | Medium | High | C++ models, simple reusable delegates, load tests, profiling | UI maintainers |
| UI duplicates financial logic | Medium | High | Runtime-owned fields, contract tests, architecture review | Architecture maintainers |
| GPL/Apache boundaries become unclear | Medium | High | Separate target, SPDX headers, `LICENSING.md`, legal review | Release maintainers |
| GPL-only Qt modules are added accidentally | Medium | High | Qt module allowlist and dependency inventory in CI | Release maintainers |
| Cross-platform behavior diverges | Medium | Medium | Golden fixtures, keyboard tests, snapshots, package smoke tests | UI maintainers |
| MSYS2 `CLANGARM64` Qt regressions or package gaps | Medium | High | Pin and mirror packages, maintain a native smoke suite, test upgrades before adoption, and retain a known-good Qt/toolchain bundle | Build maintainers |
| Windows ARM64 package passes CI but fails on physical devices or GPU drivers | Medium | High | Qualify on hosted native ARM64 plus physical Snapdragon-class devices; test software-rendering fallback and multiple graphics backends | UI/build maintainers |
| Qt/compiler ABI mismatch enters a package | Medium | High | Pin Qt/toolchain tuples, prohibit mixed MSVC/MinGW artifacts, inspect packaged libraries and plugins in CI | Release maintainers |
| QML workspace/docking implementation becomes bespoke and unstable | Medium | High | Prototype panel detach/reattach, persistence, focus, and multi-monitor behavior early; permit a selective Widgets/native host | UI maintainers |
| Charting scope dominates V2.19 or locks the shell to one vendor | Medium | High | Table-first release, chart-module interface, separate dependency/licensing ADR, batched governed data contracts | Product/UI maintainers |
| CLI and desktop command semantics diverge | Medium | Medium | Versioned shared command metadata and cross-client contract tests | API/CLI/UI maintainers |
| `tkgate` protocol drifts | Medium | High | Versioned schemas, compatibility tests, explicit unavailable states | API maintainers |
| Process transport becomes a bottleneck | Low | Medium | Profile, batch updates, optimize WebSocket deltas, then write a new ADR | Architecture maintainers |

## Implementation Plan

- Create `src/tickoni/ui/` as the license and ownership boundary for the official
  terminal, or use an equivalently explicit standalone application directory.
- Add a dedicated CMake target for `tickoni-terminal-qt`.
- Add `CMakePresets.json` and documented toolchain files for every supported
  platform/compiler/architecture lane.
- Use `qt_standard_project_setup()`, `qt_add_executable()`, and
  `qt_add_qml_module()` with automatic MOC, resources, QML cache compilation,
  and QML lint targets enabled.
- Add `LICENSES/GPL-3.0-only.txt`, `src/tickoni/ui/LICENSE`, SPDX headers, and a
  repository-level `LICENSING.md`.
- Keep runtime, API, and CLI code under Apache-2.0 with no dependency on Qt.
- Define the minimum versioned `tkgate` terminal view contract.
- Define shared command metadata for CLI/TUI and desktop commands, completion,
  authorization requirements, and help text.
- Define a chart-module interface for series snapshots, batched deltas,
  annotations, selections, and operator interactions without binding the shell
  to Qt Graphs or a web chart vendor.
- Implement a workspace-manager spike covering logical panes, detach/reattach,
  saved layouts, multi-monitor placement, focus routing, and restore after
  restart.
- Implement C++ `TkApiClient` and `FixtureClient` implementations behind one
  interface.
- Implement typed C++ models for case, basket, policy, impact, evidence, replay,
  commands, connection, and freshness state.
- Register C++ services and models as QML types.
- Build the shell and Tickoni style on Qt Quick Controls Basic.
- Add optional local runtime process management while retaining API-only
  communication.
- Add macOS x86_64 and arm64, Linux x86_64 and arm64, Windows x86_64
  `CLANG64`, and native Windows ARM64 `CLANGARM64` builds and launch smoke
  tests.
- Add Linux GCC release lanes and Clang compatibility lanes with explicit Qt
  ABI/package validation.
- Add native Windows ARM64 CI on GitHub Actions `windows-11-arm` and physical
  device qualification. Retain x86_64-on-ARM emulation as compatibility-only.
- Mirror the exact MSYS2 `clang64` and `clangarm64` package set, package metadata,
  source tarballs, and checksums required to reproduce Windows releases.
- Add Qt dependency, SBOM, and license inventory generation.
- Complete open-source licensing review before public binary distribution.

Migration/backward compatibility:

- Existing runtime and CLI behavior is unchanged.
- Existing deterministic demos become terminal fixtures or `tkgate` responses.
- CLI-only installations remain supported and do not require Qt.
- `tkgate` changes are backward-compatible or explicitly versioned.

Operational impact:

- Release engineering produces and tests desktop packages for three platforms.
- Support material distinguishes terminal, runtime, CLI, and hosted service
  versions.
- The terminal surfaces runtime connection, source, freshness, environment, and
  protocol compatibility.
- Crash reports distinguish terminal failures from runtime failures.

## Confirmation

- Tests: C++ model tests, QML component tests, keyboard/focus tests, API contract
  tests, cross-client command-contract tests, fixture equivalence tests,
  reconnect tests, multi-window and workspace-persistence tests, synthetic table
  performance tests, chart-module contract tests, 8-hour soak tests, and
  compiler/architecture package tests.
- Review gates: UI architecture, `tkgate`, cross-platform packaging,
  accessibility, open-source licensing, and documented alternative-framework
  comparison reviews.
- Build/CI checks: committed CMake presets; macOS x86_64/arm64; Linux
  x86_64/arm64 GCC plus Clang compatibility; Windows x86_64 `CLANG64`; native
  Windows ARM64 `CLANGARM64` on `windows-11-arm`; physical Windows-on-ARM smoke
  qualification; x64-emulation compatibility test; runtime and CLI builds
  without Qt; QML linting and
  cache compilation; Qt module allowlist; ABI/dependency inspection; SBOM, SPDX,
  and license checks; package launch smoke tests.
- Observability: connection state, API version, update counts, reconnects,
  stale-data state, command latency, model-update latency, and crash attribution.

Minimum evidence:

- One deterministic case renders the same semantic state on every required
  compiler/architecture release lane.
- A 10,000-row synthetic table remains interactive under representative updates.
- A synthetic 10–50 panel workspace can detach, restore, and survive an 8-hour
  update soak without unbounded memory growth or focus failure.
- The CLI/TUI and desktop resolve shared commands to compatible `tkgate` requests
  and policy/approval semantics.
- The terminal connects and reconnects to a local runtime without linking it.
- Runtime and CLI tests pass in an environment without Qt.
- Release packages contain the required terminal, Qt, and third-party notices.

## Deviation Criteria

A future implementation may deviate only when at least one condition applies:

- A target environment cannot support the approved Qt version, compiler ABI,
  architecture, or graphics/input stack.
- Replacing the approved MSYS2 `CLANGARM64` Windows ARM64 stack with MSVC, GCC,
  ARM64EC, another C++ standard library, or a different MinGW distribution is
  proposed. Such a change requires documented ABI, Qt module, deployment, and
  native-device validation.
- A measured product SLO cannot be met through `tkgate` after transport and model
  optimization.
- A browser, mobile, embedded, compact companion, or platform-specific product
  has materially different requirements from the official terminal; Tauri or
  Flutter may be reconsidered for that separate product.
- Advanced web charting, hosted distribution, and frontend reuse become the
  dominant product drivers rather than native workstation behavior; a Tauri or
  web-first decision then requires a separate ADR and performance prototype.
- The validated QML workspace approach cannot meet docking, focus,
  accessibility, or restore requirements. A selective Qt Widgets/native host may
  be adopted under this ADR; replacing Qt requires a new ADR.
- Tauri demonstrates a fully supported non-MSVC Windows ARM64 build, installer,
  updater, and multi-window terminal prototype that meets the same performance,
  accessibility, and visual-parity gates.
- Flutter demonstrates a supported no-MSVC Windows x86_64/ARM64 build path and a
  macOS x86_64 support horizon compatible with Tickoni's release commitments.
- Accessibility or OS integration requirements fail after a validated Qt
  prototype.
- Qt licensing, module availability, or commercial terms change materially.
- A separate utility is demonstrably better implemented with Widgets or a native
  framework and does not replace the terminal default.
- Direct linking of the Zig runtime is proposed; this requires a separate ADR for
  ABI, lifecycle, isolation, performance evidence, and licensing.

Each deviation must record:

- why the default does not apply;
- which alternative is used;
- who approved it;
- how correctness and compatibility are verified;
- whether it is temporary or permanent.

## Related Decisions and References

- V2.19: Tickoni Native Investment Terminal (`v2.19-updated.md`).
- Qt 6 Supported Platforms:
  <https://doc.qt.io/qt-6/supported-platforms.html>
- Qt for Windows supported configurations:
  <https://doc.qt.io/qt-6/windows.html>
- Qt CMake manual and QML integration:
  <https://doc.qt.io/qt-6/cmake-manual.html>
  <https://doc.qt.io/qt-6/cmake-build-qml-application.html>
  <https://doc.qt.io/qt-6/qt-add-qml-module.html>
- Qt Creator kits, compilers, and CMake presets:
  <https://doc.qt.io/qtcreator/creator-how-to-activate-kits.html>
  <https://doc.qt.io/qtcreator/creator-preferences-kits-compilers.html>
  <https://doc.qt.io/qtcreator/creator-how-to-add-custom-compilers.html>
  <https://doc.qt.io/qtcreator/creator-build-settings-cmake.html>
- Qt 6.11 officially supported Windows configurations (Windows ARM64 is listed
  with MSVC only):
  <https://doc.qt.io/qt-6/windows.html>
- MSYS2 ARM64 support and environment definitions:
  <https://www.msys2.org/docs/arm64/>
  <https://www.msys2.org/docs/environments/>
- MSYS2 native ARM64 Qt and tool packages:
  <https://packages.msys2.org/packages/mingw-w64-clang-aarch64-qt6-base>
  <https://packages.msys2.org/packages/mingw-w64-clang-aarch64-qt6-declarative>
  <https://packages.msys2.org/packages/mingw-w64-clang-aarch64-qt6-websockets>
  <https://packages.msys2.org/base/mingw-w64-qt6-graphs>
  <https://packages.msys2.org/packages/mingw-w64-clang-aarch64-qt6-tools>
- LLVM-MinGW architecture support and toolchain constraints:
  <https://github.com/mstorsjo/llvm-mingw>
- Qt cross-compilation host-tool requirements:
  <https://doc.qt.io/qt-6/cross-compiling-qt.html>
- GitHub Actions native Windows ARM64 runner reference:
  <https://docs.github.com/actions/reference/runners/github-hosted-runners>
- Microsoft guidance on x86/x64 emulation on Windows 11 ARM:
  <https://learn.microsoft.com/windows/arm/apps-on-arm-x86-emulation>
- QML and C++ Integration:
  <https://doc.qt.io/qt-6/qtqml-cppintegration-overview.html>
- Using C++ Models with Qt Quick Views:
  <https://doc.qt.io/qt-6/qtquick-modelviewsdata-cppmodels.html>
- Qt Quick `TableView`:
  <https://doc.qt.io/qt-6/qml-qtquick-tableview.html>
- Qt Quick performance guidance:
  <https://doc.qt.io/qt-6/qtquick-performance.html>
- Qt Quick Controls Basic style and customization:
  <https://doc.qt.io/qt-6/qtquickcontrols-basic.html>
  <https://doc.qt.io/qt-6/qtquickcontrols-customize.html>
- Qt licensing and GPL-only modules:
  <https://doc.qt.io/qt-6/licensing.html>
- GNU GPL FAQ on separate programs and communication mechanisms:
  <https://www.gnu.org/licenses/gpl-faq.html>
- Apache GPL compatibility:
  <https://www.apache.org/licenses/GPL-compatibility.html>
- Tauri 2 architecture, process model, frontend, licensing, and Windows ARM64
  packaging:
  <https://v2.tauri.app/concept/architecture/>
  <https://v2.tauri.app/concept/process-model/>
  <https://v2.tauri.app/start/frontend/>
  <https://v2.tauri.app/distribute/windows-installer/>
- Rust Windows LLVM/MinGW targets relevant to a non-MSVC Tauri ARM64 spike:
  <https://doc.rust-lang.org/rustc/platform-support/windows-gnullvm.html>
  <https://doc.rust-lang.org/rustc/platform-support.html>
- Flutter desktop architecture, supported deployment platforms, Windows build,
  and licensing:
  <https://docs.flutter.dev/resources/architectural-overview>
  <https://docs.flutter.dev/reference/supported-platforms>
  <https://docs.flutter.dev/platform-integration/desktop>
  <https://docs.flutter.dev/platform-integration/windows/building>
  <https://github.com/flutter/flutter>
- Comparative decision inputs supplied by the requester:
  - `Tickoni - CLI_GUI for Tickoni.pdf`, especially pages 1–6 for the web/Tauri
    architecture and professional trading-terminal workflow primitives, and pages 6–13 for the
    CLI/TUI, shared-command, and multiple-client strategy.
  - `Tickoni - App Framework for Trading.pdf`, especially pages 1–4 for the
    Qt/Tauri/Flutter workstation comparison and pages 5–12 for charting trade-offs
    and the recommendation to isolate the chart engine.
  - Original shared conversation archives:
    <https://chatgpt.com/s/t_6a7366dd7b688191a25b021a12d8fced>
    <https://chatgpt.com/s/t_6a7366fb901081919c3f8f97f7c3057b>
  The PDFs are treated as decision-analysis inputs rather than authoritative
  product or framework documentation. Platform, toolchain, and licensing facts
  are checked against the primary references above.
- Zig C-ABI export documentation, relevant to a future direct-linking option:
  <https://ziglang.org/documentation/master/>

References were reviewed on 2026-08-05. Module licenses and supported platform
configurations must be rechecked for the Qt version pinned by the build.

## Authoring Checklist

- [x] The decision question is explicit.
- [x] Seriously considered options are named.
- [x] The chosen option is an actionable rule.
- [x] Rejected options have specific reasons.
- [x] Consequences include real costs.
- [x] Deviation conditions are explicit.
- [x] Confirmation is testable.
- [x] Related internal and primary external references are included.
- [x] Instructional placeholder text has been removed.
