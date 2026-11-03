"""Ajustes aprovados pelo RH; nunca altera ou exclui registros de ponto."""

import re
from datetime import datetime, timezone

from sqlalchemy import func, select

from app.models import JustificativasAjustes, RegistrosPonto, SituacaoPonto, StatusAjuste, TipoOcorrencia, TipoPonto
from .rh_access import GestaoError, executar_empresa, executar_rh
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
        # Nomes públicos preservados para os clientes administrativos existentes.
        return {
            "id": str(ajuste.id), "empresa_id": str(ajuste.empresa_id),
            "usuario_id": str(ajuste.usuario_id),
            "registro_original_id": str(ajuste.registro_ponto_id) if ajuste.registro_ponto_id else None,
            "nova_data_hora": ajuste.ocorrido_em_proposto.astimezone(timezone.utc).isoformat(),
            "tipo": TipoPonto(ajuste.tipo_proposto).name,
            "motivo_texto": ajuste.justificativa,
            "tipo_ocorrencia": ajuste.tipo_ocorrencia,
            "status_analise": StatusAjuste(ajuste.status).name,
            "solicitado_por_id": str(ajuste.solicitado_por_id),
            "gestor_aprovador_id": str(ajuste.decidido_por_id),
            "decidido_em": ajuste.decidido_em.astimezone(timezone.utc).isoformat(),
            "sequencia_decisao": ajuste.sequencia_decisao,
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
                ).with_for_update())
                if original is None:
                    raise GestaoError("Batida não encontrada nesta empresa.", 404, "PONTO_NAO_ENCONTRADO")
                AjustePontoService._exigir_nao_invalidado(session, empresa, original.id)

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

    @staticmethod
    def _exigir_nao_invalidado(session, empresa, registro_id):
        existente = AjustePontoService._decisao_atual(session, empresa, registro_id)
        if existente is not None and existente.tipo_ocorrencia == TipoOcorrencia.INVALIDACAO_GESTOR.value:
            raise GestaoError("Esta marcação está invalidada. O RH pode reaprovar com justificativa.", 409, "PONTO_JA_INVALIDADO")

    @staticmethod
    def _decisao_atual(session, empresa, registro_id):
        return session.scalar(select(JustificativasAjustes).where(
            JustificativasAjustes.empresa_id == empresa,
            JustificativasAjustes.registro_ponto_id == registro_id,
            JustificativasAjustes.sequencia_decisao.is_not(None),
            JustificativasAjustes.status == StatusAjuste.APROVADO,
        ).order_by(JustificativasAjustes.sequencia_decisao.desc()).limit(1))

    @staticmethod
    def invalidar_marcacao(usuario_id, empresa_id, registro_id, dados, session=None):
        return AjustePontoService._decidir_marcacao(usuario_id, empresa_id, registro_id, dados,
            aprovar=False, session=session)

    @staticmethod
    def aprovar_marcacao(usuario_id, empresa_id, registro_id, dados, session=None):
        return AjustePontoService._decidir_marcacao(usuario_id, empresa_id, registro_id, dados,
            aprovar=True, session=session)

    @staticmethod
    def reaprovar_marcacao(usuario_id, empresa_id, registro_id, dados, session=None):
        return AjustePontoService._decidir_marcacao(usuario_id, empresa_id, registro_id, dados,
            aprovar=True, reaprovar=True, session=session)

    @staticmethod
    def _decidir_marcacao(usuario_id, empresa_id, registro_id, dados, *, aprovar, reaprovar=False, session=None):
        def operacao(session, empresa):
            campos = {"motivo_texto", "invalidacao_id"} if reaprovar else {"motivo_texto"}
            if not isinstance(dados, dict) or set(dados) != campos:
                raise GestaoError("Informe motivo_texto e invalidacao_id para reaprovar." if reaprovar
                    else "Informe somente motivo_texto para analisar a marcação.")
            motivo = dados["motivo_texto"]
            if not isinstance(motivo, str) or not 1 <= len(motivo.strip()) <= 5000:
                raise GestaoError("A justificativa deve conter entre 1 e 5000 caracteres.")
            alvo_id = identificador(registro_id, "registro_id")
            # Bloqueio de leitura serializa invalidações concorrentes; não faz UPDATE.
            original = session.scalar(select(RegistrosPonto).where(
                RegistrosPonto.id == alvo_id, RegistrosPonto.empresa_id == empresa,
            ).with_for_update())
            if original is None:
                raise GestaoError("Batida não encontrada nesta empresa.", 404, "PONTO_NAO_ENCONTRADO")
            atual = AjustePontoService._decisao_atual(session, empresa, original.id)
            if reaprovar:
                invalidacao_id = identificador(dados["invalidacao_id"], "invalidacao_id")
                if atual is None or atual.tipo_ocorrencia != TipoOcorrencia.INVALIDACAO_GESTOR.value or atual.id != invalidacao_id:
                    raise GestaoError("A análise desta marcação mudou. Consulte o espelho novamente.", 409, "DECISAO_DESATUALIZADA")
            elif atual is not None and atual.tipo_ocorrencia == TipoOcorrencia.INVALIDACAO_GESTOR.value:
                raise GestaoError("Esta marcação está invalidada. O RH pode reaprovar com justificativa.", 409, "PONTO_JA_INVALIDADO")
            elif aprovar:
                if original.situacao == SituacaoPonto.ACEITA:
                    raise GestaoError("Esta marcação já foi aceita pelo sistema.", 409, "PONTO_JA_ACEITO")
                existente = session.scalar(select(JustificativasAjustes.id).where(
                    JustificativasAjustes.empresa_id == empresa,
                    JustificativasAjustes.registro_ponto_id == original.id,
                    JustificativasAjustes.status == StatusAjuste.APROVADO,
                    JustificativasAjustes.tipo_ocorrencia.in_([TipoOcorrencia.APROVACAO_GESTOR.value,
                        TipoOcorrencia.REAPROVACAO_RH.value, TipoOcorrencia.AJUSTE.value]),
                ).limit(1))
                if existente is not None:
                    raise GestaoError("Esta marcação já possui aprovação ou correção aprovada.", 409, "PONTO_JA_APROVADO")
            autor = identificador(usuario_id, "usuario_id do responsável")
            sequencia = (session.scalar(select(func.max(JustificativasAjustes.sequencia_decisao)).where(
                JustificativasAjustes.empresa_id == empresa, JustificativasAjustes.registro_ponto_id == original.id)) or 0) + 1
            ajuste = JustificativasAjustes(
                empresa_id=empresa, usuario_id=original.usuario_id,
                registro_ponto_id=original.id, solicitado_por_id=autor,
                tipo_ocorrencia=(TipoOcorrencia.REAPROVACAO_RH if reaprovar else
                    TipoOcorrencia.APROVACAO_GESTOR if aprovar else TipoOcorrencia.INVALIDACAO_GESTOR).value,
                sequencia_decisao=sequencia,
                justificativa=motivo.strip(), tipo_proposto=original.tipo,
                ocorrido_em_proposto=original.ocorrido_em,
                status=StatusAjuste.APROVADO, decidido_por_id=autor,
                decidido_em=datetime.now(timezone.utc),
            )
            session.add(ajuste)
            session.flush()
            payload = {"ajuste": AjustePontoService._json(ajuste)}
            session.commit()
            return payload, 201

        # Autor e empresa são revalidados no banco, incluindo o papel RH/Gestor.
        executor = executar_rh if reaprovar else executar_empresa
        return executor(usuario_id, empresa_id, operacao, session)
