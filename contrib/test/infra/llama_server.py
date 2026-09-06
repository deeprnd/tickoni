#!/usr/bin/env python3
"""llama.cpp server management strategy.

Starts the server, waits for the health endpoint, and manages the PID file.
No test logic — pure infrastructure.
"""
import os
import signal
import subprocess
import sys
import tempfile
import time


def pid_file_path():
    """Return the platform-native path shared by server start and stop."""
    return os.path.join(tempfile.gettempdir(), "llama_server.pid")


def log_file_path(pid=None):
    """Return a platform-native diagnostic log path."""
    if pid is None:
        pid = os.getpid()
    return os.path.join(tempfile.gettempdir(), f"llama_server_{pid}.log")


def start_server(llama_dir, model_dir, model_file, endpoint, port):
    """Start llama-server, wait for health, write PID.

    Returns exit code 0 on success, 1 on failure.
    """
    server_bin = os.path.join(llama_dir, "llama-server" + (".exe" if os.name == "nt" else ""))
    model_path = os.path.join(model_dir, model_file)
    health_url = f"{endpoint.rstrip('/')}/health"
    pid_file = pid_file_path()
    log_file = log_file_path()

    # Canonicalize paths to resolve symlinks and prevent traversal outside
    # expected directories (CVE-style path-canonicalization guard).
    server_bin_real = os.path.realpath(server_bin)
    model_path_real = os.path.realpath(model_path)
    llama_dir_real = os.path.realpath(llama_dir)
    model_dir_real = os.path.realpath(model_dir)

    if not server_bin_real.startswith(llama_dir_real + os.sep) and server_bin_real != llama_dir_real:
        print(f"ERROR: server binary path escapes llama_dir ({server_bin_real!r})", file=sys.stderr)
        return 1

    if not model_path_real.startswith(model_dir_real + os.sep) and model_path_real != model_dir_real:
        print(f"ERROR: model path escapes model_dir ({model_path_real!r})", file=sys.stderr)
        return 1

    if not os.path.isfile(server_bin):
        print(f"ERROR: llama-server binary not found at {server_bin}", file=sys.stderr)
        print("Run: python3 ../setup/orchestrator.py llm-server", file=sys.stderr)
        return 1

    if not os.path.isfile(model_path):
        print(f"ERROR: model not found at {model_path}", file=sys.stderr)
        print("Run: python3 ../setup/orchestrator.py llm-server", file=sys.stderr)
        return 1

    # Start server in background.
    cmd = [
        server_bin,
        "-m", model_path,
        "--port", str(port),
        "--no-mmproj",
        "--reasoning-format", "none",
        "--ctx-size", "4096",
        "--cache-type-k", "q4_0",
        "--cache-type-v", "q4_0",
        "--threads", "4",
        "--batch-size", "64",
        "--ubatch-size", "32",
        "--metrics",
        "--slots",
    ]

    print(f"starting llama-server — log: {log_file}")
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    # Write PID file for llm-server-stop.
    with open(pid_file, "w") as f:
        f.write(str(proc.pid))

    # Wait for health endpoint (max 120s, 2s poll).
    print(f"waiting for llama-server at {health_url}")
    ready = False
    for _ in range(60):
        try:
            health = subprocess.run(
                ["curl", "-sf", health_url],
                capture_output=True,
                timeout=5,
            )
            if health.returncode == 0:
                ready = True
                break
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass

        # Check if process died.
        if proc.poll() is not None:
            stdout, stderr = proc.communicate()
            print(f"llama-server exited prematurely (exit {proc.returncode})", file=sys.stderr)
            print(stderr.decode(errors="replace")[-500:], file=sys.stderr)
            return 1

        time.sleep(2)

    if not ready:
        proc.terminate()
        try:
            stdout, stderr = proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate()
        print(f"llama-server did not become ready within 120s", file=sys.stderr)
        return 1

    print("llama-server ready")
    print(f"server PID: {proc.pid}")
    return 0


def stop_server(pid_file):
    """Kill the server process tracked by pid_file.

    Returns 0 on success, 1 if no PID file or process not found.
    """
    if not os.path.isfile(pid_file):
        print(f"no PID file at {pid_file}", file=sys.stderr)
        return 1

    with open(pid_file) as f:
        pid = int(f.read().strip())

    try:
        os.kill(pid, signal.SIGTERM)
        proc = subprocess.Popen(
            ["wait"],  # placeholder — we just signal and move on
        )
        # Give the process a moment to exit.
        time.sleep(1)
        # Force kill if still alive.
        try:
            os.kill(pid, 0)
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        print(f"stopped llama-server (PID {pid})")
    except ProcessLookupError:
        print(f"process {pid} already gone", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"failed to stop server: {e}", file=sys.stderr)
        return 1

    os.remove(pid_file)
    return 0
