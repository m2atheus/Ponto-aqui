# Alocações por tempo indeterminado

Ao criar uma alocação, `data_fim` pode ser `null`, com ou sem escala. O vínculo permanece vigente até que o RH informe uma data de encerramento; o histórico é preservado.

O cadastro de funcionário é suficiente para alocá-lo em um setor e uma escala. A validação de conflitos usa `funcionario_id` e não exige uma conta de login. O acesso ao aplicativo pode ser gerado depois pelo RH; esse vínculo preenche o `usuario_id` das alocações anteriores sem alterar seu histórico.

Quando há escala e o fim é nulo, o motor verifica conflitos por **10 anos a partir da data de início**. Esse horizonte limita somente a validação: a API não grava uma data final artificial na alocação. Para início em 29 de fevereiro, usa 28 de fevereiro se o ano de destino não for bissexto.

O POST retorna `validacao_escala`, com `periodo_indeterminado: true`, `horizonte_anos: 10` e `ate` indicando a última data verificada. Conflitos posteriores ao horizonte não são verificados nessa operação.

Se uma data final for informada, deve ser válida e não pode ser anterior ao início. A operação de **encerrar** uma alocação continua exigindo uma data final explícita.

## Mudar escala ou setor

RH e Gestor podem usar **Equipe → Histórico → Mudar Escala/Setor**. O RH também encontra a ação em **Alocações**. Para o Gestor, o formulário mantém um alerta sobre o impacto no espelho e nas horas extras. Cadastro avulso e encerramento continuam exclusivos do RH.

Em **Alocações**, a ação principal agora é **Transferir**. O formulário mostra funcionário, setor e escala atuais; sugere encerramento hoje e início no dia seguinte. Ao ajustar o encerramento, o início acompanha a sugestão até ser editado manualmente. As buscas de setor e escala são assíncronas. Linhas com fim passado usam fundo discreto; um fim agendado ainda permite transferência. O ícone secundário permite somente encerrar.

`POST /api/web/funcionarios/<funcionario_id>/mudar-alocacao`, com JWT da empresa:

```json
{
  "alocacao_id": "UUID-DO-VINCULO-ANTERIOR",
  "novo_setor_id": "UUID-DO-SETOR",
  "nova_escala_id": "UUID-DA-ESCALA-OU-NULL",
  "data_transicao": "2026-11-04"
}
```

Use `null` em `nova_escala_id` para ficar sem escala. `alocacao_id` identifica o vínculo quando há mais de uma alocação vigente. A data deve ser posterior ao início e estar dentro da vigência do vínculo anterior, que precisa estar aberto ou ter fim não passado no fuso da empresa.

O formulário de transferência envia também `data_encerramento` (AAAA-MM-DD), obrigatória nessa interface e opcional para clientes anteriores da API. Quando fornecida, deve estar dentro da vigência anterior e ser estritamente anterior a `data_transicao`. A nova alocação pode começar dias depois do encerramento; esses dias ficam sem o vínculo transferido. A API grava exatamente as duas datas na mesma transação. Se a propriedade for omitida, permanece a regra anterior de encerrar no dia anterior à transição.

Em uma única transação, a API define somente `data_fim` do vínculo antigo (dia anterior à transição), valida os conflitos e cria outro vínculo com fim nulo. Retorna HTTP 201 com `alocacao_anterior` e `alocacao`. Uma falha desfaz ambas as operações. A marcação de ponto original e suas referências históricas permanecem intactas. Plantões noturnos da escala anterior ainda participam da checagem de conflitos. Novas escalas abertas usam o horizonte de dez anos descrito acima.

As buscas do formulário usam `GET /api/web/alocacoes/opcoes-mudanca?tipo=setor&q=...` (ou `tipo=escala`), sempre restritas à empresa, com até 20 opções ativas por chamada. Foco vazio carrega imediatamente; digitação aguarda 500 ms. As opções não concedem acesso ao CRUD de setores ou escalas ao Gestor.
