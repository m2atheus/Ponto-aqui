# Fundação W04–W07

Esta etapa acrescenta modelos e cálculos puros. Após a validação, foram adicionados
o motor de conflitos W05, o Service de dispositivos e o decorator W07 descritos
abaixo. Os novos endpoints ainda aguardam a validação dos Services.
A migration `0004_w04_w07` parte da revisão
`0003` presente no repositório e **não foi aplicada no Supabase**.

## Estrutura de dados

- `Escala`/`Escalas`: nome, empresa, modelo, tipo semanal/cíclico, referência,
  turnos ordenados, carga semanal, tolerância, ativo e JSON legado.
- `Turno`/`Turnos`: início/fim locais com precisão de minutos, intervalo em
  minutos, dias ISO (segunda=1, domingo=7), ordem e `fim_dia_seguinte`.
- `Feriado`/`Feriados`: data, descrição, empresa e setor opcional. Setor vazio
  aplica o feriado à empresa inteira; há proteção contra duplicatas por escopo.
- `Afastamento`/`Afastamentos`: funcionário, tipo, início/fim inclusivos,
  descrição e anexo opcional. Uma exclusão GiST impede sobreposições, inclusive
  em inserções concorrentes. O dia final pertence ao afastamento.
- `Dispositivo`/`Dispositivos`: UUID do app, tipo, nome, ativo e último acesso.
  PESSOAL tem exclusivamente `usuario_id`; RELOGIO tem exclusivamente `setor_id`.
  A conta do setor será autorizada pelo Service usando esse vínculo, sem tratar
  o relógio como um aparelho pessoal do funcionário.

As referências compostas `(id, empresa_id)` impedem vínculos entre empresas.
Índices cobrem consultas por empresa, datas, funcionário, escala e dispositivo.
RLS nos novos objetos mantém o bloqueio de acesso direto pelo SDK publicável;
o backend continuará responsável por filtros de empresa e autorização via JWT.

Os quatro modelos são `24x72`, `12x36`, `Diurno` e `5x2`. `Legado` preserva
escalas anteriores sem inventar turnos a partir de um JSON desconhecido. O futuro
Service de cadastro deve exigir um dos quatro modelos e seus turnos; `Legado`
não é uma opção para novos cadastros pela API. Escalas cíclicas exigem referência.
`Diurno` aceita turnos separados de manhã/tarde; `5x2` usa dias 1–5 e intervalo.
Validações que dependem de combinar todos os turnos pertencem ao próximo Service.

Dispositivos existentes recebem `device_uuid = id`, mantendo as referências de
W09. Novos clientes deverão fornecer o UUID criado pelo app no futuro cadastro;
o default Python só mantém compatibilidade com os consumidores atuais. O UUID
não substitui JWT nem comprova sozinho a identidade do aparelho. W09 e o login
atual continuam utilizando `dispositivo_id`; a transição de contrato será feita
na etapa de Services, incluindo o fluxo de relógio, header e revogação.

## Utilitário de datas

```python
from app.utils.time_calculator import TimeCalculator

assert TimeCalculator.calcular_duracao_turno("19:00", "07:00") == 720
assert TimeCalculator.calcular_duracao_turno("08:00", "17:00", 60) == 480
assert TimeCalculator.calcular_duracao_turno(
    "08:00", "08:00", fim_dia_seguinte=True,
) == 1440

dias = TimeCalculator.projetar_escala_ciclica(
    modelo="12x36", data_referencia="2026-01-01",
    hora_inicio="19:00", hora_fim="07:00", n_dias=7,
    data_inicio="2026-01-02", fuso_horario="America/Sao_Paulo",
)
```

A duração retornada é líquida em minutos. Para plantões 12x36/24x72, a duração
bruta deve ser 720/1440 minutos e o próximo início ocorre após 48/96 horas reais.
Intervalos não deslocam o ciclo nem liberam uma janela para outra escala: ainda
não temos o horário exato da pausa. A jornada líquida do plantão não deve ser
somada novamente em cada dia em que ele aparece.

A projeção retorna exatamente N objetos JSON, cada um com `data`, `trabalha` e
`intervalos`. `trabalha` indica qualquer ocupação no dia, incluindo a madrugada
de um turno anterior. Os intervalos `inicio`/`fim` são recortados pela janela do
dia e seguem `[início, fim)`. `inicio_turno`/`fim_turno` preservam o plantão
original: use esse par para deduplicar plantões ao somar jornadas líquidas.
Término à meia-noite não ocupa o dia seguinte. Não há plantões anteriores à
referência; consultas futuras calculam diretamente a fase do ciclo.

