"""Regression tests for portable llama-server runtime paths."""

import sys
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from contrib.test import orchestrator

# The CLI adds contrib/test to sys.path and imports this as `infra.llama_server`.
# Use that same module identity so the stop-path regression test patches the
# actual dependency used by Orchestrator.
from infra import llama_server


def test_runtime_paths_use_platform_temp_directory(monkeypatch, tmp_path):
    monkeypatch.setattr(llama_server.tempfile, "gettempdir", lambda: str(tmp_path))

    assert llama_server.pid_file_path() == str(tmp_path / "llama_server.pid")
    assert llama_server.log_file_path(12345) == str(tmp_path / "llama_server_12345.log")


def test_orchestrator_stop_uses_same_pid_path(monkeypatch, tmp_path):
    monkeypatch.setattr(llama_server.tempfile, "gettempdir", lambda: str(tmp_path))
    observed = {}

    def fake_stop_server(pid_file):
        observed["pid_file"] = pid_file
        return 0

    monkeypatch.setattr(llama_server, "stop_server", fake_stop_server)
    orchestrator.Orchestrator().llm_server_stop()

    assert Path(observed["pid_file"]) == tmp_path / "llama_server.pid"
