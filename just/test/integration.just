# Test: Integration recipes

test-integration-fd:
    @true

# Tickoni integration lane: transport and boundary wiring against local mocks.
test-integration-tk-linux-x86:
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test)

test-integration-tk-linux-arm:
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test)

test-integration-tk-macos-x86:
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test)

test-integration-tk-macos-arm:
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test)

# Bare dispatcher; canonical platform recipes are in dispatch map.
test-integration-tk:
	{{ python }} {{ justfile_dir }}/scripts/dispatch test-integration-tk

test-integration-all:
	{{ python }} {{ justfile_dir }}/contrib/tool/readme/run-badged-command.py integration bash -c "just test-integration-fd && just test-integration-tk"
