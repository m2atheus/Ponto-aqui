"""Recarga do servidor local sem habilitar o debugger automaticamente."""
from pathlib import Path
import runpy
from types import SimpleNamespace

import pytest

import app


@pytest.mark.parametrize(("reload_env", "expected"), [(None, True), ("0", False), ("1", True)])
def test_dev_server_reloads_routes_without_enabling_debugger(monkeypatch, reload_env, expected):
    captured = {}
    monkeypatch.setattr(app, "create_app", lambda: SimpleNamespace(run=lambda **kwargs: captured.update(kwargs)))
    monkeypatch.setenv("FLASK_DEBUG", "0")
    if reload_env is None:
        monkeypatch.delenv("FLASK_RELOAD", raising=False)
    else:
        monkeypatch.setenv("FLASK_RELOAD", reload_env)
    runpy.run_path(str(Path(__file__).resolve().parents[1] / "run.py"), run_name="__main__")
    assert captured == {"debug": False, "use_reloader": expected}
