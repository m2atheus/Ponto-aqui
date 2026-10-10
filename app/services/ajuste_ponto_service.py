"""Ajustes aprovados pelo RH; nunca altera ou exclui registros de ponto."""

import re
from datetime import datetime, timezone

from sqlalchemy import select

from app.models import JustificativasAjustes, RegistrosPonto, StatusAjuste, TipoPonto
from .rh_access import GestaoError, executar_rh
from .w06_validation import funcionario, identificador


class AjustePontoService:
    @staticmethod
    def _validar(dados, *, correcao):
        campos = {"usuario_id", "funcionario_id", "nova_data_hora", "motivo_texto", "tipo"}
        if correcao:
            campos.add("registro_original_id")
        if not isinstance(dados, dict) or dados.keys() - campos:
            raise GestaoError("Informe os dados do ajuste, sem campos desconhecidos.")

        motivo = dados.get("motivo_texto")
        if not isinstance(motivo, str) or not 1 <= len(motivo.strip()) <= 5000:
            raise GestaoError("A justificativa deve conter entre 1 e 5000 caracteres.")

        valor = dados.get("nova_data_hora")
        if not isinstance(valor, str) or not re.fullmatch(
            r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,6})?)?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)", valor
        ):
            raise GestaoError("nova_data_hora deve usar ISO 8601 com fuso, por exemplo 2026-10-10T08:00:00-03:00.")
        try:
            instante = datetime.fromisoformat(valor.replace("Z", "+00:00")).astimezone(timezone.utc)
        except (ValueError, OverflowError):
            raise GestaoError("nova_data_hora contém uma data ou horário inválido.") from None

        tipo = None
        if "tipo" in dados or not correcao:
            try:
                # Aceita ENTRADA/SAIDA e os valores existentes Entrada/Saida.
                valor_tipo = dados.get("tipo")
                tipo = TipoPonto.__members__.get(valor_tipo) if isinstance(valor_tipo, str) else None
                tipo = tipo or TipoPonto(valor_tipo)
            except (ValueError, TypeError):
                raise GestaoError("tipo deve ser ENTRADA, INICIO_INTERVALO, FIM_INTERVALO ou SAIDA.") from None
        return instante, motivo.strip(), tipo

    @staticmethod
    def _json(ajuste):
        # Nomes públicos mapeados às colunas existentes; dispensa migration.
        return {
            "id": str(ajuste.id), "empresa_id": str(ajuste.empresa_id),
            "usuario_id": str(ajuste.usuario_id),
            "registro_original_id": str(ajuste.registro_ponto_id) if ajuste.registro_ponto_id else None,
            "nova_data_hora": ajuste.ocorrido_em_proposto.astimezone(timezone.utc).isoformat(),
            "tipo": TipoPonto(ajuste.tipo_proposto).name,
            "motivo_texto": ajuste.justificativa,
            "status_analise": StatusAjuste(ajuste.status).name,
            "solicitado_por_id": str(ajuste.solicitado_por_id),
            "gestor_aprovador_id": str(ajuste.decidido_por_id),
            "decidido_em": ajuste.decidido_em.astimezone(timezone.utc).isoformat(),
        }

    @staticmethod
    def _criar(usuario_id, empresa_id, dados, *, correcao, session=None):
        def operacao(session, empresa):
            instante, motivo, tipo = AjustePontoService._validar(dados, correcao=correcao)
            original = None
            if correcao:
                registro_id = identificador(dados.get("registro_original_id"), "registro_original_id")
                original = session.scalar(select(RegistrosPonto).where(
                    RegistrosPonto.id == registro_id, RegistrosPonto.empresa_id == empresa,
                ))
                if original is None:
                    raise GestaoError("Batida não encontrada nesta empresa.", 404, "PONTO_NAO_ENCONTRADO")

            alvo = funcionario(
                session, empresa, funcionario_id=dados.get("funcionario_id"),
                usuario_id=dados.get("usuario_id") if dados.get("usuario_id") is not None
                else (original.usuario_id if original is not None else None),
            )
            if alvo.usuario_id is None:
                raise GestaoError("O funcionário precisa de uma conta de usuário vinculada para receber ajustes.",
                    400, "FUNCIONARIO_SEM_USUARIO")
            if original is not None and original.usuario_id != alvo.usuario_id:
                raise GestaoError("Batida não encontrada para este funcionário.", 404, "PONTO_NAO_ENCONTRADO")

            autor_id = identificador(usuario_id, "usuario_id do RH")
            ajuste = JustificativasAjustes(
                empresa_id=empresa, usuario_id=alvo.usuario_id,
                registro_ponto_id=original.id if original is not None else None,
                solicitado_por_id=autor_id, justificativa=motivo,
                tipo_proposto=tipo if tipo is not None else original.tipo,
                ocorrido_em_proposto=instante, status=StatusAjuste.APROVADO,
                decidido_por_id=autor_id, decidido_em=datetime.now(timezone.utc),
            )
            session.add(ajuste)
            session.flush()
            payload = {"ajuste": AjustePontoService._json(ajuste)}
            session.commit()
            return payload, 201

        # Reconstrói o perfil no banco e verifica empresa/conta ativa e papel RH.
        return executar_rh(usuario_id, empresa_id, operacao, session)

    @staticmethod
    def inserir_ponto_manual_rh(usuario_id, empresa_id, dados, session=None):
        return AjustePontoService._criar(usuario_id, empresa_id, dados, correcao=False, session=session)

    @staticmethod
    def corrigir_ponto_existente_rh(usuario_id, empresa_id, dados, session=None):
        return AjustePontoService._criar(usuario_id, empresa_id, dados, correcao=True, session=session)
