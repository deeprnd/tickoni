#!/usr/bin/env python3
"""Test infrastructure orchestrator.

Facade pattern: single CLI that hides llama.cpp server management and
Zig test/build execution behind focused strategy modules.

Usage:
    python3 orchestrator.py llm-server-start          # start server, wait for health
    python3 orchestrator.py llm-server-stop           # kill server by PID
    python3 orchestrator.py system-test               # full lifecycle: start → zig-test → stop
"""
import argparse
import os
import sys


_script_dir = os.path.dirname(os.path.abspath(__file__))
if _script_dir not in sys.path:
    sys.path.insert(0, _script_dir)


class Orchestrator:
    """Facade: routes commands to infra strategy modules."""

    # Default paths (same as run_system_model_tests.sh).
    LLAMA_DIR = os.environ.get("TK_LLAMA_CPP_DIR", os.path.expanduser("~/work/models/llama.cpp"))
    MODEL_DIR = os.environ.get("TK_HF_MODEL_DIR", os.path.expanduser("~/work/models/gemma/gemma-4-E2B-it-qat-GGUF"))
    MODEL_FILE = os.environ.get("TK_HF_MODEL_FILE", "gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf")
    ENDPOINT = os.environ.get("TK_LLM_ENDPOINT", "http://127.0.0.1:9931/v1")
    PORT = 9931

    def llm_server_start(self):
        """Start llama.cpp server, wait for health, print PID."""
        from infra.llama_server import start_server
        return start_server(
            llama_dir=self.LLAMA_DIR,
            model_dir=self.MODEL_DIR,
            model_file=self.MODEL_FILE,
            endpoint=self.ENDPOINT,
            port=self.PORT,
        )

    def llm_server_stop(self):
        """Kill llama.cpp server by PID."""
        from infra.llama_server import pid_file_path, stop_server
        pid_file = pid_file_path()
        stop_server(pid_file)

    def zig_test(self, target):
        """Run `zig build <target>` with tests enabled."""
        from infra.zig_build import run_zig_build
        return run_zig_build(target=target, run_tests=True)

    def system_test(self):
        """Run the full system-test lifecycle: start server, run tests, stop server."""
        print("=== Phase 1: Start llama.cpp server ===")
        rc = self.llm_server_start()
        if rc != 0:
            print("Server failed to start, aborting", file=sys.stderr)
            return rc

        print("\n=== Phase 2: Run zig-test ===")
        rc = self.zig_test("system-test")
        if rc != 0:
            print("zig-test failed, proceeding to cleanup", file=sys.stderr)

        print("\n=== Phase 3: Stop llama.cpp server ===")
        self.llm_server_stop()

        return rc

    def dynamic_test_opts(self):
        """Run dynamic resource detection and output TEST_OPTS + LDFLAGS_EXE."""
        from infra.dynamic_test_opts import run_dynamic_test_opts
        return run_dynamic_test_opts()


def main():
    parser = argparse.ArgumentParser(description="Test infrastructure orchestrator")
    sub = parser.add_subparsers(dest="command", required=True)

    # llm-server-start
    sub.add_parser("llm-server-start", help="Start llama.cpp server and wait for health")

    # llm-server-stop
    sub.add_parser("llm-server-stop", help="Stop llama.cpp server by PID file")

    # zig-test
    zig_test_p = sub.add_parser("zig-test", help="Build and run Zig test target")
    zig_test_p.add_argument("--target", required=True, help="Zig build target")

    # system-test
    sub.add_parser("system-test", help="Full system-test lifecycle: start → zig-test → stop")

    # dynamic-test-opts
    sub.add_parser("dynamic-test-opts", help="Compute TEST_OPTS and LDFLAGS_EXE from system resources")

    args = parser.parse_args()
    orch = Orchestrator()

    if args.command == "llm-server-start":
        orch.llm_server_start()
    elif args.command == "llm-server-stop":
        orch.llm_server_stop()
    elif args.command == "zig-test":
        sys.exit(orch.zig_test(args.target))
    elif args.command == "system-test":
        sys.exit(orch.system_test())
    elif args.command == "dynamic-test-opts":
        orch.dynamic_test_opts()


if __name__ == "__main__":
    main()
