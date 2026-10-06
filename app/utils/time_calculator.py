"""Durações em minutos e projeções JSON de ciclos por tempo decorrido.

Um ciclo 12x36 dura 48 horas; 24x72 dura 96 horas. O intervalo reduz a
jornada líquida, mas não encurta o plantão nem desloca o ciclo seguinte.
"""

from datetime import date, datetime, time, timedelta, timezone
import re
from zoneinfo import ZoneInfo


def _hora(valor):
    if isinstance(valor, str):
        # Python 3.14 pode normalizar 24:00 para 00:00; isso perderia o dia.
        if not re.fullmatch(r"[0-9]{2}:[0-9]{2}(?::00)?", valor) or int(valor[:2]) >= 24:
            raise ValueError("Hora inválida; use HH:MM entre 00:00 e 23:59.")
        try:
            valor = time.fromisoformat(valor)
        except ValueError:
            raise ValueError("Hora inválida; use HH:MM.") from None
    if not isinstance(valor, time) or valor.tzinfo is not None or valor.second or valor.microsecond:
        raise ValueError("Hora deve ser local, com precisão de minutos.")
    return valor


def _data(valor):
    if isinstance(valor, str):
        try:
            valor = date.fromisoformat(valor)
        except ValueError:
            raise ValueError("Data inválida; use AAAA-MM-DD.") from None
    if type(valor) is not date:
        raise ValueError("Informe uma data, sem horário.")
    return valor


class TimeCalculator:
    @staticmethod
    def calcular_duracao_turno(
        hora_inicio: time | str, hora_fim: time | str, tempo_intervalo: int = 0, *,
        fim_dia_seguinte: bool = False,
    ) -> int:
        """Retorna minutos líquidos; 19:00–07:00 sem intervalo retorna 720.

        Início == fim só é permitido com fim_dia_seguinte=True (24 horas).
        Intervalos devem ser inteiros, positivos ou zero, menores que o turno.
        """
        inicio, fim = _hora(hora_inicio), _hora(hora_fim)
        if type(tempo_intervalo) is not int or tempo_intervalo < 0:
            raise ValueError("Tempo de intervalo deve ser um inteiro não negativo em minutos.")
        if type(fim_dia_seguinte) is not bool:
            raise ValueError("fim_dia_seguinte deve ser booleano.")
        if inicio == fim and not fim_dia_seguinte:
            raise ValueError("Turno de 24 horas exige fim_dia_seguinte=True.")
        if fim_dia_seguinte and fim > inicio:
            raise ValueError("Turnos não podem ultrapassar 24 horas.")
        minutos = (fim.hour * 60 + fim.minute) - (inicio.hour * 60 + inicio.minute)
        if fim < inicio or fim_dia_seguinte:
            minutos += 1440
        if tempo_intervalo >= minutos:
            raise ValueError("Intervalo deve ser menor que a duração do turno.")
        return minutos - tempo_intervalo

    @staticmethod
    def projetar_escala_ciclica(
        modelo: str, data_referencia: date | str, hora_inicio: time | str,
        hora_fim: time | str, n_dias: int, *, data_inicio: date | str | None = None,
        tempo_intervalo: int = 0, fim_dia_seguinte: bool = False,
        fuso_horario: str = "America/Sao_Paulo",
    ) -> list[dict]:
        """Retorna N dias com trabalho/folga e intervalos exatos [início, fim).

        A referência ancora o primeiro plantão; não há plantões anteriores.
        Inclui a madrugada de plantões iniciados antes da janela consultada.
        Os intervalos são recortados por dia; inicio_turno/fim_turno preservam
        o plantão original. Todos os timestamps JSON incluem offset do fuso.
        Em mudanças de horário de verão os ciclos mantêm 48/96 horas reais.
        Não aplica feriados, afastamentos ou decisões de conflito (Services).
        """
        ciclos = {"12x36": (720, 2880), "24x72": (1440, 5760)}
        if modelo not in ciclos:
            raise ValueError("Projeção cíclica suporta somente 12x36 e 24x72.")
        if type(n_dias) is not int or n_dias < 0:
            raise ValueError("n_dias deve ser um inteiro não negativo.")
        referencia = _data(data_referencia)
        primeiro_dia = referencia if data_inicio is None else _data(data_inicio)
        hora = _hora(hora_inicio)
        bruto = TimeCalculator.calcular_duracao_turno(
            hora, hora_fim, fim_dia_seguinte=fim_dia_seguinte,
        )
        liquido = TimeCalculator.calcular_duracao_turno(
            hora, hora_fim, tempo_intervalo, fim_dia_seguinte=fim_dia_seguinte,
        )
        esperado, ciclo = ciclos[modelo]
        if bruto != esperado:
            raise ValueError(f"Modelo {modelo} exige um turno de {esperado} minutos brutos.")
        zona = ZoneInfo(fuso_horario)
        local = datetime.combine(referencia, hora, tzinfo=zona)
        # Rejeita âncoras ambíguas ou inexistentes para não escolher um instante
        # silenciosamente. Datas normais têm o mesmo offset em fold=0 e fold=1.
        if local.utcoffset() != local.replace(fold=1).utcoffset():
            raise ValueError("Hora de referência ambígua ou inexistente no fuso informado.")
        utc = timezone.utc
        ancora = local.astimezone(utc)
        periodo = timedelta(minutes=ciclo)
        duracao = timedelta(minutes=bruto)
        dias = []
        for numero in range(n_dias):
            dia = primeiro_dia + timedelta(days=numero)
            inicio_dia = datetime.combine(dia, time.min, tzinfo=zona).astimezone(utc)
            fim_dia = datetime.combine(dia + timedelta(days=1), time.min, tzinfo=zona).astimezone(utc)
            # Índice direto evita iterar desde a referência em consultas futuras.
            indice = max(0, (inicio_dia - ancora) // periodo)
            inicio_turno = ancora + indice * periodo
            intervalos = []
            while inicio_turno < fim_dia:
                fim_turno = inicio_turno + duracao
                inicio = max(inicio_dia, inicio_turno)
                fim = min(fim_dia, fim_turno)
                if inicio < fim:
                    intervalos.append({
                        "inicio": inicio.astimezone(zona).isoformat(),
                        "fim": fim.astimezone(zona).isoformat(),
                        "inicio_turno": inicio_turno.astimezone(zona).isoformat(),
                        "fim_turno": fim_turno.astimezone(zona).isoformat(),
                        "duracao_no_dia_minutos": int((fim - inicio).total_seconds() // 60),
                        "duracao_turno_liquida_minutos": liquido,
                        "tempo_intervalo": tempo_intervalo,
                    })
                inicio_turno += periodo
            dias.append({"data": dia.isoformat(), "trabalha": bool(intervalos), "intervalos": intervalos})
        return dias
