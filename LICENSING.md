# Tickoni Licensing

Tickoni is a mixed-license repository.

## Apache-2.0 components

Unless expressly stated otherwise, the following are licensed under
the Apache License, Version 2.0:

- the Firedancer-derived execution infrastructure;
- the Tickoni Zig runtime;
- the Tickoni CLI;
- `tkapi` schemas and protocol definitions;
- non-UI SDKs and generated clients;
- general build, test, and technical documentation.

The Apache-2.0 license text is contained in `LICENSE`.

## GPL-3.0-only terminal

The official Tickoni desktop terminal uses Qt Graphs under Qt's
open-source GPLv3 terms and is therefore distributed under
GPL-3.0-only.

All source code under `src/tickoni/ui/`, including C++, QML,
terminal-specific CMake files, terminal resources, and terminal tests,
is licensed under GPL-3.0-only unless a file expressly states
otherwise.

The GPL-3.0-only license text is contained in
`LICENSES/GPL-3.0-only.txt`.

The Tickoni runtime and terminal are separate programs and separate
processes.

For local operation, the terminal communicates with `tk_api` through
bounded shared-memory channels. For remote operation, network
communication is mediated by the Tickoni gateway.

The runtime and CLI remain Apache-2.0.

Apache-2.0 libraries, schemas, or generated clients used by the
terminal retain their original Apache-2.0 licensing. The distributed
terminal combination is provided under GPL-3.0-only.

## Creative content

Tickoni fictional lore, characters, narrative release material,
illustrations, banners, and related creative content are maintained
in the separate `deeprnd/tickoni-content` repository, included here as the
`content/` Git submodule.

That repository is separately licensed and is not covered by the
Apache-2.0 or GPL-3.0-only licenses applicable to Tickoni software.

The license contained in the `deeprnd/tickoni-content` repository governs
those materials.

## Third-party software

Qt, Qt Graphs, and other dependencies retain their respective
copyrights and licenses.

The licenses and attribution requirements for the exact Qt libraries,
plugins, and other third-party components distributed with the terminal
must be preserved in the terminal's third-party notices.

See `NOTICE` for repository-level attributions.
