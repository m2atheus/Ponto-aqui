"""Projeção de decisões aprovadas; nunca modifica objetos RegistrosPonto."""
from datetime import timezone
from types import SimpleNamespace

from app.models import SituacaoPonto, StatusAjuste, TipoOcorrencia


def auditoria(ajuste):
    return {"id": str(ajuste.id), "motivo_texto": ajuste.justificativa,
        "gestor_aprovador_id": str(ajuste.decidido_por_id),
        "tipo_ocorrencia": ajuste.tipo_ocorrencia,
        "sequencia_decisao": ajuste.sequencia_decisao,
        "decidido_em": ajuste.decidido_em.astimezone(timezone.utc).isoformat()}


def projetar_decisoes(pontos, ajustes, linhas, zona, avisos):
    invalidacoes, aprovacoes, correcoes = {}, {}, {}
    manuais = []
    historico = {}
    for ajuste in sorted(ajustes, key=lambda a: (a.decidido_em or a.criado_em, a.criado_em, str(a.id))):
        if ajuste.status != StatusAjuste.APROVADO:
            avisos[ajuste.ocorrido_em_proposto.astimezone(zona).date()].add("AJUSTE_W10_REQUER_APURACAO")
            original = next((p for p in pontos if p.id == ajuste.registro_ponto_id), None)
            if original:
                avisos[original.ocorrido_em.astimezone(zona).date()].add("AJUSTE_W10_REQUER_APURACAO")
            continue
        if ajuste.tipo_ocorrencia != TipoOcorrencia.AJUSTE.value:
            historico.setdefault(ajuste.registro_ponto_id, []).append(auditoria(ajuste))
        elif ajuste.registro_ponto_id is not None:
            # Somente a correção aprovada mais recente substitui o original na projeção.
            correcoes[ajuste.registro_ponto_id] = ajuste
        else:
            manuais.append(ajuste)

    for registro_id, decisoes in historico.items():
        decisoes.sort(key=lambda d: d["sequencia_decisao"])
        atual = decisoes[-1]
        if atual["tipo_ocorrencia"] == TipoOcorrencia.INVALIDACAO_GESTOR.value:
            invalidacoes[registro_id] = atual
        else:
            aprovacoes[registro_id] = atual

    def alocacao(instante, preferida=None):
        dia = instante.astimezone(zona).date()
        candidatas = [a for a, _, _ in linhas if a.data_inicio <= dia and (a.data_fim is None or a.data_fim >= dia)]
        if preferida is not None and any(a.id == preferida for a in candidatas):
            return preferida
        if len(candidatas) == 1:
            return candidatas[0].id
        avisos[dia].add("AJUSTE_SEM_ALOCACAO_UNIVOCA")
        return None

    efetivos = []
    for ponto in pontos:
        if ponto.id in invalidacoes:
            continue
        correcao = correcoes.get(ponto.id)
        aid = alocacao(correcao.ocorrido_em_proposto, ponto.alocacao_id) if correcao else ponto.alocacao_id
        if aid is not None:
            efetivos.append(SimpleNamespace(id=ponto.id, alocacao_id=aid,
                tipo=correcao.tipo_proposto if correcao else ponto.tipo,
                ocorrido_em=correcao.ocorrido_em_proposto if correcao else ponto.ocorrido_em,
                situacao=SituacaoPonto.ACEITA if correcao or ponto.id in aprovacoes else ponto.situacao))
    for ajuste in manuais:
        aid = alocacao(ajuste.ocorrido_em_proposto)
        if aid is not None:
            efetivos.append(SimpleNamespace(id=ajuste.id, alocacao_id=aid, tipo=ajuste.tipo_proposto,
                ocorrido_em=ajuste.ocorrido_em_proposto, situacao=SituacaoPonto.ACEITA))
    # Ordenação estável conserva a ordem de recebimento nos instantes iguais.
    efetivos.sort(key=lambda p: p.ocorrido_em)
    return efetivos, invalidacoes, aprovacoes, correcoes, manuais, historico
