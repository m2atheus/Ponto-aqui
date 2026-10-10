# Gestão de jornada no painel

As telas usam a API Flask e os dados da empresa autenticada. Cadastros continuam
disponíveis ao atualizar a página ou abrir o painel em outro computador.

## Preparar e executar

1. Configure o `.env` conforme o [README](../README.md).
2. Na raiz, aplique as migrations, incluindo `0006` e `0007`:

   ```powershell
   .\.venv\Scripts\python.exe -m flask --app app:create_app db upgrade heads
   .\.venv\Scripts\python.exe run.py
   ```

3. Em outro terminal:

   ```powershell
   cd admin_web
   flutter pub get
   flutter run -d chrome --web-port=3000 --dart-define=ENABLE_MOCK_AUTH=false
   ```

4. Entre com o **RH real da empresa**. Superadmin cadastra empresas e contas RH;
   a conta de demonstração permite somente navegação.

## Usar as telas

| Tela | O que fazer |
| --- | --- |
| Escalas | Cadastre os turnos e o modelo: 5x2, Diurno, 12x36 ou 24x72. Ciclos exigem data de referência; jornadas de 24 horas exigem saída no dia seguinte. |
| Alocações | Selecione funcionário, setor e escala. Com escala, informe o período completo para a API validar conflitos. Encerrar preenche a data final e mantém a linha histórica. |
| Justificativas → Feriados | Cadastre data, descrição e setor, ou selecione Empresa inteira. Edite ou remova usando os ícones da tabela. |
| Justificativas → Afastamentos | Selecione funcionário, tipo e período. Use Anexar arquivo para enviar o atestado junto ao cadastro. Períodos sobrepostos são recusados. |
| Equipe | Pesquise um funcionário e abra seu histórico de setores/escalas, incluindo períodos encerrados. |
| Relatórios | Selecione funcionário e mês/ano. O Flask retorna horas e situações conforme o histórico, feriados e afastamentos vigentes no período. |

Remoções exigem confirmação e afetam os abonos dos relatórios. Escalas usadas
em alocações devem ser desativadas; seus turnos não podem ser reescritos.
O Gestor tem leitura de Equipe e Justificativas; somente RH altera cadastros
e consulta Relatórios. Marcações de ponto permanecem imutáveis.

## Anexos e relatórios

Atestados aceitam PDF, PNG ou JPEG de até **10 MB**. O arquivo fica em
`anexos_afastamento`, vinculado ao afastamento na mesma transação. O botão de
download usa JWT e valida a empresa; o endereço não é público. Na edição,
é possível substituir ou remover o arquivo. Excluir o afastamento remove seu anexo.

O espelho separa horas por dia civil no fuso da empresa e distribui intervalos
sem horário proporcionalmente. Abonos parciais e pendências aparecem na tela;
a apuração permanece preliminar, conforme o contrato atual do backend.
Consulte [as regras do espelho](W06-espelho.md).

## Endpoints

Todos usam o prefixo `/api/web`, JWT e empresa extraída da sessão no backend.

| Recurso | Métodos |
| --- | --- |
| `/dashboard` | GET: indicadores reais da empresa. |
| `/escalas`, `/escalas/{id}` | GET, POST; PUT e DELETE por ID. |
| `/equipe` | GET: funcionários, setores e histórico de alocações. |
| `/feriados`, `/feriados/{id}` | GET, POST; PUT e DELETE por ID. |
| `/afastamentos`, `/afastamentos/{id}` | GET, POST; PUT e DELETE por ID. POST/PUT aceitam JSON ou multipart com campo `anexo`. |
| `/afastamentos/{id}/anexo` | GET: download privado do arquivo. |
| `/relatorios/espelho` | GET com `funcionario_id`, `ano` e `mes`. |

Falhas mantêm o formulário aberto e exibem mensagem limpa. Não há cadastro
local alternativo quando a API estiver indisponível. Os testes Flutter simulam
apenas o transporte HTTP; os testes Flask exercitam PostgreSQL isolado.
