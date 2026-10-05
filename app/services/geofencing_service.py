"""Distância geodésica aproximada por Haversine, calculada no servidor."""
import math
from decimal import Decimal, ROUND_HALF_UP

from app.models import PoliticaLocalizacao, SituacaoPonto


class GeofencingService:
    @staticmethod
    def distancia_metros(latitude, longitude, centro_latitude, centro_longitude):
        lat1, lon1, lat2, lon2 = map(math.radians, map(float, (
            latitude, longitude, centro_latitude, centro_longitude)))
        a = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
        return 6371008.8 * 2 * math.asin(math.sqrt(max(0, min(1, a))))

    @staticmethod
    def avaliar(marcacao, setor, aparelho_registrado):
        distancia = None if marcacao.latitude is None else GeofencingService.distancia_metros(
            marcacao.latitude, marcacao.longitude, setor.latitude_centro, setor.longitude_centro)
        motivos, recusada = [], False
        if not aparelho_registrado:
            motivos.append("APARELHO_NAO_REGISTRADO")
            recusada = True
        if setor.politica_localizacao != PoliticaLocalizacao.IGNORAR:
            if distancia is None or distancia > float(setor.raio_metros):
                motivos.append("LOCALIZACAO_AUSENTE" if distancia is None else "FORA_DO_PERIMETRO")
                recusada = recusada or setor.politica_localizacao == PoliticaLocalizacao.BLOQUEAR
        if abs(marcacao.desvio) > setor.limite_desvio_relogio_segundos:
            motivos.append("DESVIO_RELOGIO_ACIMA_DO_LIMITE")
        situacao = (SituacaoPonto.RECUSADA if recusada else
                    SituacaoPonto.PENDENTE if motivos else SituacaoPonto.ACEITA)
        distancia_db = None if distancia is None else Decimal(str(distancia)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
        return situacao, motivos, distancia_db
