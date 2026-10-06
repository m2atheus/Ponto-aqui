from datetime import datetime, time, timedelta
import json

import pytest

from app.utils.time_calculator import TimeCalculator as Calculator


@pytest.mark.parametrize("inicio,fim,intervalo,seguinte,esperado", [
    ("08:00", "17:00", 60, False, 480),
    ("19:00", "07:00", 0, False, 720),
    (time(23, 30), time(0, 30), 15, False, 45),
    ("08:00", "08:00", 60, True, 1380),
    ("19:00", "07:00", 60, True, 660),
])
def test_duration(inicio, fim, intervalo, seguinte, esperado):
    assert Calculator.calcular_duracao_turno(
        inicio, fim, intervalo, fim_dia_seguinte=seguinte,
    ) == esperado


@pytest.mark.parametrize("inicio,fim,intervalo,seguinte", [
    ("08:00", "08:00", 0, False),
    ("08:00", "17:00", 0, True),
    ("19:00", "07:00", 720, False),
    ("08:00", "17:00", -1, False),
    ("08:00", "17:00", 1.5, False),
    ("08:00", "17:00", True, False),
    ("08:00", "17:00", 0, "true"),
    ("08:00:01", "17:00", 0, False),
    ("08:00+00:00", "17:00", 0, False),
    ("24:00", "07:00", 0, False),
])
def test_invalid_duration(inicio, fim, intervalo, seguinte):
    with pytest.raises(ValueError):
        Calculator.calcular_duracao_turno(inicio, fim, intervalo, fim_dia_seguinte=seguinte)


def projection(**changes):
    values = dict(modelo="12x36", data_referencia="2026-01-01", hora_inicio="19:00",
                  hora_fim="07:00", n_dias=4)
    values.update(changes)
    return Calculator.projetar_escala_ciclica(**values)


def test_projection_includes_night_and_serializes_to_json():
    days = projection()
    assert [day["data"] for day in days] == [f"2026-01-0{i}" for i in range(1, 5)]
    assert [day["intervalos"][0]["duracao_no_dia_minutos"] for day in days] == [300, 420, 300, 420]
    assert days[0]["intervalos"][0]["inicio_turno"] == "2026-01-01T19:00:00-03:00"
    assert days[1]["intervalos"][0]["fim"] == "2026-01-02T07:00:00-03:00"
    json.dumps(days)


def test_projection_distinguishes_days_off_and_uses_cycle_not_interval():
    days = projection(hora_inicio="07:00", hora_fim="19:00", n_dias=5, tempo_intervalo=60)
    assert [day["trabalha"] for day in days] == [True, False, True, False, True]
    assert days[2]["intervalos"][0]["inicio"] == "2026-01-03T07:00:00-03:00"
    assert days[2]["intervalos"][0]["duracao_turno_liquida_minutos"] == 660


def test_window_includes_previous_shift_and_no_shifts_before_reference():
    days = projection(data_inicio="2026-01-02", n_dias=1)
    assert days[0]["intervalos"][0]["inicio_turno"].startswith("2026-01-01T19:00")
    days = projection(data_inicio="2025-12-30", n_dias=3)
    assert [day["trabalha"] for day in days] == [False, False, True]
    assert projection(n_dias=0) == []


def test_24x72_and_half_open_midnight_endpoint():
    days = projection(modelo="24x72", hora_inicio="00:00", hora_fim="00:00",
                      fim_dia_seguinte=True, n_dias=5)
    assert [day["trabalha"] for day in days] == [True, False, False, False, True]
    assert days[0]["intervalos"][0]["duracao_no_dia_minutos"] == 1440


def test_distant_window_preserves_reference_phase():
    days = projection(data_inicio="2046-01-01", n_dias=3)
    interval = next(day["intervalos"][0] for day in days if day["trabalha"])
    reference = datetime.fromisoformat("2026-01-01T19:00:00-03:00")
    start = datetime.fromisoformat(interval["inicio_turno"])
    assert (start - reference) % timedelta(hours=48) == timedelta(0)


def test_dst_cycle_keeps_exact_elapsed_hours():
    days = projection(data_referencia="2026-03-07", fuso_horario="America/New_York", n_dias=4)
    original = {i["inicio_turno"]: i for d in days for i in d["intervalos"]}
    starts = sorted(datetime.fromisoformat(s) for s in original)
    assert starts[1] - starts[0] == timedelta(hours=48)
    for i in original.values():
        assert datetime.fromisoformat(i["fim_turno"]) - datetime.fromisoformat(i["inicio_turno"]) == timedelta(hours=12)


@pytest.mark.parametrize("changes", [
    {"modelo": "5x2"}, {"n_dias": -1}, {"n_dias": True}, {"n_dias": 1.5},
    {"data_referencia": "2026-02-30"}, {"data_inicio": datetime(2026, 1, 1)},
    {"hora_inicio": "08:00", "hora_fim": "17:00"},
    {"data_referencia": "2026-03-08", "hora_inicio": "02:00", "hora_fim": "14:00", "fuso_horario": "America/New_York"},
    {"data_referencia": "2026-11-01", "hora_inicio": "01:00", "hora_fim": "13:00", "fuso_horario": "America/New_York"},
])
def test_invalid_projection(changes):
    with pytest.raises(ValueError):
        projection(**changes)