Os timestamps incluem offset do fuso. Em horário de verão os ciclos mantêm horas
reais, podendo mudar a hora local de início. Referências ambíguas/inexistentes
são rejeitadas. `tzdata` fornece os fusos no Windows. O cálculo é puro e não
consulta banco, aplica feriados/afastamentos ou decide conflitos.

## Services W05/W07

`CheckScheduleConflictService.validar_alocacao(empresa_id, usuario_id, escala_id,
data_inicio, data_fim, session=...)` retorna `(JSON, status)`: 200 em sucesso,
409 com escala, setor, alocação e horários do conflito; 400 para configurações
não projetáveis e 404 para vínculos indisponíveis na empresa. A empresa vem do
JWT do solicitante; `usuario_id` identifica o funcionário a alocar. A autorização
do RH/Gestor será feita pelo futuro Service de cadastro.

O período deve ter fim explícito e no máximo 3660 dias: o motor não aprova uma
alocação indefinida usando uma amostra limitada do futuro. Vigências usam datas
inclusivas de início de plantão. A projeção inclui o turno completo e compara
também a madrugada de alocações encerradas, em qualquer setor. Escalas antigas
desativadas continuam ocupando os horários históricos; referências sem turnos
estruturados são recusadas em vez de silenciosamente ignoradas. Plantões cíclicos
aceitam componentes ordenados dentro da janela de 12/24 horas.

O motor mantém lock do usuário/funcionário até o caller inserir a alocação e
confirmar **a mesma transação**. Ele não insere dados nem faz commit em sucesso.
O caller deve finalizar a transação também quando recebe erro. Esse protocolo
foi testado com duas alocações simultâneas em setores diferentes.

`DeviceService.registrar_login_pessoal(empresa_id, usuario_id, device_uuid, nome)`
é chamado **depois da senha validada**. Ele confirma atomicamente o cadastro/
reativação do aparelho e a inativação dos demais aparelhos pessoais do usuário.
O retorno contém o ID, UUID, tipo, ativo e último acesso. O futuro login emite o
JWT com `dispositivo_id` após esse sucesso; pode incluir também `device_uuid`.
Não chamar esse método em transação com outras alterações pendentes: ele faz
commit em sucesso e rollback em falha. Não altera relógios nem outras empresas,
não transfere UUIDs entre contas e preserva os registros de dispositivos antigos.

`@require_device_uuid`, em `app/middleware/device_middleware.py`, verifica o JWT
e chama o Service com o header `X-Device-UUID`. Token ausente/expirado retorna 401;
com token válido, header ausente/inválido, aparelho inativo, UUID desconhecido,
ou vínculo incompatível retornam 403. O UUID deve corresponder ao `dispositivo_id`
da sessão, impedindo reutilizar o token de um aparelho revogado com outro header.
O aparelho autorizado fica disponível em `g.dispositivo`. Para relógios, o futuro
login de conta de setor também deve emitir `setor_id` validado; o decorator exige
esse vínculo e o papel de conta do setor. Falhas de banco retornam 503.

O decorator ainda não foi aplicado às rotas W09 existentes, nem o novo Service
foi ligado ao login atual. Essa integração será feita na etapa de Controllers;
as APIs atuais preservam seu contrato de `dispositivo_id`.

## Próxima etapa

O motor W05 já cruza os intervalos entre todos os setores. A exclusão de datas
da alocação W03 continua vigente nesta fundação; deve ser revisada junto ao motor
de cadastro para admitir múltiplas alocações no mesmo setor com turnos sem conflito.

Na troca de escala, o Service encerrará a alocação anterior e criará outra,
preservando IDs, datas e vínculos históricos. A definição de uma escala já usada
também precisará de versionamento/proteção para que mudanças de turnos não
alterem espelhos antigos. Estes fluxos e a apuração de feriados/afastamentos
não estão implementados nesta etapa de modelos.

O downgrade fica bloqueado se destruir dados novos de turnos, feriados,
afastamentos, modelos de escala ou dispositivos. A aplicação online da migration
depende da validação solicitada e da conferência da revisão real do banco.
